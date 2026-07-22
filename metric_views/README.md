# Metric Views

Unity Catalog **Metric Views** (YAML v1.1) built from the validated fact-specific
star models in `../models/`. One metric view per fact table (current UC limitation:
a metric view has a single `source` fact; cross-fact relationships via shared
dimensions are a planned future capability).

## Deploy target

`mfg_mc_se_sa.sys_table_semantics` on the FEVM workspace (`fevm-mfg-mc-se-sa`).

## How point-in-time joins are expressed (inline SQL sources)

Our validated joins are **point-in-time SCD joins**, not simple equi-joins. Two
facts make this work cleanly:

1. A metric view join's `on:` clause accepts an arbitrary boolean expression, so
   the range predicate
   `fact_ts >= dim.change_time AND (fact_ts < dim.next_change_time OR ... IS NULL)`
   is valid.
2. A join's `source:` accepts an **inline SQL query**, not just a table name. So we
   compute `next_change_time = lead(change_time) OVER (...)` directly inside the
   join source. No pre-created helper views are needed -- each metric view is fully
   self-contained.

Example inline SCD join source:

```yaml
- name: cluster
  source: |
    SELECT workspace_id, cluster_id, cluster_name, change_time,
           lead(change_time) OVER (PARTITION BY workspace_id, cluster_id ORDER BY change_time) AS next_change_time
    FROM system.compute.clusters
  "on": cluster.workspace_id = source.workspace_id
    AND cluster.cluster_id = source.usage_metadata.cluster_id
    AND source.usage_start_time >= cluster.change_time
    AND (source.usage_start_time < cluster.next_change_time OR cluster.next_change_time IS NULL)
  cardinality: many_to_one
  rely:
    at_most_one_match: true
```

Each join declares `cardinality: many_to_one` and `rely: at_most_one_match: true`,
which our SQL validation earned (every edge proven N:1, 0 many-to-many). Snapshot
dims (`workspaces_latest`, `node_types`) and window dims (`list_prices`, which has
its own `price_start/end_time`) join directly as plain table sources.

Product-scoped edges (cluster/job/pipeline on `billing.usage`) carry the
`billing_origin_product` predicate **inside** the join `on` clause, so the foreign
key only attaches for the rows where it is valid.

Note: metric-view joined sources cannot expose MAP-typed columns, so inline join
sources select only the needed scalar columns (never `SELECT *` on a dim with maps).

## Deployment

Deploy each metric view with `CREATE OR REPLACE VIEW <name> WITH METRICS LANGUAGE
YAML AS $$ <yaml> $$`. The `*.yaml` files here are the source of truth; wrap them in
that statement to deploy. No helper views or ordering dependencies.

## Status

| Metric view | Fact | Status |
|-------------|------|--------|
| `billing_usage_metrics` | system.billing.usage | DEPLOYED + query-validated (inline SCD sources) |

More metric views to follow, one per fact.

## Querying

Measures must be wrapped in `MEASURE()`; `SELECT *` is not supported.

```sql
SELECT `Billing Origin Product`,
       MEASURE(`List Cost (USD)`) AS list_cost_usd
FROM mfg_mc_se_sa.sys_table_semantics.billing_usage_metrics
WHERE `Usage Date` >= current_date() - INTERVAL 7 DAYS
GROUP BY ALL ORDER BY list_cost_usd DESC;
```
