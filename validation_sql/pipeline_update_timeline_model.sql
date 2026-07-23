-- =====================================================================
-- Model: pipeline_update_timeline  (fact = system.lakeflow.pipeline_update_timeline)
-- =====================================================================
-- One row per pipeline update time period. GRAIN =
-- (workspace_id, update_id, period_start_time) -- validated unique.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id (100%)
--   * pipelines (SCD)   : point-in-time on period_start_time,
--                         key workspace_id + pipeline_id (99.99%, 0 M:N)
-- =====================================================================

WITH pipelines_scd AS (
  SELECT workspace_id, pipeline_id, name AS pipeline_name, pipeline_type,
         created_by, run_as, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, pipeline_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.lakeflow.pipelines
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.pipeline_id,
  f.update_id,
  f.update_type,
  f.request_id,
  f.trigger_type,
  f.result_state,
  f.run_as_user_name,
  f.period_start_time,
  f.period_end_time,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- pipeline definition (point-in-time) ----
  p.pipeline_name,
  p.pipeline_type,
  p.created_by AS pipeline_created_by,
  p.run_as     AS pipeline_run_as

FROM system.lakeflow.pipeline_update_timeline f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN pipelines_scd p
  ON p.workspace_id = f.workspace_id
 AND p.pipeline_id  = f.pipeline_id
 AND f.period_start_time >= p.change_time
 AND (f.period_start_time <  p.next_change_time OR p.next_change_time IS NULL)
;
