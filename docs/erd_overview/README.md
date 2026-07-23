# ERDs — whole-catalog overview

The **big-picture** ERDs spanning all system-table facts and dimensions at once.
For the close-up, one-diagram-per-metric-view breakdown, see
[`../erd_per_model/`](../erd_per_model/).

| File | What it shows |
|------|---------------|
| [`erd.md`](erd.md) | Single diagram of **all 26 facts** and their shared dimensions in one picture (`erd.png`). Comprehensive but dense. |
| [`erd_families.md`](erd_families.md) | The same relationships **split by family** (billing, lakeflow, compute, query+lineage, access, serving/ai/mlflow, misc) — easier to read. Rendered per-family PNGs: `erd_billing.png`, `erd_lakeflow.png`, `erd_compute.png`, `erd_query_lineage.png`, `erd_access.png`, `erd_serving_ai_mlflow.png`, `erd_misc.png`. |

All edges are **N:1 (fact → dimension)**; `access.workspaces_latest` is the
universal dimension shared by nearly every fact, and `query.history` doubles as a
dimension for the lineage facts. These shared/conformed dimensions are what a
future multi-fact semantic model would join across.
