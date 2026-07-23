# Flake (snowflake) dimensions — validation findings

Goal: add 2nd/3rd-level dimensions (dimension → sub-dimension) to the fact metric
views while preserving relational integrity (N:1, no row explosion).

## Flake edges validated (dimension level, N:1, 0 inflation)

| Flake edge | Level | Inflation | Match |
|------------|-------|-----------|-------|
| clusters.worker_node_type → node_types | 2 | 0 | 100% |
| clusters.driver_node_type → node_types | 2 | 0 | 100% |
| instance_pools.node_type → node_types | 2 | 0 | 100% |
| runs_latest.experiment_id → experiments_latest | 2 | 0 | 98.4% |

All join on `(account_id, node_type)` or `(workspace_id, experiment_id)`; the
sub-dimension PK is unique, so each is a clean N:1 at the dimension level.

## KEY FINDING — how flakes must be built in a metric view

Metric-view **nested joins** (`joins:` under a parent join, referenced in
dimensions via the full path `parent.child.col`) do work for plain/deduped
dimension sources. BUT they FAIL for our **point-in-time SCD** parents:

- When a nested-flake column is referenced in a query, the engine evaluates the
  PARENT join as a scalar subquery keyed only on the pushed-down join columns.
- It does NOT push the point-in-time range predicate
  (`ts BETWEEN change_time AND next_change_time`) into that scalar evaluation.
- So the multi-version SCD source returns >1 row per key →
  `SCALAR_SUBQUERY_TOO_MANY_ROWS` (SQLSTATE 21000).

Proven on a test view: referencing a parent (cluster) column succeeded, while
referencing the nested-flake (node_types) column on the SAME view errored.

### The correct pattern: PRE-JOIN the flake inside the parent's inline SCD source

Join the sub-dimension INSIDE the parent join's inline SQL, so the flake
attribute becomes a regular column of the (still point-in-time) parent dimension.
This keeps ONE join level from the fact's perspective — integrity preserved,
point-in-time accuracy preserved, no scalar-subquery error.

```yaml
joins:
  - name: cluster
    source: |
      SELECT c.workspace_id, c.cluster_id, c.cluster_name, c.worker_node_type,
             wn.core_count AS worker_core_count, wn.memory_mb AS worker_memory_mb,
             c.change_time,
             lead(c.change_time) OVER (PARTITION BY c.workspace_id, c.cluster_id
                                       ORDER BY c.change_time) AS next_change_time
      FROM system.compute.clusters c
      LEFT JOIN system.compute.node_types wn                      -- <-- flake pre-joined here
        ON wn.account_id = c.account_id AND wn.node_type = c.worker_node_type
    "on": cluster.workspace_id = source.workspace_id
      AND cluster.cluster_id = source.cluster_id
      AND source.start_time >= cluster.change_time
      AND (source.start_time < cluster.next_change_time OR cluster.next_change_time IS NULL)
    cardinality: many_to_one
    rely:
      at_most_one_match: true
dimensions:
  - name: Worker Cores
    expr: cluster.worker_core_count     # flake attribute rides along on the parent dim
```

### Verified result

Base fact rows == MV records (no flake ref) == MV records (grouped by flake dim):
9,080,849 == 9,080,849 == 9,080,849 on node_timeline → clusters → node_types.
Zero inflation whether or not the flake dimension is activated.

## Rule going forward

- **Snapshot/plain parents** (no SCD): true nested `joins:` are fine (validated on
  a deduped source). Full-path dimension refs `parent.child.col`.
- **Point-in-time SCD parents**: DO NOT use nested `joins:`. Pre-join the
  sub-dimension inside the parent's inline SCD `source:` subquery instead.
- Either way, validate: `COUNT(base fact) == SUM of MEASURE(record count) grouped
  by the new flake dimension`.

## Deeper chains (3rd level)

The same rule composes: a 3rd-level attribute (e.g. cluster → instance_pool →
node_type) is pre-joined inside the parent inline source via additional LEFT
JOINs in the subquery. Each added LEFT JOIN must itself be N:1 on its key (all
node_types / pool keys validated unique), so no LEFT JOIN inflates the subquery.

Implemented 3rd-level chain (validated 0 inflation on closed windows):
`fact → clusters (SCD) → worker_instance_pool_id → instance_pools (SCD) → node_type → node_types`
in billing_usage, node_timeline, instance_events, query_history. The pool join is
point-in-time on the cluster's `change_time`; the node_types join is a plain lookup.
Verified e.g. node_timeline 94,288 == 94,288 and billing_usage 2,643,769 == 2,643,769
with the 3rd-level flake dimensions grouped.

## Terminal-completeness audit (are all furthest-out flakes joined?)

We scanned every dimension's columns for outbound foreign keys to OTHER system
tables (separating each dimension's own primary key from genuine outbound edges).
The complete outbound-FK edge set among the dimensions in use:

| Edge | In models? |
|------|-----------|
| clusters.worker_instance_pool_id → instance_pools | yes (3rd-level flake) |
| clusters.driver_instance_pool_id → instance_pools | no (driver pool rarely used; worker chosen as representative) |
| instance_pools.node_type → node_types | yes |
| job_tasks.job_id → jobs | yes (both joined at fact level) |
| runs_latest.experiment_id → experiments_latest | yes (both joined at fact level) |
| query.history.cache_origin_statement_id → query.history | NO — self-referential (see below) |

**Leaf dimensions** (no outbound FK to any system table — a flake chain always
terminates at one of these): workspaces_latest, list_prices, node_types,
warehouses, pipelines, jobs, served_entities, experiments_latest.
`node_types` is the sink for every compute flake chain.

## Loop safety

- **The FK graph among these dimensions is a DAG.** Following FKs always flows
  strictly toward a leaf (…→ instance_pools → node_types → ∎). No path returns to
  an ancestor, so natural flake expansion always terminates. There is no risk of an
  endless loop from ordinary flaking.
- **One self-referential edge exists:** `query.history.cache_origin_statement_id`
  points back into `query.history` (a cache hit referencing the query that
  populated the cache). This is the ONLY cycle in the whole graph. We deliberately
  do NOT flake it.
- **The pre-join pattern cannot loop regardless.** Pre-joining a sub-dimension is a
  single explicit `LEFT JOIN` inside an inline source — there is no recursive
  traversal. Even a self-referential edge would only expand exactly as many levels
  as you hand-write; nothing auto-recurses.

**Rules to codify:**
1. Never flake a self-referential edge (e.g. cache_origin_statement_id).
2. Treat the FK graph as a DAG; a chain is complete when it reaches a leaf
   dimension (no outbound FK to a system table).
3. `driver_instance_pool_id` is an available-but-unflaked edge, symmetric to the
   worker pool chain; add it only if driver-pool hardware is specifically needed.
