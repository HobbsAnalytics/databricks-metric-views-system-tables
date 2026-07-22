# Metric Views: point-in-time SCD dimensions + snowflake (flake) joins

**Audience:** Databricks Metric Views product team
**Author context:** Field project modeling all `system.*` tables as Metric Views
**TL;DR:** Nested (snowflake) joins in a Metric View are evaluated such that the
**parent join's `on:` predicate is not fully applied when a nested child column is
referenced** — the parent is resolved as an at-most-one *scalar lookup by key*.
For **point-in-time (range) SCD joins**, this breaks: the parent returns multiple
historical versions per key and the query fails with
`SCALAR_SUBQUERY_TOO_MANY_ROWS` (SQLSTATE 21000). Equi-join parents are unaffected.

---

## 1. Background: the point-in-time SCD join pattern

Many source tables are **slow-changing dimensions (SCD)** — multiple rows per
entity over time, each with a `change_time`. To attribute a fact row to the
dimension version in effect *at the time of the event*, we join on the key **and**
a validity window built with `lead()`:

```sql
-- dimension with a validity window [change_time, next_change_time)
SELECT key, attributes, change_time,
       lead(change_time) OVER (PARTITION BY key ORDER BY change_time) AS next_change_time
FROM dim
```

In a Metric View this goes in an inline join `source:`, with the window predicate
in `on:`:

```yaml
joins:
  - name: dim
    source: |
      SELECT key, attr, change_time,
             lead(change_time) OVER (PARTITION BY key ORDER BY change_time) AS next_change_time
      FROM dim
    "on": dim.key = source.key
      AND source.event_ts >= dim.change_time
      AND (source.event_ts < dim.next_change_time OR dim.next_change_time IS NULL)
    cardinality: many_to_one
    rely:
      at_most_one_match: true
```

This works perfectly for a **single-level** join: the window makes it N:1, and we
verified zero row inflation across ~24 fact tables.

---

## 2. The problem: nesting a child join under an SCD parent

We then tried to snowflake — add a **child** dimension under the SCD parent
(e.g. fact → `cluster` (SCD) → `node_type` (hardware lookup)):

```yaml
joins:
  - name: cluster
    source: |
      SELECT workspace_id, cluster_id, account_id, worker_node_type, change_time,
             lead(change_time) OVER (PARTITION BY workspace_id, cluster_id ORDER BY change_time) AS next_change_time
      FROM system.compute.clusters
    "on": cluster.workspace_id = source.workspace_id
      AND cluster.cluster_id = source.cluster_id
      AND source.start_time >= cluster.change_time
      AND (source.start_time < cluster.next_change_time OR cluster.next_change_time IS NULL)
    cardinality: many_to_one
    rely: { at_most_one_match: true }
    joins:
      - name: cnode                                    # <-- nested child (the flake)
        source: system.compute.node_types
        "on": cnode.account_id = cluster.account_id AND cnode.node_type = cluster.worker_node_type
        cardinality: many_to_one
        rely: { at_most_one_match: true }

dimensions:
  - name: Cluster Name
    expr: cluster.cluster_name
  - name: Worker Cores
    expr: cluster.cnode.core_count        # <-- full-path reference to nested child
```

### Observed behavior

- Querying only **parent** columns (`Cluster Name`) → **works**, point-in-time correct.
- Querying the **nested child** column (`Worker Cores`) on the *same view* →

```
[SCALAR_SUBQUERY_TOO_MANY_ROWS] More than one row returned by a subquery
used as an expression. SQLSTATE: 21000
```

### Diagnosis

Referencing the nested child causes the engine to resolve the **parent** join as a
correlated **scalar subquery keyed on the equi-columns only** — the range/window
part of the parent's `on:` (`event_ts BETWEEN change_time AND next_change_time`) is
**not applied** in that evaluation. Because an SCD source has many versions per
key, the scalar subquery returns >1 row → error.

