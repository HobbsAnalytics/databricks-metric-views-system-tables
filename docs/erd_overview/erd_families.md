# System Tables ERD — by family

Readable, per-family views of the validated one-layer star models. All edges are
**N:1 (fact → dimension)**, crow's-foot pointing at the many/fact side; labels are
join keys. `access.workspaces_latest` (WORKSPACES) is the universal dimension shared
by nearly every fact — shown in each family rather than as one central hairball.

Legend: `_SCD` = point-in-time join; `_PK`/`_lookup`/`_window` = equi-key join.

## Billing (cost/usage hub)

```mermaid
erDiagram
    WORKSPACES       ||--o{ BILLING_USAGE : workspace_id
    LIST_PRICES      ||--o{ BILLING_USAGE : sku_name
    CLUSTERS         ||--o{ BILLING_USAGE : "cluster_id (JOBS/ALL_PURPOSE/DLT)"
    WAREHOUSES       ||--o{ BILLING_USAGE : warehouse_id
    INSTANCE_POOLS   ||--o{ BILLING_USAGE : instance_pool_id
    JOBS             ||--o{ BILLING_USAGE : "job_id (JOBS)"
    PIPELINES        ||--o{ BILLING_USAGE : "dlt_pipeline_id (DLT)"
    SERVED_ENTITIES  ||--o{ BILLING_USAGE : endpoint_id
```

## Lakeflow (jobs & pipelines)

```mermaid
erDiagram
    WORKSPACES  ||--o{ JOB_RUN_TIMELINE : workspace_id
    JOBS        ||--o{ JOB_RUN_TIMELINE : job_id
    WORKSPACES  ||--o{ JOB_TASK_RUN_TIMELINE : workspace_id
    JOBS        ||--o{ JOB_TASK_RUN_TIMELINE : job_id
    JOB_TASKS   ||--o{ JOB_TASK_RUN_TIMELINE : "job_id+task_key"
    WORKSPACES  ||--o{ PIPELINE_UPDATE_TIMELINE : workspace_id
    PIPELINES   ||--o{ PIPELINE_UPDATE_TIMELINE : pipeline_id
```

## Compute (utilization & events)

```mermaid
erDiagram
    WORKSPACES      ||--o{ NODE_TIMELINE : workspace_id
    CLUSTERS        ||--o{ NODE_TIMELINE : cluster_id
    NODE_TYPES      ||--o{ NODE_TIMELINE : node_type
    WORKSPACES      ||--o{ INSTANCE_EVENTS : workspace_id
    INSTANCE_POOLS  ||--o{ INSTANCE_EVENTS : instance_pool_id
    CLUSTERS        ||--o{ INSTANCE_EVENTS : cluster_id
    NODE_TYPES      ||--o{ INSTANCE_EVENTS : node_type
    WORKSPACES      ||--o{ WAREHOUSE_EVENTS : workspace_id
    WAREHOUSES      ||--o{ WAREHOUSE_EVENTS : warehouse_id
```

## Query & Lineage (query.history doubles as a dimension)

```mermaid
erDiagram
    WORKSPACES     ||--o{ QUERY_HISTORY : workspace_id
    WAREHOUSES     ||--o{ QUERY_HISTORY : warehouse_id
    CLUSTERS       ||--o{ QUERY_HISTORY : cluster_id
    WORKSPACES     ||--o{ TABLE_LINEAGE : workspace_id
    QUERY_HISTORY  ||--o{ TABLE_LINEAGE : statement_id
    WORKSPACES     ||--o{ COLUMN_LINEAGE : workspace_id
    QUERY_HISTORY  ||--o{ COLUMN_LINEAGE : statement_id
```

## Access events (workspace only)

```mermaid
erDiagram
    WORKSPACES  ||--o{ AUDIT : workspace_id
    WORKSPACES  ||--o{ ASSISTANT_EVENTS : workspace_id
    WORKSPACES  ||--o{ INBOUND_NETWORK : workspace_id
    WORKSPACES  ||--o{ OUTBOUND_NETWORK : workspace_id
```

## Serving / AI Gateway / MLflow

```mermaid
erDiagram
    WORKSPACES          ||--o{ ENDPOINT_USAGE : workspace_id
    SERVED_ENTITIES     ||--o{ ENDPOINT_USAGE : served_entity_id
    WORKSPACES          ||--o{ RUN_METRICS_HISTORY : workspace_id
    RUNS_LATEST         ||--o{ RUN_METRICS_HISTORY : run_id
    EXPERIMENTS_LATEST  ||--o{ RUN_METRICS_HISTORY : experiment_id
    WORKSPACES          ||--o{ AI_GATEWAY_USAGE : workspace_id
    WORKSPACES          ||--o{ AI_GATEWAY_EXTERNAL_MODEL_SPEND : workspace_id
```

## Misc workspace-scoped facts

```mermaid
erDiagram
    WORKSPACES  ||--o{ MATERIALIZATION_HISTORY : workspace_id
    WORKSPACES  ||--o{ PREDICTIVE_OPTIMIZATION : workspace_id
    WORKSPACES  ||--o{ ZEROBUS_INGEST : workspace_id
    WORKSPACES  ||--o{ ZEROBUS_STREAM : workspace_id
```

## Standalone facts (no star edge)

No `workspace_id`, no FK to any system dimension — single-table facts:
`data_quality_monitoring.table_results`, `replication.states`,
`access.clean_room_events`, `data_classification.results`.

---

The full single-diagram version is in [`erd.md`](erd.md) (rendered: `erd.png`).
Per-family PNGs: `erd_<family>.png`.
