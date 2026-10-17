-- Independent indoor battles preserve the existing campus match contract.
create table private.battle_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 20),
  avatar text not null default 'person.crop.circle.fill' check (avatar in ('person.crop.circle.fill','hare.fill','tortoise.fill','bird.fill'))
);
create table private.battles (
  id uuid primary key default gen_random_uuid(), code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  host uuid not null references private.battle_profiles(id),
  phase text not null default 'lobby' check (phase in ('lobby','playing','finished','abandoned')),
  winner uuid references private.battle_profiles(id), started_at timestamptz, finished_at timestamptz,
  created_at timestamptz not null default now(), rematch uuid references private.battles(id)
);
create table private.battle_seats (
  battle uuid not null references private.battles(id) on delete cascade,
  player uuid not null references private.battle_profiles(id), seat int not null check (seat in (1,2)),
  ready boolean not null default false, score int not null default 0 check (score between 0 and 100),
  round int not null default 1, correct int not null default 0, attempts int not null default 0,
  round_started timestamptz, last_seen timestamptz not null default now(), last_attempt timestamptz, round_attempts int not null default 0,
  primary key(battle,player), unique(battle,seat)
);
create index battle_seats_player on private.battle_seats(player);
create table private.battle_answers (
  battle uuid not null references private.battles(id) on delete cascade, round int not null,
  prompt jsonb not null, answer jsonb not null, explanation text not null,
  primary key(battle,round)
);
create table private.battle_results (
  battle uuid not null references private.battles(id), player uuid not null references private.battle_profiles(id),
  opponent uuid not null references private.battle_profiles(id), won boolean not null,
  score int not null, difficulty text not null, completed_at timestamptz not null default now(),
  primary key(battle,player)
);
-- One temporary position per participant, never a history. Expiry/stop clears both.
create table private.battle_configuration (id boolean primary key default true check(id), cleanup_ready boolean not null default false);
insert into private.battle_configuration(id) values(true);
create table private.battle_sharing (
  battle uuid primary key references private.battles(id) on delete cascade,
  requester uuid not null references private.battle_profiles(id), accepted boolean not null default false,
  expires_at timestamptz not null default now()+interval '10 minutes', positions jsonb not null default '{}'
);
create table public.battle_invalidations (
  id uuid primary key references private.battles(id) on delete cascade, revision bigint not null default 1
);
alter table public.battle_invalidations enable row level security;
create function private.battle_member(battle_id uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.battle_seats where battle=$1 and player=auth.uid());
$$;
create policy battle_member_read on public.battle_invalidations for select to authenticated using (private.battle_member(id));
grant select on public.battle_invalidations to authenticated;
alter publication supabase_realtime add table public.battle_invalidations;

create function private.battle_difficulty(round_number int) returns text language sql immutable set search_path='' as $$
  select case when $1<=2 then 'Easy' when $1<=4 then 'Medium' when $1=5 then 'Hard' else 'Advanced' end;
$$;

-- Shared per-room/per-round challenge. Answers never enter the public projection.
create function private.battle_challenge(battle_id uuid, round_number int) returns void
language plpgsql set search_path='' as $$
declare n int:=least(4+round_number,12); kind int:=(round_number-1)%7;
  nodes jsonb:='[]'; edges jsonb:='[]'; values_json jsonb; solution jsonb:='[]';
  graph_costs int[]; dist int[]; prev int[]; visited boolean[]; current_node int; best int; candidate int; goal int; path int[];
  a int; b int; weight int; i int; j int; item jsonb; title text; rule text; algorithm text; explanation text;
