-- =====================================================================
-- Model: job_run_timeline  (fact = system.lakeflow.job_run_timeline)
-- =====================================================================
-- One row per job-run time period. GRAIN = (workspace_id, run_id,
-- period_start_time): long-running runs are split into multiple period
-- rows (~1.16 rows/run observed), so run_id alone is NOT unique.
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest : snapshot equi-join on workspace_id (100% match)
--   * jobs (SCD)        : point-in-time on period_start_time, keyed on
--                         workspace_id + job_id (99.8% match, 0 M:N)
--
-- Deliberately EXCLUDED from the one-layer star:
--   * compute_ids -> compute.clusters : compute_ids is array<string>
--     (inherently 1:N). Empty in ~99.98% of rows here; cluster linkage
--     belongs in the task-level model via explode, not this fact.
--
-- LEFT JOINs preserve unmatched fact rows.
-- =====================================================================

WITH jobs_scd AS (
  SELECT workspace_id, job_id, name AS job_name, creator_id, run_as, description,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, job_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.lakeflow.jobs
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.job_id,
  f.run_id,
  f.period_start_time,
  f.period_end_time,
  f.trigger_type,
  f.result_state,
  f.run_type,
  f.run_name,
  f.termination_code,
  f.termination_type,
  f.run_duration_seconds,
  f.queue_duration_seconds,
  f.setup_duration_seconds,
  f.execution_duration_seconds,
  f.cleanup_duration_seconds,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- job definition (point-in-time) ----
  j.job_name,
  j.creator_id  AS job_creator_id,
  j.run_as      AS job_run_as,
  j.description AS job_description

FROM system.lakeflow.job_run_timeline f

-- workspace: snapshot equi-join
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

-- job definition: point-in-time on the run's start time
LEFT JOIN jobs_scd j
  ON j.workspace_id = f.workspace_id
 AND j.job_id       = f.job_id
 AND f.period_start_time >= j.change_time
 AND (f.period_start_time <  j.next_change_time OR j.next_change_time IS NULL)
;
