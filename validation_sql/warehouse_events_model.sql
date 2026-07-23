-- =====================================================================
-- Model: warehouse_events  (fact = system.compute.warehouse_events)
-- =====================================================================
-- One row per SQL warehouse state event. GRAIN =
-- (workspace_id, warehouse_id, event_time, event_type) -- validated unique.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id
--   * warehouses (SCD)  : point-in-time on event_time,
--                         key workspace_id + warehouse_id (99.99%, 0 M:N)
-- =====================================================================

WITH warehouses_scd AS (
  SELECT workspace_id, warehouse_id, warehouse_name, warehouse_type, warehouse_size,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, warehouse_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.warehouses
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.warehouse_id,
  f.event_type,
  f.cluster_count,
  f.event_time,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- warehouse (point-in-time) ----
  wh.warehouse_name,
  wh.warehouse_type,
  wh.warehouse_size

FROM system.compute.warehouse_events f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN warehouses_scd wh
  ON wh.workspace_id = f.workspace_id
 AND wh.warehouse_id = f.warehouse_id
 AND f.event_time >= wh.change_time
 AND (f.event_time <  wh.next_change_time OR wh.next_change_time IS NULL)
;
