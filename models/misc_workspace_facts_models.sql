-- =====================================================================
-- Models: miscellaneous workspace-scoped facts
--   system.sharing.materialization_history
--   system.storage.predictive_optimization_operations_history
--   system.lakeflow.zerobus_ingest            (Beta)
--   system.lakeflow.zerobus_stream            (Beta)
-- =====================================================================
-- Each shares a single validated one-layer edge:
--   * workspaces_latest : snapshot on workspace_id (N:1, 0 M:N)
-- Match rates (see relationships/relationships.csv):
--   materialization_history 80% (5 rows total), predictive_optimization 96.7%,
--   zerobus_ingest 99.97%, zerobus_stream 99.9%
--
-- 2nd-level opportunities (deferred to the cross-model phase):
--   predictive_optimization has usage_quantity/usage_unit -> billing.usage
--   zerobus_stream <-> zerobus_ingest via stream_id
-- =====================================================================

-- ---- sharing.materialization_history --------------------------------
SELECT
  f.sharing_materialization_id, f.account_id, f.workspace_id,
  f.recipient_name, f.provider_name, f.share_name,
  f.schema_name, f.table_name, f.created_at,
  ws.workspace_name
FROM system.sharing.materialization_history f
LEFT JOIN system.access.workspaces_latest ws ON ws.workspace_id = f.workspace_id
;

-- ---- storage.predictive_optimization_operations_history -------------
SELECT
  f.account_id, f.workspace_id, f.operation_id, f.operation_type, f.operation_status,
  f.start_time, f.end_time,
  f.metastore_name, f.catalog_name, f.schema_name, f.table_name, f.table_id,
  f.usage_unit, f.usage_quantity,
  ws.workspace_name
FROM system.storage.predictive_optimization_operations_history f
LEFT JOIN system.access.workspaces_latest ws ON ws.workspace_id = f.workspace_id
;

-- ---- lakeflow.zerobus_ingest (Beta) ---------------------------------
SELECT
  f.commit_version, f.stream_id, f.workspace_id, f.account_id,
  f.table_id, f.table_name, f.commit_time,
  f.committed_bytes, f.committed_records,
  ws.workspace_name
FROM system.lakeflow.zerobus_ingest f
LEFT JOIN system.access.workspaces_latest ws ON ws.workspace_id = f.workspace_id
;

-- ---- lakeflow.zerobus_stream (Beta) ---------------------------------
SELECT
  f.stream_id, f.event_time, f.workspace_id, f.account_id, f.producer_id,
  f.opened_time, f.closed_time, f.table_id, f.table_name,
  f.protocol, f.data_format,
  ws.workspace_name
FROM system.lakeflow.zerobus_stream f
LEFT JOIN system.access.workspaces_latest ws ON ws.workspace_id = f.workspace_id
;
