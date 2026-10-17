-- Run after migrations, as database owner. Required before precise sharing is enabled.
-- pg_cron removes expired positions even when neither device is online.
create extension if not exists pg_cron;
select cron.schedule('friend-location-expiry','* * * * *',
  $$delete from private.battle_sharing where expires_at<=now()$$);
update private.battle_configuration set cleanup_ready=true where id;
-- Expired positions are hidden by the RPC immediately; physical cleanup is within one minute.
-- Stop Sharing/Decline/match completion delete immediately. Never log request bodies.
