-- #6 lobby foundation. #7 owns verified arrivals, match start and scoring.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
alter default privileges in schema private revoke execute on functions from public;

create table private.arena_courses (
  id text not null, version text not null, start_node_id text not null,
  surveyed boolean not null default false, primary key (id, version)
);
-- Lobby registration does not certify the outdoor course.
insert into private.arena_courses values
  ('gilmorehill-jms-library', 'candidate-2026-10-17-1', '01-jms', false);
create table private.arena_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[0-9A-F]{10}$'),
  creator_id uuid not null references auth.users(id),
  course_id text not null, course_version text not null,
  algorithm text not null check (algorithm in ('dijkstra', 'aStar')),
  phase text not null default 'lobby' check (phase in
    ('lobby', 'practice', 'active', 'awaitingFinish', 'finished', 'incomplete')),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  foreign key (course_id, course_version) references private.arena_courses(id, version)
);
create index arena_rooms_creator on private.arena_rooms(creator_id);
create index arena_rooms_course on private.arena_rooms(course_id, course_version);
create table private.arena_players (
  room_id uuid not null references private.arena_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  -- Independent capacity invariant, even if command code regresses.
  seat smallint not null check (seat in (1, 2)),
  nickname text not null check (char_length(nickname) between 1 and 24
    and nickname = btrim(nickname) and nickname !~ '[[:cntrl:]]'),
  algorithm_confirmed boolean not null default false,
  ready boolean not null default false check (not ready or algorithm_confirmed),
  -- Only server arrival validation in #7 may populate this field.
  start_arrival_method text check (start_arrival_method in ('location', 'organiserApproval')),
  primary key (room_id, user_id), unique (room_id, seat)
);
create index arena_players_user on private.arena_players(user_id);
create table private.arena_command_receipts (
  user_id uuid not null references auth.users(id), command_id uuid not null,
  room_id uuid not null references private.arena_rooms(id) on delete cascade,
  command jsonb not null, receipt jsonb not null,
  created_at timestamptz not null default now(), primary key (user_id, command_id)
);
create index arena_command_receipts_room on private.arena_command_receipts(room_id);
-- No answers, locations, nicknames, scores or snapshot bodies enter replication.
create table public.arena_invalidations (
  "matchID" uuid primary key references private.arena_rooms(id) on delete cascade,
  revision integer not null check (revision > 0)
);
alter table public.arena_invalidations enable row level security;
alter table private.arena_courses enable row level security;
alter table private.arena_rooms enable row level security;
alter table private.arena_players enable row level security;
alter table private.arena_command_receipts enable row level security;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on public.arena_invalidations from public, anon, authenticated;
grant select on public.arena_invalidations to authenticated;

