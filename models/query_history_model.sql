-- =====================================================================
-- Model: query_history  (fact = system.query.history)
-- =====================================================================
-- One row per statement execution. statement_id is globally unique.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id
--   * warehouses (SCD)  : point-in-time on start_time,
--                         key workspace_id + compute.warehouse_id
--                         (100% where warehouse_id present, 0 M:N)
--   * clusters (SCD)    : point-in-time on start_time,
--                         key workspace_id + compute.cluster_id
--                         (valid pattern; 0 rows use cluster_id in this
--                         workspace but included for portability)
--
-- A statement uses EITHER a warehouse or a cluster (compute.type), so the
-- two compute joins never both match the same row -> no fan-out.
-- =====================================================================

WITH warehouses_scd AS (
  SELECT workspace_id, warehouse_id, warehouse_name, warehouse_type, warehouse_size,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, warehouse_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.warehouses
),
clusters_scd AS (
  SELECT workspace_id, cluster_id, cluster_name, owned_by, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, cluster_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.clusters
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.statement_id,
  f.session_id,
  f.execution_status,
  f.statement_type,
  f.executed_by_user_id,
  f.executed_by,
  f.compute.type            AS compute_type,
  f.start_time,
  f.end_time,
  f.total_duration_ms,
  f.execution_duration_ms,
  f.compilation_duration_ms,
  f.read_bytes,
  f.read_rows,
  f.produced_rows,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- warehouse (point-in-time; when compute.type = WAREHOUSE) ----
  wh.warehouse_name,
  wh.warehouse_type,
  wh.warehouse_size,

  -- ---- cluster (point-in-time; when compute.type = CLUSTER) ----
  cl.cluster_name,
  cl.owned_by              AS cluster_owner

FROM system.query.history f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN warehouses_scd wh
  ON wh.workspace_id = f.workspace_id
 AND wh.warehouse_id = f.compute.warehouse_id
 AND f.start_time >= wh.change_time
 AND (f.start_time <  wh.next_change_time OR wh.next_change_time IS NULL)

LEFT JOIN clusters_scd cl
  ON cl.workspace_id = f.workspace_id
 AND cl.cluster_id   = f.compute.cluster_id
 AND f.start_time >= cl.change_time
 AND (f.start_time <  cl.next_change_time OR cl.next_change_time IS NULL)
;