We confirmed the parent dimension itself is genuinely N:1 under the full
predicate (validated by a `LATERAL` count: `max_matches = 1`, `rows_multi = 0`),
so this is specific to how nested-join resolution treats the parent, **not** a
data problem.

Note: `rely: at_most_one_match` on the child does not matter — removing it gives
the same error. It is the parent's scalar resolution that fails.

---

## 3. Two workarounds we validated

### (a) Works but wrong: dedupe the parent to one row per key

Collapsing the SCD parent to one row per key (`GROUP BY key ... any_value(...)`)
removes the error — but destroys point-in-time accuracy (you get an arbitrary
version). Not acceptable for time-aware attribution.

### (b) The correct pattern: pre-join the child INSIDE the parent's inline source

Move the child join *inside* the parent's inline SQL. The child attribute becomes
a regular column of the (still point-in-time) parent dimension, so from the Metric
View's perspective there is only **one** join level — no nesting, no scalar-lookup
issue, full point-in-time accuracy:

```yaml
joins:
  - name: cluster
    source: |
      SELECT c.workspace_id, c.cluster_id, c.cluster_name,
             wn.core_count AS worker_core_count,     -- child attribute rides along
             c.change_time,
             lead(c.change_time) OVER (PARTITION BY c.workspace_id, c.cluster_id
                                       ORDER BY c.change_time) AS next_change_time
      FROM system.compute.clusters c
      LEFT JOIN system.compute.node_types wn          -- <-- flake pre-joined here
        ON wn.account_id = c.account_id AND wn.node_type = c.worker_node_type
    "on": cluster.workspace_id = source.workspace_id
      AND cluster.cluster_id = source.cluster_id
      AND source.start_time >= cluster.change_time
      AND (source.start_time < cluster.next_change_time OR cluster.next_change_time IS NULL)
    cardinality: many_to_one
    rely: { at_most_one_match: true }

dimensions:
  - name: Worker Cores
    expr: cluster.worker_core_count
```

**Verified:** identical record counts to the parent-only view and to the base
fact — zero inflation whether or not the flake dimension is activated
(e.g. `9,080,849 == 9,080,849 == 9,080,849` on one fact).

---

## 4. Reproduction (verified on `system.*`)

This reproduces reliably on real system tables because the trigger requires an SCD
key with **multiple historical versions** — `system.compute.clusters` has up to 76
versions per `cluster_id`. The equi-key scalar lookup the engine uses for the
nested child then sees >1 parent row and fails.

**Important nuance:** a toy 2-3 row dimension may *not* reproduce the error — the
parent scalar still resolves to ≤1 row by chance. That makes this failure
**data-dependent on version count**: a view can pass in dev/test and then start
throwing in production once a hot key accumulates enough SCD versions. That is
precisely why it deserves product attention.

### FAILS — native nested join under an SCD parent

```sql
CREATE OR REPLACE VIEW <schema>.repro_nested WITH METRICS LANGUAGE YAML AS $$
version: 1.1
source: system.compute.node_timeline
joins:
  - name: cluster
    source: |
      SELECT workspace_id, account_id, cluster_id, cluster_name, worker_node_type, change_time,
             lead(change_time) OVER (PARTITION BY workspace_id, cluster_id ORDER BY change_time) AS next_change_time
      FROM system.compute.clusters
    "on": cluster.workspace_id = source.workspace_id
      AND cluster.cluster_id = source.cluster_id
      AND source.start_time >= cluster.change_time
      AND (source.start_time < cluster.next_change_time OR cluster.next_change_time IS NULL)
    cardinality: many_to_one
    rely: { at_most_one_match: true }
    joins:
      - name: cnode
        source: system.compute.node_types
        "on": cnode.account_id = cluster.account_id AND cnode.node_type = cluster.worker_node_type
        cardinality: many_to_one
        rely: { at_most_one_match: true }
dimensions:
  - name: Worker Node Type
    expr: cluster.worker_node_type
  - name: Worker Cores
    expr: cluster.cnode.core_count          -- nested-child reference (full path)
measures:
  - name: Records
    expr: COUNT(1)
$$;

-- Selecting only PARENT columns SUCCEEDS:
SELECT `Worker Node Type`, MEASURE(`Records`) FROM <schema>.repro_nested GROUP BY ALL;   -- ok

-- Selecting the NESTED-CHILD column ERRORS:
SELECT `Worker Cores`, MEASURE(`Records`) FROM <schema>.repro_nested
WHERE `Worker Cores` IS NOT NULL GROUP BY ALL;
--   [SCALAR_SUBQUERY_TOO_MANY_ROWS] More than one row returned by a subquery
--   used as an expression. SQLSTATE: 21000
```