begin
  if exists(select 1 from private.battle_answers where battle=battle_id and round=round_number) then return; end if;
  if kind=4 then
    select jsonb_agg(v order by random()) into values_json from generate_series(1,n) v;
    select jsonb_agg(v order by v) into solution from generate_series(1,n) v;
    insert into private.battle_answers values (battle_id,round_number,
      jsonb_build_object('round',round_number,'kind','sort','title','Sorting · arrange the values','rule','Tap two values to swap them. Submit the ascending order.','nodes','[]'::jsonb,'edges','[]'::jsonb,'values',values_json,'difficulty',private.battle_difficulty(round_number)),
      solution,'Sorting places each value in order. Selection sort repeatedly chooses the smallest remaining value; insertion sort inserts each value into a sorted prefix.');
    return;
  end if;
  if kind=5 then
    n:=7+2*least(round_number,8);
    goal:=1+floor(random()*n)::int; a:=1; b:=n;
    while a<=b loop
      i:=(a+b)/2; solution:=solution||to_jsonb(i);
      exit when i=goal;
      if i<goal then a:=i+1; else b:=i-1; end if;
    end loop;
    select jsonb_agg(v order by v) into values_json from generate_series(1,n) v;
    insert into private.battle_answers values(battle_id,round_number,
      jsonb_build_object('round',round_number,'kind','binary','title','Binary search · find '||goal,'rule','Tap the midpoint of the remaining interval, rounding down. Repeat until you find the target.','nodes','[]'::jsonb,'edges','[]'::jsonb,'values',values_json,'difficulty',private.battle_difficulty(round_number)),
      solution,'Each comparison discards half of the sorted interval. The lower midpoint gives a deterministic search.');
    return;
  end if;
  -- Ladder graph: adjacent rail nodes plus rungs. All weights positive.
  n:=least(3+(round_number+1)/2,7)*2; goal:=n-1;
  for i in 0..n-1 loop
    nodes:=nodes||jsonb_build_object('id',i,'x',0.08+0.84*(i/2)::float/((n/2)-1),'y',case when i%2=0 then 0.25 else 0.75 end);
    for j in i+1..n-1 loop
      if (j=i+1 and i%2=0) or j=i+2 then
        weight:=case when kind in (0,1) then 1 else 1+floor(random()*(3+round_number))::int end;
        edges:=edges||jsonb_build_object('a',i,'b',j,'weight',weight);
      end if;
    end loop;
  end loop;
  if kind=1 then
    -- DFS visits smallest unvisited neighbor first. Validate visitation prefix to goal.
    path:=array[0]; visited:=array_fill(false,array[n]);
    while cardinality(path)>0 loop
      current_node:=path[cardinality(path)]; path:=path[1:cardinality(path)-1];
      if visited[current_node+1] then continue; end if;
      visited[current_node+1]:=true; solution:=solution||to_jsonb(current_node);
      exit when current_node=goal;
      for item in select e from jsonb_array_elements(edges) e
        where (e->>'a')::int=current_node or (e->>'b')::int=current_node
        order by case when (e->>'a')::int=current_node then (e->>'b')::int else (e->>'a')::int end desc
      loop
        j:=case when (item->>'a')::int=current_node then (item->>'b')::int else (item->>'a')::int end;
        if not visited[j+1] then path:=array_append(path,j); end if;
      end loop;
    end loop;
    title:='Depth-first search'; rule:='Tap nodes in DFS visit order from 0 to '||goal||'. Explore the lowest numbered unvisited neighbor first. Backtrack when needed.';
    explanation:='DFS follows one branch as far as possible before backtracking. It does not guarantee a shortest path.';
  else
    dist:=array_fill(1000000,array[n]); prev:=array_fill(-1,array[n]); visited:=array_fill(false,array[n]); dist[1]:=0;
    for i in 1..n loop
      best:=1000001; current_node:=-1;
      for j in 0..n-1 loop
        if not visited[j+1] and dist[j+1]<best then current_node:=j; best:=dist[j+1]; end if;
      end loop;
      exit when current_node=-1 or current_node=goal;
      visited[current_node+1]:=true;
      for item in select e from jsonb_array_elements(edges) e loop
        a:=(item->>'a')::int; b:=(item->>'b')::int; weight:=(item->>'weight')::int;
        if a=current_node or b=current_node then
          j:=case when a=current_node then b else a end; candidate:=best+weight;
          if candidate<dist[j+1] then dist[j+1]:=candidate; prev[j+1]:=current_node; end if;
        end if;
      end loop;
    end loop;
    path:=array[goal]; current_node:=goal;
    while prev[current_node+1]>=0 loop current_node:=prev[current_node+1]; path:=array_prepend(current_node,path); end loop;
    solution:=to_jsonb(path);
    title:=case when kind=0 then 'Breadth-first search' when kind in (3,6) then 'A* search' else 'Dijkstra''s algorithm' end;
    rule:='Tap a path from 0 to '||goal||case when kind=0 then ' with the fewest edges.' else ' with the lowest total edge weight.' end;
    explanation:=case when kind=0 then 'BFS explores in layers and minimises edge count on this unweighted graph.' when kind in (3,6) then 'A* orders the frontier by g + h. An admissible heuristic never overestimates the remaining cost. Your path is checked against the exact least cost.' else 'Dijkstra settles the smallest known distance first. Positive edge weights ensure the settled distance is final.' end;
  end if;
  insert into private.battle_answers values(battle_id,round_number,
    jsonb_build_object('round',round_number,'kind',case when kind=1 then 'dfs' else 'path' end,'title',title,'rule',rule,'nodes',nodes,'edges',edges,'values','[]'::jsonb,'difficulty',private.battle_difficulty(round_number)),solution,explanation);
