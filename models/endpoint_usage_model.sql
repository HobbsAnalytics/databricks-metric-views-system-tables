-- =====================================================================
-- Model: endpoint_usage  (fact = system.serving.endpoint_usage)
-- =====================================================================
-- One row per model serving request (token usage record).
--
-- Validated one-layer star edges (see relationships/relationships.csv):
--   * workspaces_latest    : snapshot on workspace_id (100%)
--   * served_entities (SCD): point-in-time on request_time,
--                            key workspace_id + served_entity_id
--                            (99.99%, 0 M:N). served_entity_id is the
--                            DOCUMENTED FK (the safe key vs endpoint_id).
-- =====================================================================

WITH served_entities_scd AS (
  SELECT workspace_id, served_entity_id, endpoint_name, served_entity_name,
         entity_type, entity_name, entity_version, change_time,
         lead(change_time) OVER (PARTITION BY workspace_id, served_entity_id
                                 ORDER BY change_time) AS next_change_time
  FROM system.serving.served_entities
)

SELECT
  -- ---- fact grain & measures ----
  f.account_id,
  f.workspace_id,
  f.databricks_request_id,
  f.client_request_id,
  f.requester,
  f.status_code,
  f.request_time,
  f.input_token_count,
  f.output_token_count,
  f.input_character_count,
  f.output_character_count,
  f.request_streaming,
  f.served_entity_id,

  -- ---- workspace (snapshot) ----
  ws.workspace_name,

  -- ---- served entity (point-in-time) ----
  se.endpoint_name,
  se.served_entity_name,
  se.entity_type,
  se.entity_name,
  se.entity_version

FROM system.serving.endpoint_usage f

LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id

LEFT JOIN served_entities_scd se
  ON se.workspace_id      = f.workspace_id
 AND se.served_entity_id  = f.served_entity_id
 AND f.request_time >= se.change_time
 AND (f.request_time <  se.next_change_time OR se.next_change_time IS NULL)
;
