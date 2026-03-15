"""
Sprint D2 E2E verifier: Poison Buff lifecycle test.

Flow:
  Start Godot with sprint_d2_poison_init.toon
  → Inject active_poison_001 (references poison_basic, target hero_1)
  → Verify granted_tags applied immediately (~50ms)
  → Wait ~1.1s → hp == 99
  → Wait ~2.1s → hp == 98
  → Wait ~3.5s → hp == 97, effect expired, tag removed

Public API (for regression_runner.py --sprint d2):
    run_e2e(log_dir: Path | None = None) -> int
        Returns 0 on pass, non-zero on failure.

CLI:
    python orchestrator/verify_d2_poison_e2e.py
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT
PROJECT_GODOT = PROJECT / "project.godot"

sys.path.insert(0, str(PROJECT))
from launch_godot import find_godot_exe, kill_existing_godot  # noqa: E402


INJECT_PATCH = json.dumps({
    "ops": [
        {
            "op": "add",
            "path": "/active_effects/active_poison_001",
            "value": {
                "type": "active_effect",
                "effect_def": "poison_basic",
                "target_entity": "hero_1",
                "elapsed": 0.0,
                "next_tick_at": 1.0,
                "_last_updated_at": 0.0,
            },
        }
    ]
})


def _load_mcp() -> tuple[str, int]:
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME", "")
    data = json.loads((Path(home) / ".cursor" / "mcp.json").read_text(encoding="utf-8"))
    env = data.get("mcpServers", {}).get("gameclaw", {}).get("env", {})
    host = env.get("GODOT_HOST", "127.0.0.1")
    port = int(env.get("GODOT_PORT", "0") or 0)
    return host, port


def _call(method: str, params: dict | None = None, req_id: int = 1) -> dict:
    host, port = _load_mcp()
    if port <= 0:
        return {"error": {"message": "GODOT_PORT unavailable"}}
    req = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params or {}}
    try:
        with socket.create_connection((host, port), timeout=8) as s:
            s.sendall((json.dumps(req) + "\n").encode("utf-8"))
            buf = b""
            while b"\n" not in buf:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8")
        return json.loads(line)
    except Exception as exc:
        return {"error": {"message": str(exc)}}


def _query(path: str) -> object:
    resp = _call("query_ir_path", {"path": path})
    result = resp.get("result", resp)
    if "error" in resp:
        return None
    data = result.get("data", result)
    return data.get("value", None)


def _assert(label: str, actual: object, expected: object, log: list[str]) -> bool:
    ok = actual == expected
    status = "PASS" if ok else "FAIL"
    msg = f"[{status}] {label}: expected={expected!r}, actual={actual!r}"
    print(msg, flush=True)
    log.append(msg)
    return ok


def _set_initial_path(path: str) -> None:
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    import re
    text = re.sub(
        r'config/initial_ir_path="[^"]*"',
        f'config/initial_ir_path="{path}"',
        text,
    )
    PROJECT_GODOT.write_text(text, encoding="utf-8")


def run_e2e(log_dir: Path | None = None) -> int:
    if log_dir is None:
        log_dir = PROJECT / "artifacts" / "d2_poison"
    log_dir = Path(log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)

    log: list[str] = []
    passed = True

    godot_exe = find_godot_exe()
    if not godot_exe:
        print("ERROR: Godot executable not found", flush=True)
        return 1

    _set_initial_path("res://test_data/sprint_d2_poison_init.toon")

    kill_existing_godot()
    godot_log_path = log_dir / "d2_godot.log"
    proc = subprocess.Popen(
        [godot_exe, "--path", str(PROJECT), "--headless"],
        stdout=open(godot_log_path, "w"),
        stderr=subprocess.STDOUT,
    )

    try:
        # Wait for Godot MCP to come up.
        print("Waiting for Godot MCP...", flush=True)
        for _ in range(30):
            time.sleep(0.5)
            resp = _call("ping")
            if resp.get("result", {}).get("pong") or resp.get("result") == "pong":
                break
        else:
            print("ERROR: Godot did not respond to ping", flush=True)
            return 1

        # Inject active_poison_001.
        print("Injecting active_poison_001...", flush=True)
        inject_resp = _call("apply_patch", {"patch": INJECT_PATCH})
        if inject_resp.get("result", {}).get("data", {}).get("applied") is not True:
            print(f"ERROR: inject failed: {inject_resp}", flush=True)
            return 1

        # T=0.15s: tags should be applied (EffectSystem runs within 50ms).
        time.sleep(0.25)
        tags = _query("/entities/hero_1/components/tag_set/runtime_tags")
        passed &= _assert("T~0.25s: state.poisoned in runtime_tags",
                          "state.poisoned" in (tags or []), True, log)

        # T=1.1s: hp == 99.
        time.sleep(1.1)
        hp = _query("/entities/hero_1/components/attribute_set/attributes/hp/current")
        passed &= _assert("T~1.1s: hp.current == 99", hp, 99.0, log)

        # T=2.1s: hp == 98.
        time.sleep(1.0)
        hp = _query("/entities/hero_1/components/attribute_set/attributes/hp/current")
        passed &= _assert("T~2.1s: hp.current == 98", hp, 98.0, log)

        # T=3.5s: hp == 97, effect expired, tag gone.
        time.sleep(1.4)
        hp = _query("/entities/hero_1/components/attribute_set/attributes/hp/current")
        passed &= _assert("T~3.5s: hp.current == 97", hp, 97.0, log)

        ae = _query("/active_effects/active_poison_001")
        passed &= _assert("T~3.5s: active_poison_001 removed from IR", ae, None, log)

        tags_after = _query("/entities/hero_1/components/tag_set/runtime_tags")
        passed &= _assert("T~3.5s: state.poisoned removed from runtime_tags",
                          "state.poisoned" not in (tags_after or []), True, log)

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        _set_initial_path("res://test_data/initial_state.toon")

    summary_path = log_dir / "d2_summary.json"
    summary_path.write_text(json.dumps({"passed": passed, "log": log}, indent=2), encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'} — summary: {summary_path}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(run_e2e())
