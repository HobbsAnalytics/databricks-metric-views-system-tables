# Relationship discovery & validation process

Goal: assemble one or more semantic (metric-view) models over the system tables,
maximizing the number of tables joined while avoiding many-to-many (M:N) joins.
We expect a **snowflake** (not pure star): several fact tables, each surrounded by
dimensions, with some dimensions shared and some chained (dim → dim).

## The repeatable process (per fact table)

1. **Pick a fact.** A fact = an event/measurement grain (one row = one measurable
   thing). Start from `billing.usage` and expand outward along discovered edges.
2. **Derive candidate keys from metadata.** Read column names + comments from
   `source_data/system_tables_schema.csv`. Signals we rely on, in priority order:
   - Explicit comment language: "foreign key to join with …", "join with the …
     dimension table", "primary key".
   - `*_id` / `*_name` columns, including IDs nested inside structs
     (e.g. `billing.usage.usage_metadata.cluster_id`).
   - Naming matches between a fact column and a dimension's stated PK.
3. **Determine the true dimension grain.** Check whether the dimension's PK is
   actually unique. Many system dimensions are **SCD** tables (multiple rows per
   entity over time, e.g. `compute.clusters` has `change_time`). Their natural key
   is NOT unique on its own, so a naive join is M:N.
4. **Establish the join predicate.** Most entity IDs are **only unique within a
   workspace** (comment on `lakeflow.jobs.job_id`: "Only unique within a single
   workspace"). So joins usually need `workspace_id` + entity id, and for SCD dims
   a version-resolution rule (latest row, or point-in-time between
   `change_time`/`delete_time`).
5. **Record the candidate edge** in `relationships.csv` with an *expected*
   cardinality and a `status` of `candidate`.
6. **Validate in SQL (later step).** For each edge, measure real cardinality:
   - orphan rate (fact keys with no dim match),
   - max children per parent,
   - whether the parent side is unique.
   Promote to `validated` (1:1 / 1:N / N:1) or flag `many-to-many` for redesign.
7. **Expand.** Add any new dimension's own foreign keys as new candidate edges and
   repeat. Group connected components into logical models.

## Cardinality convention

Direction is written **fact → dimension**. We want each fact row to match at most
one dimension row, i.e. **N:1** (many fact rows → one dim row). N:1 and 1:1 are
safe; **M:N is disallowed** and must be resolved (usually by making the dimension
unique via a `_latest` view or point-in-time join).

## SCD resolution rule (decided)

**Default = point-in-time.** Whenever the fact has a usable timestamp and the SCD
dimension exposes a validity window (e.g. `change_time` … next `change_time` /
`delete_time`), join on key AND `fact_ts` within that window. This attributes each
fact row to the dimension config that was in effect when the event occurred.

**Fallback = latest snapshot.** Only when there is no time-bounded way to join
(fact lacks a timestamp, or the dim has no validity columns) do we reduce the dim
to one current row per key (most recent `change_time`, `delete_time IS NULL`).

Per-edge choice is recorded in `relationships.csv`.

## Status values used in relationships.csv

`candidate` (from metadata only) → `validated` (SQL-confirmed N:1/1:1) →
`many-to-many` (needs redesign) / `invalid` (no real overlap).
