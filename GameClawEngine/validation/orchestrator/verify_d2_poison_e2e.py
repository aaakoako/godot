"""
Sprint D2 E2E verifier: Poison Buff lifecycle test.
"""
from __future__ import annotations

import importlib
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT
D2_INITIAL_IR_PATH = "res://test_data/sprint_d2_poison_init.toon"

sys.path.insert(0, str(PROJECT))
launch_godot_mod = importlib.import_module("launch_godot")
find_godot_exe = launch_godot_mod.find_godot_exe
kill_existing_godot = launch_godot_mod.kill_existing_godot

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


def _call(method: str, params: dict[str, object] | None = None, req_id: int = 1) -> dict[str, object]:
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


def _has_pong(resp: dict[str, object]) -> bool:
    result = resp.get("result")
    if not isinstance(result, dict):
        return False
    data = result.get("data")
    if isinstance(data, dict) and data.get("pong") is True:
        return True
    return result.get("pong") is True or result == "pong"


def _wait_port(timeout_sec: float = 20.0) -> bool:
    t0 = time.time()
    while time.time() - t0 < timeout_sec:
        _, port = _load_mcp()
        if port > 0 and _has_pong(_call("ping", req_id=900)):
            return True
        time.sleep(0.3)
    return False


def _query(path: str) -> object:
    resp = _call("query_ir_path", {"path": path})
    result = resp.get("result")
    if not isinstance(result, dict):
        return None
    data = result.get("data")
    if not isinstance(data, dict):
        return None
    return data.get("value", None)


def _assert(label: str, actual: object, expected: object, log: list[str]) -> bool:
    ok = actual == expected
    status = "PASS" if ok else "FAIL"
    msg = f"[{status}] {label}: expected={expected!r}, actual={actual!r}"
    print(msg, flush=True)
    log.append(msg)
    return ok


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

    kill_existing_godot()
    godot_log_path = log_dir / "d2_godot.log"
    env = os.environ.copy()
    env["GAMECLAW_INITIAL_IR_PATH"] = D2_INITIAL_IR_PATH
    with godot_log_path.open("w", encoding="utf-8") as gf:
        proc = subprocess.Popen(
            [godot_exe, "--path", str(PROJECT), "--headless", "main.tscn"],
            env=env,
            stdout=gf,
            stderr=subprocess.STDOUT,
        )

    try:
        print("Waiting for Godot MCP...", flush=True)
        if not _wait_port(25.0):
            print("ERROR: Godot did not respond to ping", flush=True)
            return 1

        print("Injecting active_poison_001...", flush=True)
        inject_resp = _call("apply_patch", {"patch": INJECT_PATCH})
        inject_result = inject_resp.get("result")
        inject_data = inject_result.get("data") if isinstance(inject_result, dict) else None
        if not isinstance(inject_data, dict) or inject_data.get("applied") is not True:
            print(f"ERROR: inject failed: {inject_resp}", flush=True)
            return 1

        time.sleep(0.25)
        tags = _query("/entities/hero_1/components/tag_set/runtime_tags")
        tags_list = tags if isinstance(tags, list) else []
        passed &= _assert("T~0.25s: state.poisoned in runtime_tags", "state.poisoned" in tags_list, True, log)

        time.sleep(1.1)
        hp = _query("/entities/hero_1/components/attribute_set/attributes/hp/current")
        passed &= _assert("T~1.1s: hp.current == 99", hp, 99.0, log)

        time.sleep(1.0)
        hp = _query("/entities/hero_1/components/attribute_set/attributes/hp/current")
        passed &= _assert("T~2.1s: hp.current == 98", hp, 98.0, log)

        time.sleep(1.4)
        hp = _query("/entities/hero_1/components/attribute_set/attributes/hp/current")
        passed &= _assert("T~3.5s: hp.current == 97", hp, 97.0, log)

        ae = _query("/active_effects/active_poison_001")
        passed &= _assert("T~3.5s: active_poison_001 removed from IR", ae, None, log)

        tags_after = _query("/entities/hero_1/components/tag_set/runtime_tags")
        tags_after_list = tags_after if isinstance(tags_after, list) else []
        passed &= _assert("T~3.5s: state.poisoned removed from runtime_tags", "state.poisoned" not in tags_after_list, True, log)

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    summary_path = log_dir / "d2_summary.json"
    summary_path.write_text(json.dumps({"passed": passed, "log": log}, indent=2), encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'} — summary: {summary_path}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(run_e2e())
