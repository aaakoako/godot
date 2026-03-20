#!/usr/bin/env python3
"""
GameClawEngine C.1 Golden Case regression runner.

Runs verify_c1_ui_e2e.run_e2e() N times and reports structured results.
All logs and summary JSON are written to the artifacts/ directory.

Usage:
    python regression_runner.py                  # single run
    python regression_runner.py --repeat 3       # 3 consecutive runs
    python regression_runner.py --repeat 1 --ci  # CI mode (JSON summary to stdout on failure)

Exit codes:
    0 = all runs passed
    1 = one or more runs failed
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parent
ARTIFACTS_DIR = PROJECT / "artifacts"

sys.path.insert(0, str(PROJECT / "orchestrator"))
import verify_c1_ui_e2e  # noqa: E402


def _clean_artifacts() -> None:
    """Remove stale artifacts before a new run set to avoid uploading old logs."""
    if ARTIFACTS_DIR.exists():
        shutil.rmtree(ARTIFACTS_DIR)
    ARTIFACTS_DIR.mkdir(parents=True)


def _run_once(index: int, total: int) -> dict:
    """Run one E2E test pass. Returns a result record."""
    run_log_dir = ARTIFACTS_DIR / f"run_{index:03d}"
    run_log_dir.mkdir(parents=True, exist_ok=True)

    label = f"#{index}/{total}"
    print(f"[RUN {label}] Starting...", flush=True)
    t0 = time.time()
    try:
        rc = verify_c1_ui_e2e.run_e2e(log_dir=run_log_dir)
    except Exception as exc:
        rc = 1
        print(f"[RUN {label}] EXCEPTION: {exc}", flush=True)

    elapsed_ms = int((time.time() - t0) * 1000)
    ok = rc == 0
    status = "PASS" if ok else "FAIL"
    print(f"[{status} {label}] {elapsed_ms / 1000:.1f}s — logs: {run_log_dir}", flush=True)

    return {
        "index": index,
        "ok": ok,
        "rc": rc,
        "duration_ms": elapsed_ms,
        "log_dir": str(run_log_dir),
        "godot_log": str(run_log_dir / "e2e_godot.log"),
        "orch_log": str(run_log_dir / "e2e_orchestrator.log"),
    }


def _write_summary(results: list[dict], summary_path: Path) -> None:
    passed = sum(1 for r in results if r["ok"])
    failed = len(results) - passed
    summary = {
        "total_runs": len(results),
        "passed_runs": passed,
        "failed_runs": failed,
        "all_passed": failed == 0,
        "results": results,
    }
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="C.1 Golden Case regression runner")
    parser.add_argument(
        "--repeat", type=int, default=1, metavar="N",
        help="Number of consecutive runs (all must pass). Default: 1.",
    )
    parser.add_argument(
        "--ci", action="store_true",
        help="CI mode: suppress interactive output, print JSON summary to stdout on failure.",
    )
    parser.add_argument(
        "--initial-ir", dest="initial_ir", default=None,
        help="Set GAMECLAW_INITIAL_IR_PATH env var to override the initial IR file loaded by Godot.",
    )
    args = parser.parse_args()

    if args.initial_ir:
        os.environ["GAMECLAW_INITIAL_IR_PATH"] = args.initial_ir

    if args.repeat < 1:
        print("--repeat must be >= 1", file=sys.stderr)
        return 1

    _clean_artifacts()

    results: list[dict] = []
    for i in range(1, args.repeat + 1):
        record = _run_once(i, args.repeat)
        results.append(record)
        if not record["ok"] and not args.ci:
            # Fail fast in interactive mode after first failure.
            print(f"[ABORT] Run {i} failed. Skipping remaining runs.", flush=True)
            # Fill remaining as skipped so summary is complete.
            for j in range(i + 1, args.repeat + 1):
                results.append({"index": j, "ok": False, "rc": -1, "duration_ms": 0,
                                 "log_dir": "", "godot_log": "", "orch_log": "", "skipped": True})
            break

    summary_path = ARTIFACTS_DIR / "c1_golden_summary.json"
    _write_summary(results, summary_path)

    passed = sum(1 for r in results if r["ok"])
    failed = len(results) - passed
    all_passed = failed == 0

    print(f"\n{'='*50}", flush=True)
    print(f"Result: {passed}/{args.repeat} PASS", flush=True)
    print(f"Summary: {summary_path}", flush=True)

    if not all_passed:
        failed_runs = [r for r in results if not r["ok"]]
        if args.ci:
            print(json.dumps({
                "status": "FAIL",
                "passed": passed,
                "failed": failed,
                "failed_runs": failed_runs,
            }, ensure_ascii=False), flush=True)
        else:
            print("\nFailed runs:", flush=True)
            for r in failed_runs:
                if r.get("skipped"):
                    print(f"  #{r['index']} — skipped (previous run failed)", flush=True)
                else:
                    print(f"  #{r['index']} — rc={r['rc']} logs: {r['log_dir']}", flush=True)

    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
