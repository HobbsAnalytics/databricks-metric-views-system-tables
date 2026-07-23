-- =====================================================================
-- Models: AI Gateway facts
--   system.ai_gateway.usage                (one inference request)
--   system.ai_gateway.external_model_spend (one hourly spend record)
-- =====================================================================
-- Both share a single validated one-layer edge:
--   * workspaces_latest : snapshot on workspace_id (N:1, 0 M:N)
--
-- NOTE: ai_gateway.usage.endpoint_id references the AI Gateway entity,
-- NOT system.serving.served_entities -- there is no system dimension
-- table for AI Gateway endpoints, so no other star edge exists.
-- =====================================================================

-- ---- ai_gateway.usage ----------------------------------------------
SELECT
  f.account_id, f.workspace_id, f.request_id, f.invocation_id,
  f.endpoint_id, f.endpoint_name, f.event_time,
  f.latency_ms, f.time_to_first_byte_ms,
  f.destination_type, f.destination_name, f.destination_model,
  f.requester, f.requester_type, f.api_type,
  f.input_tokens, f.output_tokens, f.total_tokens, f.status_code,
  ws.workspace_name
FROM system.ai_gateway.usage f
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id
;

-- ---- ai_gateway.external_model_spend --------------------------------
SELECT
  f.record_id, f.account_id, f.workspace_id,
  f.usage_date, f.usage_start_time, f.usage_end_time,
  f.usage_unit, f.usage_quantity, f.custom_tags,
  ws.workspace_name
FROM system.ai_gateway.external_model_spend f
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id
;
