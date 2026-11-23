-- Run inside EACH service database (rems_api, rems_authz, rems_governance, rems_savvy) as the master user.
-- The bootstrap script substitutes the service-specific role names via psql variables before execution
-- (see scripts/bootstrap-roles.sh); this file shows the rems_api instance.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS rems AUTHORIZATION rems_api_owner;

-- Application role: DML only, no DDL.
GRANT USAGE ON SCHEMA rems TO rems_api, rems_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE rems_api_owner IN SCHEMA rems
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rems_api;
ALTER DEFAULT PRIVILEGES FOR ROLE rems_api_owner IN SCHEMA rems
  GRANT USAGE, SELECT ON SEQUENCES TO rems_api;
ALTER DEFAULT PRIVILEGES FOR ROLE rems_api_owner IN SCHEMA rems
  GRANT SELECT ON TABLES TO rems_readonly;

ALTER ROLE rems_api SET search_path = rems, public;
