# pgvector

**Status:** ✅ `database/sql/04-pgvector-rag.sql` (parsed with the PostgreSQL 16 parser). ⚠️ Not executed against Aurora.

## Real schema highlights

```sql
-- savvy.chunks (excerpt)
embedding     vector(1024) NOT NULL,

CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw
  ON savvy.chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
CREATE INDEX IF NOT EXISTS chunks_tenant_idx ON savvy.chunks (tenant_id, document_id);
-- query-time:
--   SET LOCAL hnsw.ef_search = 40;
```

RLS with `FORCE` applies to `savvy.*` tables, the same as `rems.*` (see [tenant isolation](../07-security/tenant-isolation.md)).

## Sizing

| Parameter | Value | Effect |
|---|---|---|
| Dimensions | 1024 (Titan v2) | ~4 KB per vector + row overhead |
| `m` | 16 | Graph degree: recall vs memory |
| `ef_construction` | 64 | Build quality vs build time |
| `ef_search` | 40 (100 for recall-critical) | Query recall vs latency |
| Cluster | db.r7g.xlarge writer + 1 reader (prod), auto scaling to 3 | The HNSW index should fit in memory for < 20 ms queries |

Rough memory check: 10 M chunks × ~4.5 KB ≈ 45 GB of vectors plus index. Monitor `BufferCacheHitRatio`, and scale the instance class before it drops.

## Steps

```bash
AWS_REGION=ap-south-1 ./database/scripts/bootstrap-roles.sh prod rag
```

## Verification

```sql
SELECT pg_size_pretty(pg_relation_size('savvy.chunks_embedding_hnsw'));
SELECT count(*) FROM savvy.chunks;   -- returns only the current tenant's rows (RLS)
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Sequential scan instead of HNSW | Query must `ORDER BY embedding <=> $1 LIMIT k` with the same operator class (cosine) |
| Index build very slow / times out | Raise `maintenance_work_mem` for the session. The rag cluster `statement_timeout` is 120 s, so build `CONCURRENTLY` from an admin session with a higher timeout |
| Low recall | Raise `ef_search`. Check that the embedding model versions match |

## Rollback

`DROP INDEX CONCURRENTLY` / recreate. Vectors are derived data and can be re-embedded from S3.