end;
$$;

create function private.battle_snapshot(battle_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare room private.battles; me private.battle_seats; prompt jsonb; sharing jsonb;
begin
  if not private.battle_member(battle_id) then raise exception 'Room unavailable'; end if;
  select * into room from private.battles where id=battle_id;
  select * into me from private.battle_seats where battle=battle_id and player=auth.uid();
  select a.prompt into prompt from private.battle_answers a where battle=battle_id and round=me.round and room.phase='playing';
  select jsonb_build_object('requester',requester,'accepted',accepted,'expiresAt',expires_at,
    'positions',case when accepted and expires_at>now() then positions else '{}'::jsonb end)
    into sharing from private.battle_sharing where battle=battle_id and expires_at>now();
  return jsonb_build_object('revision',(select revision from public.battle_invalidations where id=battle_id),'id',room.id,'code',room.code,'host',room.host,'phase',room.phase,'winner',room.winner,
    'startedAt',room.started_at,'finishedAt',room.finished_at,'viewer',auth.uid(),'rematch',room.rematch,'challenge',prompt,'sharing',sharing,
    'players',(select jsonb_agg(jsonb_build_object('id',s.player,'nickname',p.nickname,'avatar',p.avatar,'ready',s.ready,'score',s.score,'round',s.round,'correct',s.correct,'attempts',s.attempts,'online',s.last_seen>now()-interval '20 seconds') order by s.seat)
      from private.battle_seats s join private.battle_profiles p on p.id=s.player where s.battle=battle_id));
end;
$$;

create function private.friend_battle(action text, payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare principal uuid:=auth.uid(); room private.battles; me private.battle_seats; other private.battle_seats;
  battle_id uuid; next_id uuid; answer private.battle_answers; valid boolean; earned int; elapsed float; feedback jsonb;
  cost int:=0; optimal_cost int:=0; ids int[]; optimal_ids int[]; w int; i int; sharing private.battle_sharing;
  nickname text; avatar text; principal_email text;
begin
  if principal is null then raise exception 'Sign in to continue'; end if;
  -- Battles require a recoverable account. Campus anonymous auth remains supported.
  select email into principal_email from auth.users where id=principal and not is_anonymous;
  if principal_email is null or principal_email='' then raise exception 'Sign in with email to use friend battles'; end if;
  perform pg_advisory_xact_lock(hashtextextended(principal::text,712));
  if action='profile' then
    nickname:=btrim(payload->>'nickname'); avatar:=coalesce(payload->>'avatar','person.crop.circle.fill');
    insert into private.battle_profiles(id,nickname,avatar) values(principal,nickname,avatar)
      on conflict(id) do update set nickname=excluded.nickname, avatar=excluded.avatar;
    return jsonb_build_object('saved',true);
  end if;
  if action='stats' then
    return jsonb_build_object('profile',(select jsonb_build_object('nickname',p.nickname,'avatar',p.avatar) from private.battle_profiles p where p.id=principal),'matches', (select count(*) from private.battle_results where player=principal),
      'wins',(select count(*) from private.battle_results where player=principal and won),
      'currentStreak',(select count(*) from private.battle_results where player=principal and won and completed_at>coalesce((select max(completed_at) from private.battle_results where player=principal and not won),'-infinity')),
      'bestStreak',(select coalesce(max(streak),0) from (select count(*) filter(where won) streak from (select won,sum(case when won then 0 else 1 end) over(order by completed_at,battle) grp from private.battle_results where player=principal) a group by grp) b),
      'history',coalesce((select jsonb_agg(h order by h."completedAt" desc) from (select r.battle as id,p.nickname as opponent,r.won,r.score,r.difficulty,r.completed_at as "completedAt" from private.battle_results r join private.battle_profiles p on p.id=r.opponent where r.player=principal order by r.completed_at desc limit 20) h),'[]'::jsonb));
  end if;
  if action='recover' then
    select b.id into battle_id from private.battles b join private.battle_seats s on s.battle=b.id where s.player=principal and b.phase in ('lobby','playing') order by b.created_at desc limit 1;
    if battle_id is null then return 'null'::jsonb; end if;
    return private.battle_snapshot(battle_id);
  end if;
  if not exists(select 1 from private.battle_profiles where id=principal) then raise exception 'Save your player name first'; end if;
  if action='create' then
    if exists(select 1 from private.battle_seats s join private.battles b on b.id=s.battle where s.player=principal and b.phase in ('lobby','playing')) then raise exception 'Resume or leave your existing room first'; end if;
    insert into private.battles(host) values(principal) returning id into battle_id;
    insert into private.battle_seats(battle,player,seat) values(battle_id,principal,1);
    insert into public.battle_invalidations(id) values(battle_id);
    return private.battle_snapshot(battle_id);
  end if;
  if action='join' then
    select * into room from private.battles where code=upper(btrim(payload->>'code')) for update;
    if not found then raise exception 'Room not found'; end if;
    battle_id:=room.id;
    if private.battle_member(battle_id) then return private.battle_snapshot(battle_id); end if;
    if room.phase<>'lobby' or (select count(*) from private.battle_seats where battle=battle_id)>=2 then raise exception 'Room is full or already started'; end if;
    if exists(select 1 from private.battle_seats s join private.battles b on b.id=s.battle where s.player=principal and b.phase in ('lobby','playing')) then raise exception 'Resume or leave your existing room first'; end if;
    insert into private.battle_seats(battle,player,seat) values(battle_id,principal,2);
  else
    battle_id:=(payload->>'id')::uuid;
    select * into room from private.battles where id=battle_id for update;
    if not found or not private.battle_member(battle_id) then raise exception 'Room unavailable'; end if;
    select * into me from private.battle_seats where battle=battle_id and player=principal;
    select * into other from private.battle_seats where battle=battle_id and player<>principal;
    update private.battle_seats set last_seen=now() where battle=battle_id and player=principal;
    delete from private.battle_sharing where battle=battle_id and expires_at<=now();
    -- A five minute disconnected grace period pauses scoring; no unearned forfeit wins.
    if room.phase='playing' and other.last_seen<now()-interval '5 minutes' then
      update private.battles set phase='abandoned',finished_at=now() where id=battle_id;
      delete from private.battle_sharing where battle=battle_id;
      room.phase:='abandoned';
    end if;
    case action
    when 'snapshot' then null;
    when 'ready' then
      if room.phase<>'lobby' then raise exception 'Match has started'; end if;
      update private.battle_seats set ready=(payload->>'ready')::boolean where battle=battle_id and player=principal;
      if (select count(*) from private.battle_seats where battle=battle_id and ready)=2 then
        update private.battles set phase='playing',started_at=now() where id=battle_id;
        update private.battle_seats set round_started=now() where battle=battle_id;
        perform private.battle_challenge(battle_id,1);
      end if;
    when 'submit' then
      if room.phase<>'playing' then raise exception 'Match is not active'; end if;
      if other.last_seen<now()-interval '20 seconds' then raise exception 'Opponent disconnected. Scoring resumes when they return.'; end if;
      if (payload->>'round')::int<>me.round then raise exception 'That round has already been submitted. Refresh the match.'; end if;
      if me.last_attempt>now()-interval '1 second' then raise exception 'Take a moment before trying again'; end if;
      if jsonb_typeof(payload->'answer')<>'array' or jsonb_array_length(payload->'answer')>100 then raise exception 'Invalid answer'; end if;
      select * into answer from private.battle_answers where battle=battle_id and round=me.round;
      valid:=payload->'answer'=answer.answer;
      -- Accept every connected equal-optimum route, not just the solver's tie-break.
      if answer.prompt->>'kind'='path' then
        select array_agg(v::int order by ord) into ids from jsonb_array_elements_text(payload->'answer') with ordinality as t(v,ord);
        select array_agg(v::int order by ord) into optimal_ids from jsonb_array_elements_text(answer.answer) with ordinality as t(v,ord);
        valid:=cardinality(ids)>=2 and ids[1]=0 and ids[cardinality(ids)]=optimal_ids[cardinality(optimal_ids)] and cardinality(ids)=(select count(distinct v) from unnest(ids) v);
        if valid then
          for i in 1..cardinality(ids)-1 loop
            select (e->>'weight')::int into w from jsonb_array_elements(answer.prompt->'edges') e where ((e->>'a')::int=ids[i] and (e->>'b')::int=ids[i+1]) or ((e->>'b')::int=ids[i] and (e->>'a')::int=ids[i+1]);
            if w is null then valid:=false; exit; end if; cost:=cost+w;
          end loop;
          for i in 1..cardinality(optimal_ids)-1 loop
            select (e->>'weight')::int into w from jsonb_array_elements(answer.prompt->'edges') e where ((e->>'a')::int=optimal_ids[i] and (e->>'b')::int=optimal_ids[i+1]) or ((e->>'b')::int=optimal_ids[i] and (e->>'a')::int=optimal_ids[i+1]);
            optimal_cost:=optimal_cost+w;
          end loop;
          valid:=valid and cost=optimal_cost;
        end if;
      end if;
      valid:=coalesce(valid,false);
      elapsed:=extract(epoch from now()-me.round_started);
      earned:=case when valid then least(24,10+me.round*2)+case when elapsed<20 and me.round_attempts=0 then 3 else 0 end else 0 end;
      update private.battle_seats set attempts=attempts+1,last_attempt=now(),correct=correct+case when valid then 1 else 0 end,
        round_attempts=case when valid then 0 else round_attempts+1 end,
        score=least(100,score+earned),round=round+case when valid then 1 else 0 end,
        round_started=case when valid then now() else round_started end where battle=battle_id and player=principal returning * into me;
      feedback:=jsonb_build_object('correct',valid,'earned',earned,'explanation',case when valid then answer.explanation else 'Check your steps and try again. Incorrect attempts earn no progress.' end,'solution',case when valid then answer.answer else '[]'::jsonb end);
      if me.score=100 then
        update private.battles set phase='finished',winner=principal,finished_at=now() where id=battle_id;
        insert into private.battle_results(battle,player,opponent,won,score,difficulty)
          select battle_id,s.player,o.player,s.player=principal,s.score,private.battle_difficulty(s.round-1)
          from private.battle_seats s join private.battle_seats o on o.battle=s.battle and o.player<>s.player where s.battle=battle_id on conflict do nothing;
        delete from private.battle_sharing where battle=battle_id;
      elsif valid then perform private.battle_challenge(battle_id,me.round); end if;
    when 'leave' then
      if room.phase in ('lobby','playing') then update private.battles set phase='abandoned',finished_at=now() where id=battle_id; end if;
      delete from private.battle_sharing where battle=battle_id;
    when 'rematch' then
      if room.phase not in ('finished','abandoned') then raise exception 'Finish this match first'; end if;
      if room.rematch is null then
        insert into private.battles(host) values(room.host) returning id into next_id;
        insert into private.battle_seats(battle,player,seat) select next_id,player,seat from private.battle_seats where battle=battle_id;
        insert into public.battle_invalidations(id) values(next_id);
        update private.battles set rematch=next_id where id=battle_id;
      else next_id:=room.rematch; end if;
    when 'requestLocation' then
      if not (select cleanup_ready from private.battle_configuration where id) then raise exception 'Location sharing needs the scheduled expiry cleanup. See docs/EXPANSION.md.'; end if;
      if other.player is null then raise exception 'Connect a friend first'; end if;
      if room.phase not in ('lobby','playing') then raise exception 'Start a new room to share locations'; end if;
      if exists(select 1 from private.battle_sharing where battle=battle_id) then raise exception 'A sharing session already exists'; end if;
      insert into private.battle_sharing(battle,requester) values(battle_id,principal);
    when 'acceptLocation' then
      update private.battle_sharing set accepted=true,expires_at=now()+interval '10 minutes' where battle=battle_id and requester<>principal and expires_at>now();
      if not found then raise exception 'Location request expired'; end if;
    when 'stopLocation' then delete from private.battle_sharing where battle=battle_id;
    when 'position' then
      select * into sharing from private.battle_sharing where battle=battle_id;
      if not found or not sharing.accepted or sharing.expires_at<=now() then raise exception 'Both players must consent first'; end if;
      if not ((payload->>'latitude')::float between -90 and 90 and (payload->>'longitude')::float between -180 and 180) then raise exception 'Invalid coordinates'; end if;
      update private.battle_sharing set positions=jsonb_set(positions,array[principal::text],jsonb_build_object('latitude',(payload->>'latitude')::float,'longitude',(payload->>'longitude')::float)) where battle=battle_id;
    else raise exception 'Unknown action';
    end case;
  end if;
  update public.battle_invalidations set revision=revision+1 where id=battle_id and action<>'snapshot';
  return private.battle_snapshot(battle_id)||jsonb_build_object('feedback',feedback);
end;
$$;

-- Exposed wrapper uses invoker privileges, matching the existing arena boundary.
create function public.friend_battle(action text, payload jsonb default '{}') returns jsonb
language sql set search_path='' as $$ select private.friend_battle($1,$2); $$;
revoke all on function private.friend_battle(text,jsonb) from public,anon;
grant execute on function private.friend_battle(text,jsonb) to authenticated;

-- All writes go through the checked RPC, including scores and exactly-once results.
alter table private.battle_configuration enable row level security;
revoke all on private.battle_configuration from public,anon,authenticated;
alter table private.battle_profiles enable row level security;
alter table private.battles enable row level security;
alter table private.battle_seats enable row level security;
alter table private.battle_answers enable row level security;
alter table private.battle_results enable row level security;
alter table private.battle_sharing enable row level security;
revoke all on private.battle_profiles,private.battles,private.battle_seats,private.battle_answers,private.battle_results,private.battle_sharing from public,anon,authenticated;
revoke all on public.battle_invalidations from public,anon,authenticated;
grant select on public.battle_invalidations to authenticated;
revoke all on function public.friend_battle(text,jsonb) from public,anon;
grant execute on function public.friend_battle(text,jsonb) to authenticated;
revoke all on function private.battle_challenge(uuid,int),private.battle_snapshot(uuid),private.battle_difficulty(int) from public,anon,authenticated;
revoke all on function private.battle_member(uuid) from public,anon;
grant execute on function private.battle_member(uuid) to authenticated;
