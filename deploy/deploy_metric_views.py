#!/usr/bin/env python3
"""Deploy the system-table metric views to a target catalog.schema.

Each metric view is created with:

    CREATE OR REPLACE VIEW <catalog>.<schema>.<name>_metrics
    WITH METRICS LANGUAGE YAML AS $$ <yaml> $$

The YAML definitions live in ../metric_views. A file is treated as holding
MULTIPLE views if it contains `--- <name>` marker lines (our convention);
otherwise the whole file is one view named after the file. In both cases the
deployed view name is `<base>_metrics`.

Auth uses the standard Databricks SDK resolution (env vars, or --profile for a
~/.databrickscfg profile). See deploy/README.md.

Usage:
    python deploy_metric_views.py --catalog my_cat --schema my_schema
    python deploy_metric_views.py --catalog my_cat --schema my_schema --warehouse-id abc123
    python deploy_metric_views.py --catalog my_cat --schema my_schema --dry-run
    python deploy_metric_views.py --catalog my_cat --schema my_schema --only billing_usage,query_history
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

MARKER = re.compile(r"^---\s+(\S+)\s*$")
METRIC_VIEWS_DIR = Path(__file__).resolve().parent.parent / "metric_views"


def parse_views(yaml_path: Path) -> list[tuple[str, str]]:
    """Return [(base_name, yaml_body), ...] for a YAML file.

    Multi-view files split on `--- <name>` markers; single-view files use the
    file stem as the base name and the whole file as the body.
    """
    text = yaml_path.read_text()
    lines = text.splitlines()
    marker_idxs = [i for i, ln in enumerate(lines) if MARKER.match(ln)]

    if not marker_idxs:
        return [(yaml_path.stem, text.strip())]

    views: list[tuple[str, str]] = []
    for n, start in enumerate(marker_idxs):
        name = MARKER.match(lines[start]).group(1)
        end = marker_idxs[n + 1] if n + 1 < len(marker_idxs) else len(lines)
        body = "\n".join(lines[start + 1 : end]).strip()
        views.append((name, body))
    return views


def discover(only: set[str] | None) -> list[tuple[str, str, Path]]:
    """Return [(view_name, yaml_body, source_file), ...] across all YAML files."""
    out: list[tuple[str, str, Path]] = []
    for yaml_path in sorted(METRIC_VIEWS_DIR.glob("*.yaml")):
        for base, body in parse_views(yaml_path):
            view = f"{base}_metrics"
            if only and base not in only and view not in only:
                continue
            out.append((view, body, yaml_path))
    return out


def build_statement(catalog: str, schema: str, view: str, body: str) -> str:
    fq = f"`{catalog}`.`{schema}`.`{view}`"
    return f"CREATE OR REPLACE VIEW {fq}\nWITH METRICS\nLANGUAGE YAML\nAS $$\n{body}\n$$"


def pick_warehouse(w) -> str:
    whs = list(w.warehouses.list())
    if not whs:
        sys.exit("No SQL warehouses found in this workspace. Pass --warehouse-id explicitly.")
    # Prefer a RUNNING warehouse, else the first one (it will auto-start).
    running = [x for x in whs if str(getattr(x, "state", "")).endswith("RUNNING")]
    chosen = (running or whs)[0]
    print(f"Auto-selected warehouse: {chosen.name} ({chosen.id})")
    return chosen.id


def run_statement(w, warehouse_id: str, catalog: str, schema: str, sql: str):
    """Execute a statement and wait for a terminal state; return (ok, error_str)."""
    from databricks.sdk.service.sql import StatementState

    resp = w.statement_execution.execute_statement(
        warehouse_id=warehouse_id,
        statement=sql,
        catalog=catalog,
        schema=schema,
        wait_timeout="50s",
    )
    # Poll if not yet terminal.
    terminal = {StatementState.SUCCEEDED, StatementState.FAILED,
                StatementState.CANCELED, StatementState.CLOSED}
    while resp.status and resp.status.state not in terminal:
        time.sleep(2)
        resp = w.statement_execution.get_statement(resp.statement_id)

    state = resp.status.state if resp.status else None
    if state == StatementState.SUCCEEDED:
        return True, None
    err = ""
    if resp.status and resp.status.error:
        err = f"{resp.status.error.error_code}: {resp.status.error.message}"
    return False, err or str(state)


def main() -> int:
    ap = argparse.ArgumentParser(description="Deploy system-table metric views.")
    ap.add_argument("--catalog", required=True, help="Target Unity Catalog catalog.")
    ap.add_argument("--schema", required=True, help="Target schema (must already exist).")
    ap.add_argument("--warehouse-id", help="SQL warehouse ID. Auto-selected if omitted.")
    ap.add_argument("--profile", help="~/.databrickscfg profile name (else default/env auth).")
    ap.add_argument("--only", help="Comma-separated view base names to deploy (default: all).")
    ap.add_argument("--dry-run", action="store_true", help="Print statements; do not execute.")
    args = ap.parse_args()

    only = {s.strip() for s in args.only.split(",")} if args.only else None
    views = discover(only)
    if not views:
        sys.exit("No matching metric views found.")

    print(f"Target: {args.catalog}.{args.schema}   |   {len(views)} metric view(s)\n")

    if args.dry_run:
        for view, body, src in views:
            print(f"-- {view}  (from {src.name})")
            print(build_statement(args.catalog, args.schema, view, body))
            print("\n" + "=" * 70 + "\n")
        return 0

    try:
        from databricks.sdk import WorkspaceClient
    except ImportError:
        sys.exit("databricks-sdk not installed. Run: pip install -r deploy/requirements.txt")

    w = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
    warehouse_id = args.warehouse_id or pick_warehouse(w)
    print()

    ok, failed = [], []
    for view, body, src in views:
        sql = build_statement(args.catalog, args.schema, view, body)
        success, err = run_statement(w, warehouse_id, args.catalog, args.schema, sql)
        if success:
            print(f"  [ ok ]  {view}")
            ok.append(view)
        else:
            hint = "  (needs SELECT grant on source table)" if "PERMISSION" in (err or "").upper() else ""
            print(f"  [FAIL]  {view}{hint}\n           {err}")
            failed.append((view, err))

    print(f"\nDeployed {len(ok)}/{len(views)}. Failed: {len(failed)}.")
    if failed:
        print("Failed views:", ", ".join(v for v, _ in failed))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
