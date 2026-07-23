# Deploy

Deploy all system-table metric views to a Unity Catalog `catalog.schema` of your
choosing. The script loops over every YAML definition in `../metric_views/` and
runs `CREATE OR REPLACE VIEW <catalog>.<schema>.<name>_metrics WITH METRICS
LANGUAGE YAML AS $$ … $$` for each.

## Prerequisites

- **Databricks Runtime 17.2+ SQL warehouse** (metric views YAML v1.1).
- The **target schema already exists** and you have `CREATE TABLE` + `USE SCHEMA`
  on it, plus `CAN USE` on a SQL warehouse.
- `SELECT` on the `system.*` source tables. Most are on by default; a few system
  schemas (e.g. `data_quality_monitoring`, `data_classification`) require an
  account admin to enable/grant them — views over tables you can't read will
  report `[FAIL] … (needs SELECT grant on source table)` and the rest still deploy.
- Python 3.9+ and the SDK: `pip install -r deploy/requirements.txt`.

## Authenticate

The script uses standard Databricks SDK auth resolution. Either:

```bash
export DATABRICKS_HOST=https://<your-workspace>.cloud.databricks.com
export DATABRICKS_TOKEN=<your-pat>
```

or use a `~/.databrickscfg` profile and pass `--profile <name>`.

## Run

```bash
pip install -r deploy/requirements.txt

# Preview the exact SQL without touching the workspace:
python deploy/deploy_metric_views.py --catalog my_cat --schema my_schema --dry-run

# Deploy everything (warehouse auto-selected):
python deploy/deploy_metric_views.py --catalog my_cat --schema my_schema

# Or pin a specific warehouse / a subset of views:
python deploy/deploy_metric_views.py --catalog my_cat --schema my_schema \
    --warehouse-id 0123456789abcdef --only billing_usage,query_history
```

### Options

| Flag | Meaning |
|------|---------|
| `--catalog` (required) | Target catalog. |
| `--schema` (required) | Target schema (must already exist). |
| `--warehouse-id` | SQL warehouse to run on. Auto-selected (prefers a RUNNING one) if omitted. |
| `--profile` | `~/.databrickscfg` profile name. Omit to use env vars / default auth. |
| `--only` | Comma-separated view base names (e.g. `billing_usage`) to deploy a subset. |
| `--dry-run` | Print the `CREATE … WITH METRICS` statements and exit; no workspace calls. |

## How the loop works

- Each file in `../metric_views/` is a metric-view definition.
- A file that contains `--- <name>` marker lines holds **multiple** views (one per
  marker); any other file is a **single** view named after the file.
- The deployed view name is always `<base>_metrics` — so `billing_usage.yaml` →
  `billing_usage_metrics`, and the `--- audit` block in `access_events.yaml` →
  `audit_metrics`. No hardcoded list; add a new YAML and it deploys automatically.

## Verify

```sql
SELECT `Billing Origin Product`, MEASURE(`List Cost (USD)`) AS cost
FROM my_cat.my_schema.billing_usage_metrics
WHERE `Usage Date` >= current_date() - INTERVAL 7 DAYS
GROUP BY ALL ORDER BY cost DESC;
```
