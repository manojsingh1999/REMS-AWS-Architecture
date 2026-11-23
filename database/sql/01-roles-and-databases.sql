-- REMS database bootstrap (run as the master user, once per cluster, by database/scripts/bootstrap-roles.sh).
-- Passwords are NOT in this file: the script sets them from Secrets Manager with ALTER ROLE afterwards.
-- Least privilege: each service owns nothing it does not need, and no application role is a superuser,
-- table owner of RLS-protected tables, or BYPASSRLS.

-- ------------------------------------------------------------------ roles (idempotent: safe to re-run)
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('rems_readonly',         'NOLOGIN'),
      ('rems_monitoring',       'NOLOGIN'),
      -- schema owners: migrations SET ROLE to these, applications never connect as owners
      ('rems_api_owner',        'NOLOGIN'),
      ('rems_authz_owner',      'NOLOGIN'),
      ('rems_governance_owner', 'NOLOGIN'),
      -- one login role per service (names match terraform service_users)
      ('rems_api',        'LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS CONNECTION LIMIT 400'),
      ('rems_authz',      'LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS CONNECTION LIMIT 200'),
      ('rems_governance', 'LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS CONNECTION LIMIT 100'),
      ('rems_migrator',   'LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS CONNECTION LIMIT 5'),
      -- LLM gateway (LiteLLM) owns its own small database for virtual keys, budgets and spend logs
      ('rems_llmgw',      'LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS CONNECTION LIMIT 50')
    ) AS t(name, attrs)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.name) THEN
      EXECUTE format('CREATE ROLE %I %s', r.name, r.attrs);
    END IF;
  END LOOP;
END
$$;

GRANT pg_monitor TO rems_monitoring;
GRANT rems_api_owner, rems_authz_owner, rems_governance_owner TO rems_migrator;
GRANT rems_monitoring TO rems_api;

-- Server-side guardrails per role (complement cluster parameter group defaults).
ALTER ROLE rems_api SET statement_timeout = '15s';
ALTER ROLE rems_api SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE rems_authz SET statement_timeout = '2s';      -- authz is on every request path
ALTER ROLE rems_governance SET statement_timeout = '5min'; -- scans are long but bounded
ALTER ROLE rems_migrator SET lock_timeout = '5s';         -- migrations never block traffic for long

-- ------------------------------------------------------------------ databases
-- CREATE DATABASE cannot run inside a transaction/DO block; bootstrap-roles.sh creates
-- rems_api, rems_authz, rems_governance and rems_llmgw idempotently, then applies these grants.
