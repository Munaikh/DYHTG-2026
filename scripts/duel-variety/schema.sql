-- Additive expansion of the indoor duel only. Existing outdoor contracts are unchanged.
alter table private.duel_rooms drop constraint duel_rooms_algorithm_check;
alter table private.duel_rooms add constraint duel_rooms_algorithm_check
  check (algorithm in ('bfs','dfs','dijkstra','aStar','greedy'));
create table private.duel_content (
  id text primary key, algorithm text not null check (algorithm in ('bfs','dfs','dijkstra','aStar','greedy')),
  slot integer not null check(slot between 0 and 2), document jsonb not null
);
create index duel_content_selection on private.duel_content(algorithm,slot);
create table private.duel_decks (
  room_id uuid not null references private.duel_rooms(id) on delete cascade,
  generation integer not null, round_index integer not null check(round_index between 0 and 2),
  content_id text not null references private.duel_content(id),
  primary key(room_id,generation,round_index), unique(room_id,generation,content_id)
);
create index duel_decks_content on private.duel_decks(content_id);
create table private.duel_seen (
  user_id uuid not null references auth.users(id) on delete cascade,
  content_id text not null references private.duel_content(id), last_seen timestamptz not null default clock_timestamp(),
  primary key(user_id,content_id)
);
create index duel_seen_content on private.duel_seen(content_id);
alter table private.duel_content enable row level security;
alter table private.duel_decks enable row level security;
alter table private.duel_seen enable row level security;
revoke all on private.duel_content,private.duel_decks,private.duel_seen from public,anon,authenticated;

create function private.duel_document(room private.duel_rooms) returns jsonb
language sql stable set search_path='' as $$
  select coalesce(
    (select c.document from private.duel_decks d join private.duel_content c on c.id=d.content_id
      where d.room_id=room.id and d.generation=room.generation and d.round_index=room.round_index),
    -- Keep already-running v1 rooms on their original questions and locked answers.
    (select document from private.duel_rounds where algorithm=room.algorithm and round_index=room.round_index));
$$;
create function private.duel_build_deck(room private.duel_rooms) returns void
language plpgsql set search_path='' as $$
declare slot_number integer; selected text;
begin
  for slot_number in 0..2 loop
    -- Prefer unseen-by-both content, then the least recently seen by either player.
    -- The deck is fixed under the room lock before any public question is returned.
    select c.id into selected from private.duel_content c
      left join private.duel_seen h on h.content_id=c.id and h.user_id in
        (select user_id from private.duel_players where room_id=room.id)
      where c.algorithm=room.algorithm and c.slot=slot_number
      group by c.id
      order by count(h.user_id),max(h.last_seen) nulls first,random() limit 1;
    if selected is null then perform private.arena_fail('serviceUnavailable','The question bank is unavailable.'); end if;
    insert into private.duel_decks values(room.id,room.generation,slot_number,selected) on conflict do nothing;
  end loop;
end;
$$;
create function private.duel_mark_seen(room private.duel_rooms) returns void
language sql set search_path='' as $$
  insert into private.duel_seen(user_id,content_id)
    select p.user_id,d.content_id from private.duel_players p join private.duel_decks d on d.room_id=p.room_id
      where p.room_id=room.id and d.generation=room.generation and d.round_index=room.round_index
  on conflict(user_id,content_id) do update set last_seen=excluded.last_seen;
$$;
revoke all on function private.duel_document(private.duel_rooms),private.duel_build_deck(private.duel_rooms),
  private.duel_mark_seen(private.duel_rooms) from public,anon,authenticated;