-- Privileged implementations live outside exposed schemas. Each entry point
-- checks auth.uid(); RPC never accepts a caller-supplied player ID.
create function private.arena_is_member(room_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and exists (
    select 1 from private.arena_players p
    where p.room_id = $1 and p.user_id = (select auth.uid())
  );
$$;
create policy arena_member_invalidations on public.arena_invalidations
for select to authenticated using (private.arena_is_member("matchID"));
alter publication supabase_realtime add table public.arena_invalidations;

create function private.arena_fail(code text, message text, revision integer default null)
returns void language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = 'P0001', message =
    jsonb_strip_nulls(jsonb_build_object('code', code, 'message', message,
      'currentRevision', revision))::text;
end;
$$;
create function private.arena_snapshot(match_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  principal uuid := auth.uid(); room private.arena_rooms;
  players jsonb; start_node text;
begin
  if principal is null then
    perform private.arena_fail('unauthenticated', 'Restore your player session.');
  end if;
  -- Same error for absent/non-member rooms; share lock keeps the projection coherent.
  select * into room from private.arena_rooms r
    where r.id::text = match_id and private.arena_is_member(r.id) for share;
  if not found then
    perform private.arena_fail('notMember', 'This session is not a member of that room.');
  end if;
  select start_node_id into start_node from private.arena_courses
    where id = room.course_id and version = room.course_version;
  select jsonb_agg(jsonb_build_object(
    'id', p.user_id, 'nickname', p.nickname,
    'algorithmConfirmed', p.algorithm_confirmed, 'ready', p.ready,
    'connection', 'online', 'stage', jsonb_build_object('atStart', '{}'::jsonb),
    'arrivals', case when p.start_arrival_method is null then '[]'::jsonb else
      jsonb_build_array(jsonb_build_object('nodeID', start_node,
        'method', p.start_arrival_method)) end,
    'completedChallengeIDs', '[]'::jsonb, 'releasedScore', 0,
    'pendingRewardMaximum', 0, 'remainingAvailablePoints', 100
  ) order by p.seat) into players from private.arena_players p where p.room_id = room.id;
  return jsonb_build_object('contractVersion', 1, 'revision', room.revision,
    'serverTime', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'room', jsonb_build_object('matchID', room.id, 'roomCode', room.code,
      'creatorID', room.creator_id,
      'course', jsonb_build_object('id', room.course_id, 'version', room.course_version),
      'algorithm', room.algorithm, 'phase', room.phase, 'players', players),
    'viewer', jsonb_build_object('playerID', principal, 'submissions', '[]'::jsonb,
      'feedback', '[]'::jsonb, 'availableChallenges', '[]'::jsonb));
end;
$$;
create function private.arena_command(command jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  principal uuid := auth.uid(); v_command_id uuid; action_name text;
  payload jsonb; scope jsonb; room private.arena_rooms; player private.arena_players;
  previous private.arena_command_receipts; nickname text; selected_algorithm text;
  room_code text; result jsonb; member_count integer;
begin
  if principal is null then
    perform private.arena_fail('unauthenticated', 'Restore your player session.');
  end if;
  if jsonb_typeof(command) is distinct from 'object'
     or not command ?& array['contractVersion', 'id', 'scope', 'action']
     or command - array['contractVersion', 'id', 'scope', 'action'] <> '{}'::jsonb then
    perform private.arena_fail('invalidCommand', 'Expected a MatchCommand envelope.');
  end if;
  if command->'contractVersion' is distinct from '1'::jsonb then
    perform private.arena_fail('incompatibleContract', 'This server supports contract version 1.');
  end if;
  if jsonb_typeof(command->'id') is distinct from 'string' then
    perform private.arena_fail('invalidCommand', 'A UUID command ID is required.');
  end if;
  begin
    v_command_id := (command->>'id')::uuid;
  exception when invalid_text_representation then
    perform private.arena_fail('invalidCommand', 'A UUID command ID is required.');
  end;
  -- Same-session retries serialize BEFORE revision validation or room locks.
  perform pg_advisory_xact_lock(hashtextextended(principal::text, 0));
  select * into previous from private.arena_command_receipts cr
    where cr.user_id = principal and cr.command_id = v_command_id;
  if found then
    if previous.command <> command then
      perform private.arena_fail('idempotencyConflict', 'That command ID has a different payload.');
    end if;
    if not private.arena_is_member(previous.room_id) then
      perform private.arena_fail('notMember', 'That receipt is not available to this session.');
    end if;
    return previous.receipt;
  end if;
  if jsonb_typeof(command->'action') is distinct from 'object' then
    perform private.arena_fail('invalidCommand', 'Exactly one action is required.');
  end if;
  if (select count(*) from jsonb_object_keys(command->'action')) <> 1 then
    perform private.arena_fail('invalidCommand', 'Exactly one action is required.');
  end if;
  select key, value into action_name, payload from jsonb_each(command->'action');
  if jsonb_typeof(payload) is distinct from 'object' then
    perform private.arena_fail('invalidCommand', 'Action parameters must be an object.');
  end if;
  if action_name in ('createRoom', 'joinRoom') then
    if command->'scope' is distinct from '{"roomEntry":{}}'::jsonb then
      perform private.arena_fail('invalidCommand', 'Room entry requires roomEntry scope.');
    end if;
    if jsonb_typeof(payload->'nickname') is distinct from 'string' then
      perform private.arena_fail('invalidCommand', 'Enter a nickname of 1 to 24 characters.');
    end if;
    nickname := btrim(payload->>'nickname');
    if char_length(nickname) not between 1 and 24 or nickname ~ '[[:cntrl:]]' then
      perform private.arena_fail('invalidCommand', 'Enter a nickname of 1 to 24 characters.');
    end if;
    if action_name = 'createRoom' then
      if not payload ?& array['nickname', 'algorithm', 'course']
         or payload - array['nickname', 'algorithm', 'course'] <> '{}'::jsonb
         or payload->>'algorithm' not in ('dijkstra', 'aStar')
         or jsonb_typeof(payload->'algorithm') is distinct from 'string' then
        perform private.arena_fail('invalidCommand', 'Choose Dijkstra or A*.');
      end if;
      if jsonb_typeof(payload->'course') is distinct from 'object'
         or (payload->'course') - array['id', 'version'] <> '{}'::jsonb
         or not exists (select 1 from private.arena_courses c
           where c.id = payload->'course'->>'id' and c.version = payload->'course'->>'version') then
        perform private.arena_fail('incompatibleCourse', 'Refresh the supported course version.');
      end if;
      loop
        room_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
        begin
          insert into private.arena_rooms(code, creator_id, course_id, course_version, algorithm)
          values (room_code, principal, payload->'course'->>'id',
            payload->'course'->>'version', payload->>'algorithm') returning * into room;
          exit;
        exception when unique_violation then null;
        end;
      end loop;
      insert into private.arena_players(room_id, user_id, seat, nickname)
        values (room.id, principal, 1, nickname);
    else
      if not payload ?& array['code', 'nickname']
         or payload - array['code', 'nickname'] <> '{}'::jsonb
         or jsonb_typeof(payload->'code') is distinct from 'string' then
        perform private.arena_fail('invalidCommand', 'Enter the shared room code.');
      end if;
      room_code := upper(btrim(payload->>'code'));
      if room_code !~ '^[0-9A-F]{10}$' then
        perform private.arena_fail('roomNotFound', 'No room has that code. Check and try again.');
      end if;
      select * into room from private.arena_rooms r where r.code = room_code for update;
      if not found then
        perform private.arena_fail('roomNotFound', 'No room has that code. Check and try again.');
      end if;
      select * into player from private.arena_players p
        where p.room_id = room.id and p.user_id = principal;
      if found then
        if player.nickname <> nickname then
          perform private.arena_fail('invalidCommand', 'This session already joined with another nickname.');
        end if;
      else
        if room.phase <> 'lobby' then
          perform private.arena_fail('invalidPhase', 'This room is no longer accepting players.');
        end if;
        select count(*) into member_count from private.arena_players p where p.room_id = room.id;
        if member_count >= 2 then
          perform private.arena_fail('roomFull', 'This room already has two players.');
        end if;
        insert into private.arena_players(room_id, user_id, seat, nickname)
          values (room.id, principal, 2, nickname);
        update private.arena_rooms set revision = revision + 1 where id = room.id returning * into room;
      end if;
    end if;
  else
    if jsonb_typeof(command->'scope') is distinct from 'object'
       or (command->'scope') - 'match' <> '{}'::jsonb
       or jsonb_typeof(command->'scope'->'match') is distinct from 'object' then
      perform private.arena_fail('invalidCommand', 'This action requires match scope.');
    end if;
    scope := command->'scope'->'match';
    if not scope ?& array['matchID', 'course', 'expectedRevision']
       or scope - array['matchID', 'course', 'expectedRevision'] <> '{}'::jsonb
       or jsonb_typeof(scope->'matchID') is distinct from 'string'
       or jsonb_typeof(scope->'expectedRevision') is distinct from 'number'
       or (scope->>'expectedRevision') !~ '^[0-9]{1,9}$' then
      perform private.arena_fail('invalidCommand', 'Match, course and integer revision are required.');
    end if;
    select * into room from private.arena_rooms r
      where r.id::text = scope->>'matchID' and private.arena_is_member(r.id) for update;
    if not found then
      perform private.arena_fail('notMember', 'This session is not a member of that room.');
    end if;
    if scope->'course' is distinct from jsonb_build_object('id', room.course_id, 'version', room.course_version) then
      perform private.arena_fail('incompatibleCourse', 'Refresh the supported course version.');
    end if;
    if (scope->>'expectedRevision')::integer <> room.revision then
      perform private.arena_fail('staleRevision', 'Refresh the room before trying again.', room.revision);
    end if;
    if room.phase <> 'lobby' then
      perform private.arena_fail('invalidPhase', 'Lobby actions require an open lobby.');
    end if;
    select * into player from private.arena_players p
      where p.room_id = room.id and p.user_id = principal;
    if action_name in ('selectAlgorithm', 'confirmAlgorithm') then
      selected_algorithm := payload->>'algorithm';
      if not payload ? 'algorithm' or payload - 'algorithm' <> '{}'::jsonb
         or selected_algorithm not in ('dijkstra', 'aStar')
         or jsonb_typeof(payload->'algorithm') is distinct from 'string' then
        perform private.arena_fail('invalidCommand', 'Choose Dijkstra or A*.');
      end if;
      if action_name = 'selectAlgorithm' then
        if principal <> room.creator_id then
          perform private.arena_fail('invalidCommand', 'Only the room creator can change the algorithm.');
        end if;
        if room.algorithm <> selected_algorithm then
          update private.arena_rooms set algorithm = selected_algorithm where id = room.id;
          update private.arena_players set algorithm_confirmed = false, ready = false where room_id = room.id;
        end if;
      else
        if selected_algorithm <> room.algorithm then
          perform private.arena_fail('algorithmNotConfirmed', 'Confirm the current shared algorithm.');
        end if;
        update private.arena_players set algorithm_confirmed = true
          where room_id = room.id and user_id = principal;
      end if;
    elsif action_name = 'setReady' then
      if not payload ? 'ready' or payload - 'ready' <> '{}'::jsonb
         or jsonb_typeof(payload->'ready') is distinct from 'boolean' then
        perform private.arena_fail('invalidCommand', 'Ready must be a boolean.');
      end if;
      if (payload->>'ready')::boolean and not player.algorithm_confirmed then
        perform private.arena_fail('algorithmNotConfirmed', 'Confirm the shared algorithm before becoming ready.');
      end if;
      update private.arena_players set ready = (payload->>'ready')::boolean
        where room_id = room.id and user_id = principal;
    elsif action_name = 'start' then
      if payload <> '{}'::jsonb or principal <> room.creator_id then
        perform private.arena_fail('invalidCommand', 'Only the room creator can start.');
      end if;
      if (select count(*) from private.arena_players p where p.room_id = room.id) <> 2
         or exists (select 1 from private.arena_players p where p.room_id = room.id
           and (not p.algorithm_confirmed or not p.ready)) then
        perform private.arena_fail('algorithmNotConfirmed', 'Both players must confirm and become ready.');
      end if;
      if exists (select 1 from private.arena_players p where p.room_id = room.id
        and p.start_arrival_method is null) then
        perform private.arena_fail('arrivalRequired', 'Both players must verify arrival at the shared start.');
      end if;
      perform private.arena_fail('serviceUnavailable', 'Match start will be enabled with the match rules.');
    else
      perform private.arena_fail('invalidCommand', 'This action is not implemented by the lobby service.');
    end if;
    update private.arena_rooms set revision = revision + 1 where id = room.id returning * into room;
  end if;
  insert into public.arena_invalidations("matchID", revision) values (room.id, room.revision)
    on conflict ("matchID") do update set revision = excluded.revision
    where arena_invalidations.revision < excluded.revision;
  result := jsonb_build_object('commandID', v_command_id, 'acceptedRevision', room.revision,
    'snapshot', private.arena_snapshot(room.id::text));
  insert into private.arena_command_receipts(user_id, command_id, room_id, command, receipt)
    values (principal, v_command_id, room.id, command, result);
  return result;
end;
$$;
-- Invoker wrappers have no privileged context; private entry points authorize.
create function public.arena_command(command jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.arena_command(command); $$;
create function public.arena_snapshot(match_id text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.arena_snapshot(match_id); $$;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.arena_is_member(uuid), private.arena_command(jsonb),
  private.arena_snapshot(text) to authenticated;
revoke all on function public.arena_command(jsonb), public.arena_snapshot(text) from public, anon;
grant execute on function public.arena_command(jsonb), public.arena_snapshot(text) to authenticated;
