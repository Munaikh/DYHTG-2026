-- Some hosted projects include this SECURITY DEFINER event-trigger helper with
-- PUBLIC execution. Event triggers need no API caller privileges. Older/local
-- stacks may not contain it, so keep this migration portable.
do $lockdown$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end;
$lockdown$;
