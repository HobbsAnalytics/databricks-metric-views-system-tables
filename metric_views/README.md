# Metric Views

Unity Catalog **Metric Views** (YAML v1.1) built from the validated fact-specific
star models in `../models/`. One metric view per fact table (current UC limitation:
a metric view has a single `source` fact; cross-fact relationships via shared
dimensions are a planned future capability).

## Deploy target

`mfg_mc_se_sa.sys_table_semantics` on the FEVM workspace (`fevm-mfg-mc-se-sa`).

## How point-in-time joins are expressed

Our validated joins are **point-in-time SCD joins**, not simple equi-joins. Metric
view `on:` clauses accept arbitrary boolean expressions, so the range predicate
`fact_ts >= dim.change_time AND (fact_ts < dim.next_change_time OR ... IS NULL)`
works — but `next_change_time` must exist on the dimension. It does not exist on
the raw system tables, so we materialize it in **SCD helper views**
(`deploy/00_scd_helper_views.sql`): raw dim + `lead(change_time)` window.

Each join declares `cardinality: many_to_one` and `rely: at_most_one_match: true`,
which our SQL validation earned (every edge proven N:1, 0 many-to-many). Snapshot
dims (`workspaces_latest`, `node_types`) and window dims (`list_prices`, which has
its own `price_start/end_time`) join directly with no helper view.

Product-scoped edges (cluster/job/pipeline on `billing.usage`) carry the
`billing_origin_product` predicate **inside** the join `on` clause, so the foreign
key only attaches for the rows where it is valid.

## Deployment order

1. `deploy/00_scd_helper_views.sql` — create the 6 SCD helper views (run each stmt).
2. Deploy each metric view (`CREATE OR REPLACE VIEW ... WITH METRICS LANGUAGE YAML`).
   The exact per-view deploy SQL is generated from the `*.yaml` files.

## Status

| Metric view | Fact | Status |
|-------------|------|--------|
| `billing_usage_metrics` | system.billing.usage | DEPLOYED + query-validated |

More metric views to follow, one per fact, reusing the shared SCD helper views.

## Querying

Measures must be wrapped in `MEASURE()`; `SELECT *` is not supported.

```sql
SELECT `Billing Origin Product`,
       MEASURE(`List Cost (USD)`) AS list_cost_usd
FROM mfg_mc_se_sa.sys_table_semantics.billing_usage_metrics
WHERE `Usage Date` >= current_date() - INTERVAL 7 DAYS
GROUP BY ALL ORDER BY list_cost_usd DESC;
```
