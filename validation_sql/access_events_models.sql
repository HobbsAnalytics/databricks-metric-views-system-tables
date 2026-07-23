-- =====================================================================
-- Models: thin access event facts
--   system.access.audit
--   system.access.assistant_events
--   system.access.inbound_network
--   system.access.outbound_network
-- =====================================================================
-- These facts share a single validated one-layer edge:
--   * workspaces_latest : snapshot on workspace_id (N:1, 0 M:N)
-- They carry no other FK to a system dimension (user_identity, session_id,
-- request_id etc. have no system-table dimension to join to).
--
-- Match-rate notes (see relationships/relationships.csv):
--   audit           57%  -- account-level events have workspace_id NULL (expected)
--   assistant_events 96%
--   outbound_network 98.7%
--   inbound_network  0% here -- 167 rows, 1 workspace not in the snapshot (low volume)
-- =====================================================================

-- ---- audit ----------------------------------------------------------
SELECT
  f.account_id, f.workspace_id, f.event_id, f.event_time, f.service_name,
  f.action_name, f.audit_level, f.session_id, f.source_ip_address, f.user_agent,
  ws.workspace_name
FROM system.access.audit f
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id
;

-- ---- assistant_events -----------------------------------------------
SELECT
  f.account_id, f.workspace_id, f.event_id, f.event_time, f.user_agent, f.initiated_by,
  ws.workspace_name
FROM system.access.assistant_events f
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id
;

-- ---- inbound_network -------------------------------------------------
SELECT
  f.account_id, f.workspace_id, f.event_id, f.event_time, f.request_path,
  f.source, f.authenticated_as, f.policy_outcome, f.rule_label,
  ws.workspace_name
FROM system.access.inbound_network f
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id
;

-- ---- outbound_network ------------------------------------------------
SELECT
  f.account_id, f.workspace_id, f.event_id, f.event_time, f.destination_type,
  f.destination, f.access_type, f.dns_event, f.storage_event, f.network_source_type,
  ws.workspace_name
FROM system.access.outbound_network f
LEFT JOIN system.access.workspaces_latest ws
  ON ws.workspace_id = f.workspace_id
;
