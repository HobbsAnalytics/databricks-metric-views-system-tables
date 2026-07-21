-- =====================================================================
-- Model: node_timeline  (fact = system.compute.node_timeline)
-- =====================================================================
-- One row per node-minute utilization record. GRAIN =
-- (workspace_id, cluster_id, instance_id, start_time) -- validated unique.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id
--   * clusters (SCD)    : point-in-time on start_time,
--                         key workspace_id + cluster_id (99.7%, 0 M:N)
--   * node_types (lookup): account_id + node_type (100%, 0 M:N)
-- =====================================================================

WITH clusters_scd AS (
  SELECT workspace_id, cluster_id, cluster_name, owned_by, dbr_version,
         data_security_mode, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, cluster_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.clusters
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.cluster_id,
  f.instance_id,
  f.start_time,
  f.end_time,
  f.driver,
  f.node_type,
  f.cpu_user_percent,
  f.cpu_system_percent,
  f.cpu_wait_percent,
  f.mem_used_percent,
  f.mem_swap_percent,
  f.network_sent_bytes,
  f.network_received_bytes,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- cluster (point-in-time) ----
  cl.cluster_name,
  cl.owned_by AS cluster_owner,
  cl.dbr_version,
  cl.data_security_mode,

  -- ---- node type (static lookup) ----
  nt.core_count,
  nt.memory_mb,
  nt.gpu_count

FROM system.compute.node_timeline f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN clusters_scd cl
  ON cl.workspace_id = f.workspace_id
 AND cl.cluster_id   = f.cluster_id
 AND f.start_time >= cl.change_time
 AND (f.start_time <  cl.next_change_time OR cl.next_change_time IS NULL)

LEFT JOIN system.compute.node_types nt
  ON nt.account_id = f.account_id
 AND nt.node_type  = f.node_type
;
