-- =====================================================================
-- Model: job_task_run_timeline  (fact = system.lakeflow.job_task_run_timeline)
-- =====================================================================
-- One row per job-task run time period. GRAIN =
-- (workspace_id, run_id, period_start_time) -- validated unique.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot on workspace_id (100%)
--   * jobs (SCD)        : point-in-time on period_start_time,
--                         key workspace_id + job_id (99.8%, 0 M:N)
--   * job_tasks (SCD)   : point-in-time on period_start_time,
--                         key workspace_id + job_id + task_key
--                         (99.7%, 0 M:N). task_key only unique within a job.
--
-- EXCLUDED: compute_ids -> compute.clusters (array<string>, 1:N by design).
-- =====================================================================

WITH jobs_scd AS (
  SELECT workspace_id, job_id, name AS job_name, run_as, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, job_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.lakeflow.jobs
),
tasks_scd AS (
  SELECT workspace_id, job_id, task_key, depends_on_keys, timeout_seconds, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, job_id, task_key
                                 ORDER BY change_time) AS next_change_time
  FROM system.lakeflow.job_tasks
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.job_id,
  f.run_id,
  f.job_run_id,
  f.parent_run_id,
  f.task_key,
  f.period_start_time,
  f.period_end_time,
  f.result_state,
  f.termination_code,
  f.termination_type,
  f.setup_duration_seconds,
  f.execution_duration_seconds,
  f.cleanup_duration_seconds,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- job definition (point-in-time) ----
  j.job_name,
  j.run_as AS job_run_as,

  -- ---- task definition (point-in-time) ----
  t.depends_on_keys AS task_depends_on_keys,
  t.timeout_seconds AS task_timeout_seconds

FROM system.lakeflow.job_task_run_timeline f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN jobs_scd j
  ON j.workspace_id = f.workspace_id
 AND j.job_id       = f.job_id
 AND f.period_start_time >= j.change_time
 AND (f.period_start_time <  j.next_change_time OR j.next_change_time IS NULL)

LEFT JOIN tasks_scd t
  ON t.workspace_id = f.workspace_id
 AND t.job_id       = f.job_id
 AND t.task_key     = f.task_key
 AND f.period_start_time >= t.change_time
 AND (f.period_start_time <  t.next_change_time OR t.next_change_time IS NULL)
;
