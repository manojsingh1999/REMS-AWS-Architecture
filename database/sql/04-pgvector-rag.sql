-- Metadata RCA / Savvy RAG store on the dedicated rems-rag Aurora cluster (database rems_savvy).
-- Illustrative schema for documents + chunk embeddings; Savvy migrations own the real DDL and must keep
-- tenant_id + RLS on every table.

-- Roles and the rems_savvy database are created by bootstrap-roles.sh (rag cluster) before this file runs.
ALTER ROLE rems_savvy SET statement_timeout = '60s';

CREATE EXTENSION IF NOT EXISTS vector;     -- pgvector (Aurora PostgreSQL 16.x ships >= 0.7)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE SCHEMA IF NOT EXISTS savvy AUTHORIZATION rems_savvy_owner;
GRANT USAGE ON SCHEMA savvy TO rems_savvy;

CREATE OR REPLACE FUNCTION savvy.current_tenant() RETURNS uuid
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$;

CREATE TABLE IF NOT EXISTS savvy.documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL,
  kind          text NOT NULL,              -- sop | runbook | postmortem | rca
  s3_key        text NOT NULL,              -- tenants/<tenant_id>/documents/<id>
  sha256        text NOT NULL,
  title         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, sha256)
);

-- 1024 dims = Amazon Titan Text Embeddings v2 default (configurable: 256/512/1024).
CREATE TABLE IF NOT EXISTS savvy.chunks (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id     uuid NOT NULL,
  document_id   uuid NOT NULL REFERENCES savvy.documents (id) ON DELETE CASCADE,
  chunk_no      int  NOT NULL,
  content       text NOT NULL,
  embedding     vector(1024) NOT NULL,
  model         text NOT NULL,              -- embedding model id/version for re-embedding
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- HNSW gives better recall/latency than IVFFlat without periodic retraining.
CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw
  ON savvy.chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX IF NOT EXISTS chunks_tenant_idx ON savvy.chunks (tenant_id, document_id);

ALTER TABLE savvy.documents OWNER TO rems_savvy_owner;
ALTER TABLE savvy.chunks OWNER TO rems_savvy_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON savvy.documents, savvy.chunks TO rems_savvy;

ALTER TABLE savvy.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE savvy.documents FORCE ROW LEVEL SECURITY;
ALTER TABLE savvy.chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE savvy.chunks FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON savvy.documents;
DROP POLICY IF EXISTS tenant_isolation ON savvy.chunks;
CREATE POLICY tenant_isolation ON savvy.documents
  USING (tenant_id = savvy.current_tenant()) WITH CHECK (tenant_id = savvy.current_tenant());
CREATE POLICY tenant_isolation ON savvy.chunks
  USING (tenant_id = savvy.current_tenant()) WITH CHECK (tenant_id = savvy.current_tenant());

-- Retrieval pattern (RLS already restricts to the caller's tenant; the explicit predicate keeps the
-- planner on the tenant index for large tenants and documents intent):
--   SET LOCAL hnsw.ef_search = 40;
--   SELECT id, document_id, content, 1 - (embedding <=> $1) AS score
--   FROM savvy.chunks
--   WHERE tenant_id = savvy.current_tenant()
--   ORDER BY embedding <=> $1
--   LIMIT 8;
