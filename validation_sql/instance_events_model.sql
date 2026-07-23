-- =====================================================================
-- Model: instance_events  (fact = system.compute.instance_events)
-- =====================================================================
-- One row per instance state transition / lifecycle event.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest  : snapshot on workspace_id
--   * instance_pools (SCD): point-in-time on event_time,
--                           key workspace_id + instance_pool_id
--                           (100% where instance_pool_id present, 0 M:N)
--   * clusters (SCD)     : point-in-time on event_time,
--                           key workspace_id + cluster_id
--                           (100% where cluster_id present, 0 M:N)
--   * node_types (lookup): account_id + node_type (100%, 0 M:N)
--
-- NOTE: instance_pool_id and cluster_id are each populated only for a
-- subset of events, so their match rates are 100% *of the rows that
-- carry the id* (LEFT JOINs leave the rest null, as expected).
-- =====================================================================

WITH pools_scd AS (
  SELECT workspace_id, instance_pool_id, instance_pool_name, node_type, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, instance_pool_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.instance_pools
),
clusters_scd AS (
  SELECT workspace_id, cluster_id, cluster_name, owned_by, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, cluster_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.clusters
)

SELECT
  -- ---- fact grain & attributes ----
  f.account_id,
  f.workspace_id,
  f.instance_id,
  f.event_time,
  f.event_type,
  f.state,
  f.availability_type,
  f.instance_pool_id,
  f.cluster_id,
  f.node_type,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- instance pool (point-in-time) ----
  ip.instance_pool_name,

  -- ---- cluster (point-in-time) ----
  cl.cluster_name,
  cl.owned_by AS cluster_owner,

  -- ---- node type (static lookup) ----
  nt.core_count,
  nt.memory_mb,
  nt.gpu_count

FROM system.compute.instance_events f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN pools_scd ip
  ON ip.workspace_id     = f.workspace_id
 AND ip.instance_pool_id = f.instance_pool_id
 AND f.event_time >= ip.change_time
 AND (f.event_time <  ip.next_change_time OR ip.next_change_time IS NULL)

LEFT JOIN clusters_scd cl
  ON cl.workspace_id = f.workspace_id
 AND cl.cluster_id   = f.cluster_id
 AND f.event_time >= cl.change_time
 AND (f.event_time <  cl.next_change_time OR cl.next_change_time IS NULL)

LEFT JOIN system.compute.node_types nt
  ON nt.account_id = f.account_id
 AND nt.node_type  = f.node_type
;
