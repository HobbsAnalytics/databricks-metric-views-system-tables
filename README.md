# Databricks Metric Views for System Tables

Unity Catalog **Metric Views** covering the Databricks **system tables**
(`system.*`). The goal is a governed, reusable set of business/operational
metrics defined once in YAML and consumable consistently across Genie, AI/BI
dashboards, and SQL.

## Why

The `system` catalog exposes rich operational data — billing/usage, compute,
access/audit, lineage, query history, and more — but consuming it well means
re-deriving the same measures (cost, DBUs, job success rate, etc.) over and
over. Metric views let us define those measures once, with consistent
dimensions, and reuse them everywhere.

## Scope

One metric view per **fact** system table, surrounded by its validated
dimensions (a star, snowflaked where a dimension has its own foreign keys).
26 fact tables were identified; **24 are deployable** to a target
`<catalog>.<schema>` (2 are blocked only by missing SELECT grants on their
source tables). The deploy target is configurable — set `<catalog>` and
`<schema>` to wherever you want the metric views created.

## Repository layout

```
source_data/                       # source inputs the models are derived from
  system_tables.csv                #   catalog of all system tables (from docs)
  system_tables_schema.csv         #   per-column schema + comments (from information_schema)
metric_views/                      # one YAML metric-view definition per fact (the deliverable)
validation_sql/                    # validated SQL join spec per fact (proves each model is N:1)
docs/                              # documentation, diagrams, and methodology
  methodology/                     #   the rules used to produce the models
    PROCESS.md                     #     the per-fact discovery/validation workflow
    relationships.csv              #     every validated fact->dimension edge
    fact_dimension_inventory.csv   #     fact vs dimension classification
    FLAKE_JOINS.md                 #     snowflake/flake rules, loop-safety, PIT pattern
  erd_overview/                    #   whole-catalog ERDs (all facts: single + by-family)
  erd_per_model/                   #   one ERD per semantic model (metric view)
  flake_joins_for_product.md       #   metric-views product-team writeup
```

## Join-logic rules (how we keep every model relationally valid)

Every join was SQL-validated before deployment. The rules we followed:

1. **One fact per view.** Each metric view's `source` is a single event/measurement
   fact table. Dimensions attach via joins; we never union facts.
2. **Prove N:1, never M:N.** Every join is `cardinality: many_to_one` with
   `rely: at_most_one_match: true`. We only assert that after verifying it: the
   fully-joined row count must equal the base fact row count (zero inflation).
3. **Point-in-time joins for slow-changing dimensions.** Most dimensions
   (clusters, warehouses, jobs, pipelines, …) keep full history. We attribute each
   fact row to the dimension version in effect at the event time, using a validity
   window `fact_ts >= change_time AND (fact_ts < next_change_time OR next_change_time IS NULL)`,
   where `next_change_time = lead(change_time)`. Snapshot/`_latest` and lookup
   dimensions use a plain equi-join.
4. **Keys are workspace-scoped.** Most entity IDs are unique only within a
   workspace, so joins key on `workspace_id` + the entity id (account-scoped
   dimensions like `list_prices` are the exception).
5. **Scope foreign keys to where they are valid.** A key can mean different things
   for different rows — e.g. `billing.usage.usage_metadata.cluster_id` is a real
   cluster only for classic-compute products — so product/type predicates live
   inside the join `on` clause.
6. **Inline SQL sources, not helper views.** A join's `source` can be an inline
   `SELECT`, so the point-in-time window (and any flake pre-joins) live directly in
   the metric view — each view is fully self-contained.
7. **Snowflake (flake) dimensions are pre-joined inside the parent's inline source.**
   Native nested joins break for point-in-time SCD parents (they resolve the parent
   as a scalar keyed on equi-columns only, ignoring the range predicate). Instead we
   `LEFT JOIN` the sub-dimension inside the parent's inline `SELECT` so its
   attributes ride along as parent columns — one join level from the fact, N:1
   preserved. See [`docs/methodology/FLAKE_JOINS.md`](docs/methodology/FLAKE_JOINS.md).
8. **The FK graph is a DAG — no join loops.** Flake chains always flow toward a
   leaf dimension (e.g. clusters → instance_pools → node_types → ∎) and terminate.
   The single self-referential edge (`query.history.cache_origin_statement_id`) is
   deliberately never flaked, and the pre-join pattern is non-recursive regardless.
9. **Comments + formatting carry through.** Dimension/measure comments are pulled
   from the source column comments; measures declare a display `format` (number,
   currency, percentage, date).
10. **Validate on a closed time window.** Integrity checks (`base rows == joined
    rows`) run over a fully-past window, since high-ingest facts land new rows
    mid-query and cause false mismatches.

## Metric view basics

A Unity Catalog metric view is created from a YAML spec that defines a `source`,
`dimensions`, `measures`, and optional `joins`. See the Databricks docs on
[metric views](https://docs.databricks.com/aws/en/metric-views/) for the current
spec, and [`metric_views/README.md`](metric_views/README.md) for the per-view
status table and deployment notes.

## Future: one semantic model across all system tables

> **Note.** Today a metric view has a **single `source` fact**, so this project is
> a *collection* of fact-specific models that share common dimensions (workspace,
> clusters, jobs, …) but remain separate views. Once **multi-fact metric views**
> (relationships across facts via shared conformed dimensions) are supported, the
> validated relationships in [`docs/methodology/relationships.csv`](docs/methodology/relationships.csv)
> can be composed into a **single semantic model spanning all system tables** —
> letting a user analyze cost, compute utilization, job runs, query performance,
> and lineage together through one conformed set of dimensions. The per-fact models
> here are built to slot directly into that model when it lands.
