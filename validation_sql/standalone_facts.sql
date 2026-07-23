-- =====================================================================
-- Standalone facts (NO validated one-layer star edge)
--   system.data_quality_monitoring.table_results
--   system.replication.states
--   system.access.clean_room_events
--   system.data_classification.results
-- =====================================================================
-- These four have NO workspace_id and NO foreign key to any system
-- dimension table, so there is no N:1 star edge to build. They are used
-- as single-table facts. Their natural keys (catalog_id / table_id /
-- schema_id / failover_group_name / central_clean_room_id) reference
-- Unity Catalog / account entities that do NOT have a system dimension
-- table to join to.
--
-- They are listed here (SELECT * passthroughs) for completeness so every
-- fact in the inventory has a model file. If a UC-object dimension (e.g.
-- information_schema.tables) is later admitted into scope, table_id-based
-- edges could be added -- but that is outside system.* and outside this
-- phase's one-layer-star goal.
-- =====================================================================

-- ---- data_quality_monitoring.table_results -------------------------
SELECT * FROM system.data_quality_monitoring.table_results;

-- ---- replication.states (Private Preview) ---------------------------
SELECT * FROM system.replication.states;

-- ---- access.clean_room_events ---------------------------------------
SELECT * FROM system.access.clean_room_events;

-- ---- data_classification.results (current-state snapshot) -----------
SELECT * FROM system.data_classification.results;
