create or replace function private.arena_duel_snapshot(match_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare principal uuid := auth.uid(); room private.duel_rooms; players jsonb; doc jsonb; reveal jsonb; answers jsonb;
begin
  if principal is null then perform private.arena_fail('unauthenticated','Restore your player session.'); end if;
  select * into room from private.duel_rooms r where r.id=match_id and exists (
    select 1 from private.duel_players p where p.room_id=r.id and p.user_id=principal) for share;
  if not found then perform private.arena_fail('notMember','This session is not a member of that duel.'); end if;
  select jsonb_agg(jsonb_build_object('id',p.user_id,'nickname',p.nickname,'ready',p.ready,
    'score',p.score,'hasContinued',p.continued,'submitted',exists(select 1 from private.duel_answers a
      where a.room_id=room.id and a.user_id=p.user_id and a.generation=room.generation and a.round_index=room.round_index))
    order by p.seat) into players from private.duel_players p where p.room_id=room.id;
  if room.phase in ('answering','reveal','finished') then
    doc := private.duel_document(room);
  end if;
  if room.phase in ('reveal','finished') then
    select jsonb_agg(jsonb_build_object('playerID',a.user_id,'answerNodeID',a.node_id,'correct',a.correct,'points',a.points)
      order by p.seat) into answers from private.duel_answers a join private.duel_players p on p.room_id=a.room_id and p.user_id=a.user_id
      where a.room_id=room.id and a.generation=room.generation and a.round_index=room.round_index;
    reveal := jsonb_build_object('correctNodeID',doc->'correctNodeID','explanation',doc->'explanation','trace',doc->'trace','answers',answers);
  end if;
  return jsonb_strip_nulls(jsonb_build_object('id',room.id,'roomCode',room.code,'creatorID',room.creator_id,
    'viewerID',principal,'revision',room.revision,'phase',room.phase,'roundIndex',room.round_index,'roundCount',3,
    'algorithm',room.algorithm,'players',players,'currentRound',doc->'round','reveal',reveal));
end;
$$;

create or replace function private.arena_duel_command(command jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare principal uuid := auth.uid(); v_command_id uuid; action text; room private.duel_rooms;
  existing private.duel_receipts; name text; room_code text; picked text; doc jsonb;
  result jsonb; player_count integer; expected integer; match uuid; round_points integer;
begin
  if principal is null then perform private.arena_fail('unauthenticated','Restore your player session.'); end if;
  if jsonb_typeof(command) is distinct from 'object' or command - array['id','action','matchID','revision','nickname','code','algorithm','answerNodeID'] <> '{}'::jsonb then
    perform private.arena_fail('invalidCommand','Unsupported duel command.');
  end if;
  begin v_command_id := (command->>'id')::uuid; match := (command->>'matchID')::uuid; expected := (command->>'revision')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    perform private.arena_fail('invalidCommand','Invalid command identity or revision.'); end;
  action := command->>'action';
  if v_command_id is null or action is null or action not in ('create','join','ready','start','submit','advance','leave','rematch') then
    perform private.arena_fail('invalidCommand','Choose a supported duel action.'); end if;
  -- Serialise commands for one identity, including entry commands, then room mutations.
  perform pg_advisory_xact_lock(hashtextextended('duel:' || principal::text,0));
  select * into existing from private.duel_receipts where user_id=principal and duel_receipts.command_id=v_command_id;
  if found then
    if existing.command <> command then perform private.arena_fail('commandConflict','This command ID has already been used.'); end if;
    return existing.snapshot;
  end if;
  if action in ('create','join') then
    name := btrim(command->>'nickname');
    if name is null or char_length(name) not between 1 and 24 or name ~ '[[:cntrl:]]' then
      perform private.arena_fail('invalidNickname','Use a nickname of 1–24 characters.'); end if;
    if action='create' then
      if command->>'algorithm' is null or command->>'algorithm' not in ('bfs','dfs','dijkstra','aStar','greedy') then
        perform private.arena_fail('invalidAlgorithm','Choose BFS, DFS, Dijkstra, A* or Greedy best-first.'); end if;
      if (select count(*) from private.duel_rooms where creator_id=principal and created_at>now()-interval '1 hour')>=30 then
        perform private.arena_fail('rateLimited','Too many rooms. Join an existing room.'); end if;
      loop
        room_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
        begin
          insert into private.duel_rooms(code,creator_id,algorithm) values(room_code,principal,command->>'algorithm') returning * into room;
          exit;
        exception when unique_violation then null; end;
      end loop;
      insert into private.duel_players(room_id,user_id,seat,nickname) values(room.id,principal,1,name);
    else
      select * into room from private.duel_rooms where code=upper(btrim(command->>'code')) for update;
      if not found then perform private.arena_fail('roomNotFound','No duel has that room code.'); end if;
      if room.phase <> 'lobby' then perform private.arena_fail('invalidPhase','That duel has already started.'); end if;
      if not exists(select 1 from private.duel_players where room_id=room.id and user_id=principal) then
        select count(*) into player_count from private.duel_players where room_id=room.id;
        if player_count>=2 then perform private.arena_fail('roomFull','This duel already has two players.'); end if;
        insert into private.duel_players(room_id,user_id,seat,nickname) values(room.id,principal,2,name);
        update private.duel_rooms set revision=revision+1 where id=room.id returning * into room;
      end if;
    end if;
  else
    select * into room from private.duel_rooms r where r.id=match and exists(
      select 1 from private.duel_players p where p.room_id=r.id and p.user_id=principal) for update;
    if not found then perform private.arena_fail('notMember','This session is not a member of that duel.'); end if;
    if expected is distinct from room.revision then perform private.arena_fail('staleRevision','The duel changed. Refresh and try again.',room.revision); end if;
    if action='leave' then
      if room.phase not in ('finished','incomplete') then update private.duel_rooms set phase='incomplete' where id=room.id; end if;
    elsif action='rematch' then
      if room.creator_id<>principal then perform private.arena_fail('hostOnly','Only the host can start a rematch.'); end if;
      if room.phase<>'finished' then perform private.arena_fail('invalidPhase','Finish this duel before starting a rematch.'); end if;
      update private.duel_rooms set phase='lobby',round_index=0,generation=generation+1 where id=room.id;
      update private.duel_players set ready=false,score=0,continued=false where room_id=room.id;
    elsif action='ready' then
      if room.phase<>'lobby' then perform private.arena_fail('invalidPhase','Ready up in the lobby.'); end if;
      update private.duel_players set ready=true where room_id=room.id and user_id=principal;
    elsif action='start' then
      if room.creator_id<>principal then perform private.arena_fail('hostOnly','Only the host can start the duel.'); end if;
      if room.phase<>'lobby' then perform private.arena_fail('invalidPhase','This duel has already started.'); end if;
      if (select count(*) from private.duel_players where room_id=room.id and ready)<>2 then
        perform private.arena_fail('notReady','Both players must be ready.'); end if;
      perform private.duel_build_deck(room);
      update private.duel_rooms set phase='answering' where id=room.id;
    elsif action='submit' then
      if room.phase<>'answering' then perform private.arena_fail('invalidPhase','Wait for the next prediction.'); end if;
      if exists(select 1 from private.duel_answers where room_id=room.id and user_id=principal and generation=room.generation and round_index=room.round_index) then
        perform private.arena_fail('alreadySubmitted','Your prediction is already locked in.'); end if;
      doc := private.duel_document(room);
      picked := command->>'answerNodeID';
      if picked is null or not (doc->'round'->'choices' ? picked) then perform private.arena_fail('invalidAnswer','Choose one of the displayed nodes.'); end if;
      round_points := case when picked=doc->>'correctNodeID' then 100 else 0 end;
      insert into private.duel_answers values(room.id,principal,room.generation,room.round_index,picked,round_points=100,round_points);
      if (select count(*) from private.duel_answers where room_id=room.id and generation=room.generation and round_index=room.round_index)=2 then
        update private.duel_rooms set phase='reveal' where id=room.id;
        update private.duel_players p set score=p.score+a.points from private.duel_answers a
          where a.room_id=room.id and a.generation=room.generation and a.round_index=room.round_index and p.room_id=a.room_id and p.user_id=a.user_id;
      end if;
    elsif action='advance' then
      if room.phase<>'reveal' then perform private.arena_fail('invalidPhase','Wait for both predictions to be revealed.'); end if;
      update private.duel_players set continued=true where room_id=room.id and user_id=principal;
      if (select count(*) from private.duel_players where room_id=room.id and continued)=2 then
        if room.round_index=2 then update private.duel_rooms set phase='finished' where id=room.id;
        else
          update private.duel_rooms set phase='answering',round_index=round_index+1 where id=room.id;
          update private.duel_players set continued=false where room_id=room.id;
        end if;
      end if;
    end if;
    update private.duel_rooms set revision=revision+1 where id=room.id returning * into room;
  end if;
  if action in ('start','advance') and room.phase='answering' then perform private.duel_mark_seen(room); end if;
  result := private.arena_duel_snapshot(room.id);
  insert into private.duel_receipts(user_id,command_id,room_id,command,snapshot) values(principal,v_command_id,room.id,command,result);
  return result;
end;
$$;
