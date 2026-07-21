# Layer-1 star models

One validated SQL model per fact table. Every join was SQL-tested for
**0 row inflation** (fan-out) and confirmed **N:1 with no many-to-many**.
Join rules follow `../relationships/PROCESS.md`: point-in-time on SCD
dimensions, snapshot equi-join on `_latest`/lookup dimensions, and
per-`billing_origin_product` scoping where a foreign key is only valid
for a subset of rows.

## Models by family

| File | Fact(s) | Key dimension edges |
|------|---------|---------------------|
| `billing_usage_model.sql` | billing.usage | workspaces, list_prices, clusters, warehouses, instance_pools, jobs, pipelines, served_entities |
| `job_run_timeline_model.sql` | lakeflow.job_run_timeline | workspaces, jobs |
| `job_task_run_timeline_model.sql` | lakeflow.job_task_run_timeline | workspaces, jobs, job_tasks |
| `pipeline_update_timeline_model.sql` | lakeflow.pipeline_update_timeline | workspaces, pipelines |
| `node_timeline_model.sql` | compute.node_timeline | workspaces, clusters, node_types |
| `instance_events_model.sql` | compute.instance_events | workspaces, instance_pools, clusters, node_types |
| `warehouse_events_model.sql` | compute.warehouse_events | workspaces, warehouses |
| `query_history_model.sql` | query.history | workspaces, warehouses, clusters |
| `table_lineage_model.sql` | access.table_lineage | workspaces, query.history (statement_id FK) |
| `column_lineage_model.sql` | access.column_lineage | workspaces, query.history (statement_id FK) |
| `access_events_models.sql` | access.audit, assistant_events, inbound_network, outbound_network | workspaces |
| `endpoint_usage_model.sql` | serving.endpoint_usage | workspaces, served_entities (served_entity_id) |
| `run_metrics_history_model.sql` | mlflow.run_metrics_history | workspaces, runs_latest, experiments_latest |
| `ai_gateway_models.sql` | ai_gateway.usage, ai_gateway.external_model_spend | workspaces |
| `misc_workspace_facts_models.sql` | sharing.materialization_history, storage.predictive_optimization, zerobus_ingest, zerobus_stream | workspaces |
| `standalone_facts.sql` | data_quality_monitoring.table_results, replication.states, clean_room_events, data_classification.results | none (no workspace_id, no joinable system dim) |

## Shared dimensions (snowflake hubs)

- **access.workspaces_latest** — universal: nearly every fact joins to it.
- **compute.clusters / warehouses / instance_pools / node_types** — shared across billing, compute, query, job facts.
- **lakeflow.jobs / job_tasks / pipelines** — shared across lakeflow facts + billing.
- **query.history** — acts as a dimension for the lineage facts.

## Validation method

For each model: `count(base_fact) == count(fully_joined)` over a recent
time window proves no edge fans out. Match rates and per-edge evidence
live in `../relationships/relationships.csv`.

## Next phase

Second-level joins / cross-model overlap: e.g. billing.usage cost attached
to job_run_timeline, predictive_optimization usage_quantity -> billing,
zerobus_stream <-> zerobus_ingest, mlflow experiment via runs_latest.
