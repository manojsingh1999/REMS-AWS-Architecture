-- Applied by bootstrap-roles.sh after the databases exist (core cluster).
REVOKE ALL ON DATABASE rems_api FROM PUBLIC;
REVOKE ALL ON DATABASE rems_authz FROM PUBLIC;
REVOKE ALL ON DATABASE rems_governance FROM PUBLIC;
GRANT CONNECT ON DATABASE rems_api TO rems_api, rems_migrator, rems_readonly;
GRANT CONNECT ON DATABASE rems_authz TO rems_authz, rems_migrator, rems_readonly;
GRANT CONNECT ON DATABASE rems_governance TO rems_governance, rems_migrator, rems_readonly;
REVOKE ALL ON DATABASE rems_llmgw FROM PUBLIC;
GRANT CONNECT ON DATABASE rems_llmgw TO rems_llmgw;
