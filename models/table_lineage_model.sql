-- =====================================================================
-- Model: table_lineage  (fact = system.access.table_lineage)
-- =====================================================================
-- One row per table read/write lineage event. record_id is the PK
-- (auto-generated, ~99.94% unique; a tiny duplicate fraction exists).
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id
--   * query.history (as dimension) : DOCUMENTED FK on statement_id,
--     key workspace_id + statement_id. 93% of rows-with-statement_id
--     match (rest = queries outside query.history retention). 0 M:N.
--
-- NOTE: record_id per the docs "cannot be joined with any tables"; it is
-- only the fact PK. source/target table names are natural attributes,
-- not FKs to a system dimension (no system table of UC tables exists).
-- =====================================================================

WITH query_dim AS (
  SELECT workspace_id, statement_id, statement_type, execution_status,
         executed_by, start_time AS query_start_time
  FROM system.query.history
)

SELECT
  -- ---- fact grain & attributes ----
  f.account_id,
  f.metastore_id,
  f.workspace_id,
  f.record_id,
  f.event_id,
  f.event_time,
  f.entity_type,
  f.entity_id,
  f.entity_run_id,
  f.source_table_full_name,
  f.source_type,
  f.target_table_full_name,
  f.target_type,
  f.created_by,
  f.statement_id,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- originating query (documented FK; query.history as dimension) ----
  q.statement_type,
  q.execution_status  AS query_execution_status,
  q.executed_by       AS query_executed_by,
  q.query_start_time

FROM system.access.table_lineage f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN query_dim q
  ON q.workspace_id = f.workspace_id
 AND q.statement_id = f.statement_id
;
