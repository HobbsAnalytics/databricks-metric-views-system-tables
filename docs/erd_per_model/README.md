# ERDs — per semantic model

One Entity Relationship Diagram **per semantic model** (metric view) — the
close-up, model-by-model view. For the whole-catalog picture (all facts in one
diagram and grouped by family) see [`../erd_overview/`](../erd_overview/).

Each diagram shows the model's **fact** at the center with its validated
dimension joins, and any snowflake/flake chains above the dimensions.

Reading the diagrams:
- Crow's-foot points at the **many** side (the fact). Every edge is **N:1**
  (fact → dimension), so no join inflates the fact grain.
- Edge labels are the join key, with `(PIT)` marking a point-in-time SCD join and
  product/type scoping noted where it applies.
- Flake (snowflake) edges sit above their parent dimension. Where one dimension is
  reached by more than one path (e.g. `node_types` as worker hardware, driver
  hardware, and pool hardware), the diagram shows a separate node per path
  (`NODE_TYPES`, `NODE_TYPES_2`, …) since a diagram entity can't be reused — each
  is the same physical `system.compute.node_types` table via a different key.
- **Standalone facts** (replication_states, clean_room_events, dq_monitoring,
  data_classification) have no dimension joins and render as a single entity.

Each model has a `.mmd` (mermaid source, renders inline on GitHub) and a rendered
`.png`.

## Models

| Model (metric view) | Fact | Dimensions | Flake depth |
|---------------------|------|-----------:|:-----------:|
| billing_usage | system.billing.usage | 8 | 3rd level |
| job_run_timeline | system.lakeflow.job_run_timeline | 2 | — |
| job_task_run_timeline | system.lakeflow.job_task_run_timeline | 3 | — |
| pipeline_update_timeline | system.lakeflow.pipeline_update_timeline | 2 | — |
| node_timeline | system.compute.node_timeline | 3 | 3rd level |
| instance_events | system.compute.instance_events | 4 | 3rd level |
| warehouse_events | system.compute.warehouse_events | 2 | — |
| query_history | system.query.history | 3 | 3rd level |
| table_lineage | system.access.table_lineage | 2 (incl. query.history) | — |
| column_lineage | system.access.column_lineage | 2 (incl. query.history) | — |
| audit | system.access.audit | 1 | — |
| assistant_events | system.access.assistant_events | 1 | — |
| inbound_network | system.access.inbound_network | 1 | — |
| outbound_network | system.access.outbound_network | 1 | — |
| endpoint_usage | system.serving.endpoint_usage | 2 | — |
| run_metrics_history | system.mlflow.run_metrics_history | 3 | — |
| ai_gateway_usage | system.ai_gateway.usage | 1 | — |
| ai_gateway_external_model_spend | system.ai_gateway.external_model_spend | 1 | — |
| materialization_history | system.sharing.materialization_history | 1 | — |
| predictive_optimization | system.storage.predictive_optimization_operations_history | 1 | — |
| zerobus_ingest | system.lakeflow.zerobus_ingest | 1 | — |
| zerobus_stream | system.lakeflow.zerobus_stream | 1 | — |
| replication_states | system.replication.states | 0 (standalone) | — |
| clean_room_events | system.access.clean_room_events | 0 (standalone) | — |
| dq_monitoring | system.data_quality_monitoring.table_results | 0 (standalone) | — |
| data_classification | system.data_classification.results | 0 (standalone) | — |

`dq_monitoring` and `data_classification` are modeled but not yet deployed
(pending SELECT grants on their source tables).

The workspace-wide ERD across all facts lives in
[`../erd_overview/erd_families.md`](../erd_overview/erd_families.md); once multi-fact metric views are
supported these per-model stars compose into a single semantic model.
