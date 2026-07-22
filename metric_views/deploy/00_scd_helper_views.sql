-- =====================================================================
-- SCD helper views for point-in-time metric-view joins
-- Target schema: mfg_mc_se_sa.sys_table_semantics
-- =====================================================================
-- Metric view joins accept an arbitrary boolean `on` expression, so a
-- point-in-time (range) join is expressible -- but the SCD dimension needs
-- a next_change_time column (from lead()) that does not exist in the raw
-- system table. These helper views add it. MAP-typed columns are excluded
-- because metric-view joined tables cannot contain MAP columns.
--
-- One statement per view (run individually).
-- =====================================================================

CREATE OR REPLACE VIEW mfg_mc_se_sa.sys_table_semantics.scd_clusters AS
SELECT workspace_id, cluster_id, cluster_name, owned_by, dbr_version, data_security_mode,
       worker_node_type, driver_node_type, policy_id, cluster_source, change_time,
       lead(change_time) OVER (PARTITION BY workspace_id, cluster_id ORDER BY change_time) AS next_change_time
FROM system.compute.clusters;

CREATE OR REPLACE VIEW mfg_mc_se_sa.sys_table_semantics.scd_warehouses AS
SELECT workspace_id, warehouse_id, warehouse_name, warehouse_type, warehouse_size, change_time,
       lead(change_time) OVER (PARTITION BY workspace_id, warehouse_id ORDER BY change_time) AS next_change_time
FROM system.compute.warehouses;

CREATE OR REPLACE VIEW mfg_mc_se_sa.sys_table_semantics.scd_instance_pools AS
SELECT workspace_id, instance_pool_id, instance_pool_name, node_type, change_time,
       lead(change_time) OVER (PARTITION BY workspace_id, instance_pool_id ORDER BY change_time) AS next_change_time
FROM system.compute.instance_pools;

CREATE OR REPLACE VIEW mfg_mc_se_sa.sys_table_semantics.scd_jobs AS
SELECT workspace_id, job_id, name AS job_name, creator_id, run_as, change_time,
       lead(change_time) OVER (PARTITION BY workspace_id, job_id ORDER BY change_time) AS next_change_time
FROM system.lakeflow.jobs;

CREATE OR REPLACE VIEW mfg_mc_se_sa.sys_table_semantics.scd_pipelines AS
SELECT workspace_id, pipeline_id, name AS pipeline_name, pipeline_type, created_by, run_as, change_time,
       lead(change_time) OVER (PARTITION BY workspace_id, pipeline_id ORDER BY change_time) AS next_change_time
FROM system.lakeflow.pipelines;

CREATE OR REPLACE VIEW mfg_mc_se_sa.sys_table_semantics.scd_served_entities AS
SELECT workspace_id, served_entity_id, endpoint_name, served_entity_name, entity_type, entity_name, entity_version, change_time,
       lead(change_time) OVER (PARTITION BY workspace_id, served_entity_id ORDER BY change_time) AS next_change_time
FROM system.serving.served_entities;
