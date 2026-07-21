-- =====================================================================
-- Model: run_metrics_history  (fact = system.mlflow.run_metrics_history)
-- =====================================================================
-- One row per logged MLflow metric datapoint (timeseries).
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest      : snapshot on workspace_id
--   * runs_latest (snapshot) : workspace_id + run_id (99.996%, 0 M:N)
--   * experiments_latest     : workspace_id + experiment_id (99.99%, 0 M:N)
--
-- SNOWFLAKE NOTE: runs_latest also carries experiment_id, so experiment
-- could be reached via runs_latest (2nd-level flake). Kept direct here
-- because the fact carries experiment_id itself (one-layer star).
-- =====================================================================

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.record_id,
  f.experiment_id,
  f.run_id,
  f.metric_name,
  f.metric_value,
  f.metric_step,
  f.metric_time,
  f.insert_time,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- run (snapshot) ----
  r.run_name,
  r.status       AS run_status,
  r.created_by   AS run_created_by,
  r.start_time   AS run_start_time,
  r.end_time     AS run_end_time,

  -- ---- experiment (snapshot) ----
  e.name         AS experiment_name

FROM system.mlflow.run_metrics_history f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN system.mlflow.runs_latest r
  ON r.workspace_id = f.workspace_id
 AND r.run_id       = f.run_id

LEFT JOIN system.mlflow.experiments_latest e
  ON e.workspace_id   = f.workspace_id
 AND e.experiment_id  = f.experiment_id
;