### WORKS — pre-join the child inside the parent's inline source (PIT-correct)

```sql
CREATE OR REPLACE VIEW <schema>.repro_prejoin WITH METRICS LANGUAGE YAML AS $$
version: 1.1
source: system.compute.node_timeline
joins:
  - name: cluster
    source: |
      SELECT c.workspace_id, c.cluster_id, c.cluster_name, c.worker_node_type,
             wn.core_count AS worker_core_count,          -- child rides along as a parent column
             c.change_time,
             lead(c.change_time) OVER (PARTITION BY c.workspace_id, c.cluster_id ORDER BY c.change_time) AS next_change_time
      FROM system.compute.clusters c
      LEFT JOIN system.compute.node_types wn ON wn.account_id = c.account_id AND wn.node_type = c.worker_node_type
    "on": cluster.workspace_id = source.workspace_id
      AND cluster.cluster_id = source.cluster_id
      AND source.start_time >= cluster.change_time
      AND (source.start_time < cluster.next_change_time OR cluster.next_change_time IS NULL)
    cardinality: many_to_one
    rely: { at_most_one_match: true }
dimensions:
  - name: Worker Node Type
    expr: cluster.worker_node_type
  - name: Worker Cores
    expr: cluster.worker_core_count
measures:
  - name: Records
    expr: COUNT(1)
$$;

-- Both columns query cleanly, point-in-time correct:
SELECT `Worker Node Type`, `Worker Cores`, MEASURE(`Records`)
FROM <schema>.repro_prejoin WHERE `Worker Cores` IS NOT NULL GROUP BY ALL;   -- ok
```

Verified on the field workspace: the nested form succeeds on the parent column but
errors on the child column; the pre-join form returns record counts identical to
the base fact with the flake active (`9,080,849 == 9,080,849`), point-in-time
correct.

---

## 5. Product feedback / asks

1. **Push the parent join's full `on:` predicate (including range conditions) into
   the scalar evaluation used for nested-child resolution.** Then point-in-time
   SCD parents could use native nested `joins:` directly.
2. If (1) is hard, **document the limitation** and the pre-join workaround in the
   joins reference — today nothing warns that nested joins assume equi-key
   at-most-one parents.
3. Consider a first-class **"temporal / point-in-time join"** construct
   (`valid_from` / `valid_to` on a join) so users don't hand-roll `lead()` windows
   at all — this is an extremely common pattern over SCD system tables.

## 6. How to verify integrity (any metric view)

Row-count identity on a **closed** time window (avoid `current_date()` on
high-ingest facts, or new rows landing mid-query cause false mismatches):

```sql
SELECT
  (SELECT COUNT(*) FROM <fact>
     WHERE ts >= DATE'2026-07-20' AND ts < DATE'2026-07-21')                 AS base_rows,
  (SELECT SUM(r) FROM (
     SELECT MEASURE(`<count measure>`) AS r FROM <metric_view>
     WHERE `<ts dim>` >= DATE'2026-07-20' AND `<ts dim>` < DATE'2026-07-21'
     GROUP BY `<flake dimension>`))                                          AS mv_rows;
-- base_rows must equal mv_rows -> the flake added no inflation.
```
