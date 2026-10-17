-- Read-only operator check. Run locally first, then on the dedicated project.
-- Expected: three migrations; one unsurveyed course; six slots per algorithm;
-- no private client grants; only the invalidation table in Realtime.
select
  (select jsonb_agg(version order by version) from supabase_migrations.schema_migrations) as migrations,
  (select jsonb_agg(jsonb_build_object('id',id,'version',version,'surveyed',surveyed,
    'arrivalPolicy',definition->'arrivalPolicy') order by id,version)
    from private.arena_courses) as courses,
  (select jsonb_agg(to_jsonb(c) order by algorithm) from (
    select algorithm,document->'definition'->>'contentVersion' as content_version,
      array_agg(slot order by slot) as slots
    from private.arena_challenges group by algorithm,document->'definition'->>'contentVersion'
  ) c) as content,
  (select jsonb_agg(schemaname||'.'||tablename order by tablename)
    from pg_publication_tables where pubname='supabase_realtime') as realtime_tables,
  (select count(*) from pg_tables t
    cross join unnest(array['anon','authenticated']) r(role)
    cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
    where t.schemaname='private' and t.tablename like 'arena_%'
      and has_table_privilege(r.role,format('%I.%I',t.schemaname,t.tablename),p.privilege)) as private_client_grants;
