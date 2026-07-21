-- =====================================================================
-- Model: column_lineage  (fact = system.access.column_lineage)
-- =====================================================================
-- One row per column read/write lineage event. record_id is the PK.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id
--   * query.history (as dimension) : DOCUMENTED FK on statement_id,
--     key workspace_id + statement_id. 0 inflation, 0 M:N.
--     ~half of rows carry a statement_id (query-driven lineage).
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
  f.source_table_full_name,
  f.source_column_name,
  f.target_table_full_name,
  f.target_column_name,
  f.created_by,
  f.statement_id,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- originating query (documented FK; query.history as dimension) ----
  q.statement_type,
  q.execution_status  AS query_execution_status,
  q.executed_by       AS query_executed_by,
  q.query_start_time

FROM system.access.column_lineage f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN query_dim q
  ON q.workspace_id = f.workspace_id
 AND q.statement_id = f.statement_id
;
