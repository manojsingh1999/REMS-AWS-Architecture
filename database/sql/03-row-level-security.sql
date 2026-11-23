-- Tenant isolation at the database layer (defence in depth behind the Authorization Service).
--
-- Contract with the application (documented in architecture/07-security.md):
--   Every transaction starts with   SELECT set_config('app.tenant_id', '<uuid from verified JWT>', true);
--   (transaction-local, so it can never leak to another client through RDS Proxy connection reuse)
-- If the setting is missing, current_tenant() returns NULL and every policy evaluates to false -> zero rows.
--
-- The tables below are an illustrative pattern for REMS entities (incidents, rca_reports); the real
-- schema is owned by the service migrations, which must apply the same three statements to every
-- tenant-scoped table: tenant_id NOT NULL, ENABLE + FORCE ROW LEVEL SECURITY, tenant policy.

CREATE OR REPLACE FUNCTION rems.current_tenant() RETURNS uuid
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$;

CREATE TABLE IF NOT EXISTS rems.incidents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL,
  title       text NOT NULL,
  severity    text NOT NULL,
  status      text NOT NULL DEFAULT 'open',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS incidents_tenant_created_idx ON rems.incidents (tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS rems.rca_reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL,
  incident_id  uuid NOT NULL REFERENCES rems.incidents (id) ON DELETE CASCADE,
  summary      text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rca_reports_tenant_idx ON rems.rca_reports (tenant_id, incident_id);

ALTER TABLE rems.incidents OWNER TO rems_api_owner;
ALTER TABLE rems.rca_reports OWNER TO rems_api_owner;

-- FORCE applies the policy to the table owner too (migrations cannot accidentally read across tenants).
ALTER TABLE rems.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE rems.incidents FORCE ROW LEVEL SECURITY;
ALTER TABLE rems.rca_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE rems.rca_reports FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON rems.incidents;
CREATE POLICY tenant_isolation ON rems.incidents
  USING (tenant_id = rems.current_tenant())
  WITH CHECK (tenant_id = rems.current_tenant());

DROP POLICY IF EXISTS tenant_isolation ON rems.rca_reports;
CREATE POLICY tenant_isolation ON rems.rca_reports
  USING (tenant_id = rems.current_tenant())
  WITH CHECK (tenant_id = rems.current_tenant());

-- Composite FK guard: an RCA can only reference an incident of the same tenant.
ALTER TABLE rems.incidents DROP CONSTRAINT IF EXISTS incidents_id_tenant_uq;
ALTER TABLE rems.incidents ADD CONSTRAINT incidents_id_tenant_uq UNIQUE (id, tenant_id);
ALTER TABLE rems.rca_reports DROP CONSTRAINT IF EXISTS rca_same_tenant_fk;
ALTER TABLE rems.rca_reports ADD CONSTRAINT rca_same_tenant_fk
  FOREIGN KEY (incident_id, tenant_id) REFERENCES rems.incidents (id, tenant_id);

-- ------------------------------------------------------------------ verification (run in CI against a test DB)
-- BEGIN;
--   SELECT set_config('app.tenant_id', '11111111-1111-1111-1111-111111111111', true);
--   SELECT count(*) FROM rems.incidents WHERE tenant_id = '22222222-2222-2222-2222-222222222222';  -- must be 0
-- ROLLBACK;
