-- =====================================================================
-- Model: billing_usage  (fact = system.billing.usage)
-- =====================================================================
-- One row per billable usage record, enriched with its point-in-time
-- dimension context. Every join below was SQL-validated as N:1 with
-- zero many-to-many (see relationships/relationships.csv).
--
-- Join rules encoded here:
--   * SCD dimensions (clusters/warehouses/instance_pools/jobs/pipelines/
--     served_entities) use POINT-IN-TIME: match the dim version whose
--     validity window [change_time, next change_time) contains
--     usage_start_time. Keyed on workspace_id + entity_id because entity
--     ids are only unique within a workspace.
--   * list_prices uses point-in-time on its own [price_start_time,
--     price_end_time) window and is ACCOUNT-scoped (sku_name only).
--   * workspaces_latest is a snapshot dim (no validity window) -> plain
--     equi-join on workspace_id.
--   * Product-scoped edges (job/pipeline/cluster) only attach for the
--     billing_origin_product where that id is a real FK; otherwise the
--     id is an internal identifier that does not exist in the dim.
--
-- LEFT JOINs throughout so unmatched usage rows are preserved (orphan
-- rates are expected and documented per edge).
-- =====================================================================

WITH
-- ---- SCD dimensions reduced to validity windows -------------------
clusters_scd AS (
  SELECT workspace_id, cluster_id, cluster_name, owned_by, dbr_version,
         data_security_mode, worker_node_type, driver_node_type, policy_id,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, cluster_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.clusters
),
warehouses_scd AS (
  SELECT workspace_id, warehouse_id, warehouse_name, warehouse_type, warehouse_size,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, warehouse_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.warehouses
),
instance_pools_scd AS (
  SELECT workspace_id, instance_pool_id, instance_pool_name, node_type,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, instance_pool_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.compute.instance_pools
),
jobs_scd AS (
  SELECT workspace_id, job_id, name AS job_name, creator_id, run_as,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, job_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.lakeflow.jobs
),
pipelines_scd AS (
  SELECT workspace_id, pipeline_id, name AS pipeline_name, created_by, run_as,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, pipeline_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.lakeflow.pipelines
),
served_entities_scd AS (
  SELECT workspace_id, endpoint_id, endpoint_name, served_entity_id,
         served_entity_name, entity_name, entity_type,
         change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, endpoint_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.serving.served_entities
)

SELECT
  -- ---- fact measures & grain ----
  u.record_id,
  u.account_id,
  u.workspace_id,
  u.sku_name,
  u.billing_origin_product,
  u.usage_start_time,
  u.usage_end_time,
  u.usage_date,
  u.usage_unit,
  u.usage_quantity,
  u.custom_tags,

  -- ---- list price (point-in-time) + derived list cost ----
  -- pricing is a struct; effective_list.default is the rate used for cost,
  -- falling back to default when effective_list is absent.
  coalesce(lp.pricing.effective_list.default, lp.pricing.default) AS list_price_usd,
  u.usage_quantity * coalesce(lp.pricing.effective_list.default, lp.pricing.default) AS list_cost_usd,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- classic compute cluster (PIT, classic-compute products only) ----
  cl.cluster_name,
  cl.owned_by                          AS cluster_owner,
  cl.dbr_version,
  cl.worker_node_type,
  cl.driver_node_type,

  -- ---- SQL warehouse (PIT) ----
  wh.warehouse_name,
  wh.warehouse_type,

  -- ---- instance pool (PIT) ----
  ip.instance_pool_name,

  -- ---- job (PIT, JOBS product) ----
  j.job_name,
  j.creator_id                         AS job_creator_id,

  -- ---- pipeline (PIT, DLT product) ----
  p.pipeline_name,

  -- ---- serving endpoint / entity (PIT) ----
  se.endpoint_name,
  se.served_entity_name

FROM system.billing.usage u

-- workspace: snapshot equi-join
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = u.workspace_id

-- list price: account-scoped, point-in-time on price window
LEFT JOIN system.billing.list_prices lp
  ON lp.sku_name = u.sku_name
 AND u.usage_start_time >= lp.price_start_time
 AND (u.usage_start_time <  lp.price_end_time OR lp.price_end_time IS NULL)

-- clusters: PIT + scope to classic compute
LEFT JOIN clusters_scd cl
  ON cl.workspace_id = u.workspace_id
 AND cl.cluster_id   = u.usage_metadata.cluster_id
 AND u.billing_origin_product IN ('JOBS','ALL_PURPOSE','DLT')
 AND u.usage_start_time >= cl.change_time
 AND (u.usage_start_time <  cl.next_change_time OR cl.next_change_time IS NULL)

-- warehouses: PIT
LEFT JOIN warehouses_scd wh
  ON wh.workspace_id = u.workspace_id
 AND wh.warehouse_id = u.usage_metadata.warehouse_id
 AND u.usage_start_time >= wh.change_time
 AND (u.usage_start_time <  wh.next_change_time OR wh.next_change_time IS NULL)

-- instance pools: PIT
LEFT JOIN instance_pools_scd ip
  ON ip.workspace_id     = u.workspace_id
 AND ip.instance_pool_id = u.usage_metadata.instance_pool_id
 AND u.usage_start_time >= ip.change_time
 AND (u.usage_start_time <  ip.next_change_time OR ip.next_change_time IS NULL)

-- jobs: PIT + scope to JOBS product
LEFT JOIN jobs_scd j
  ON j.workspace_id = u.workspace_id
 AND j.job_id       = u.usage_metadata.job_id
 AND u.billing_origin_product = 'JOBS'
 AND u.usage_start_time >= j.change_time
 AND (u.usage_start_time <  j.next_change_time OR j.next_change_time IS NULL)

-- pipelines: PIT + scope to DLT product
LEFT JOIN pipelines_scd p
  ON p.workspace_id = u.workspace_id
 AND p.pipeline_id  = u.usage_metadata.dlt_pipeline_id
 AND u.billing_origin_product = 'DLT'
 AND u.usage_start_time >= p.change_time
 AND (u.usage_start_time <  p.next_change_time OR p.next_change_time IS NULL)

-- serving endpoint/entity: PIT
-- NOTE: keyed on endpoint_id. An endpoint may contain multiple served
-- entities (latent 1:N). Validated 1:1 in current data, but if a future
-- endpoint holds >1 entity per window this becomes M:N -- dedup to one
-- entity per endpoint window, or key on served_entity_id, before relying on it.
LEFT JOIN served_entities_scd se
  ON se.workspace_id = u.workspace_id
 AND se.endpoint_id  = u.usage_metadata.endpoint_id
 AND u.usage_start_time >= se.change_time
 AND (u.usage_start_time <  se.next_change_time OR se.next_change_time IS NULL)
;
