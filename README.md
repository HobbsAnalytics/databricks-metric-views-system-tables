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

One metric view (or a small set) per system schema, e.g.:

| System schema        | Example metrics |
|----------------------|-----------------|
| `system.billing`     | list-price cost, DBUs, cost by SKU/workspace/tag |
| `system.compute`     | cluster/warehouse utilization, node hours |
| `system.access`      | audit event counts, failed logins |
| `system.lakeflow`    | job & pipeline run counts, success/failure rate |
| `system.query`       | query counts, latency, bytes scanned |
| `system.lineage`     | table/column lineage activity |
| `system.storage`     | predictive optimization, storage growth |

(Exact coverage depends on which system schemas are enabled in the workspace.)

## Repository layout

```
metric_views/        # one YAML definition per metric view
```

## Metric view basics

A Unity Catalog metric view is created from a YAML spec that defines a
`source`, `dimensions`, and `measures`. See the Databricks docs on
[metric views](https://docs.databricks.com/aws/en/metric-views/) for the
current spec.

## Status

Early scaffold — metric view definitions to follow.
