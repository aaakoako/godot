"""
Sprint D3 E2E verifier: Fireball ability -> projectile -> hit -> burn effect.
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
D3_INITIAL_IR_PATH = "res://test_data/sprint_d3_fireball_init.toon"

sys.path.insert(0, str(PROJECT))
launch_godot_mod = importlib.import_module("launch_godot")
find_godot_exe = launch_godot_mod.find_godot_exe
kill_existing_godot = launch_godot_mod.kill_existing_godot


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
        if port > 0 and _has_pong(_call("ping", req_id=901)):
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


def _get_state() -> dict[str, object]:
    resp = _call("get_ir_state")
    result = resp.get("result")
    if not isinstance(result, dict):
        return {}
    data = result.get("data")
    if not isinstance(data, dict):
        return {}
    state = data.get("state")
    return state if isinstance(state, dict) else {}


def _assert(label: str, actual: object, expected: object, log: list[str]) -> bool:
    ok = actual == expected
    status = "PASS" if ok else "FAIL"
    msg = f"[{status}] {label}: expected={expected!r}, actual={actual!r}"
    print(msg, flush=True)
    log.append(msg)
    return ok


def run_e2e(log_dir: Path | None = None) -> int:
    if log_dir is None:
        log_dir = PROJECT / "artifacts" / "d3_fireball"
    log_dir = Path(log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)

    log: list[str] = []
    passed = True

    godot_exe = find_godot_exe()
    if not godot_exe:
        print("ERROR: Godot executable not found", flush=True)
        return 1

    kill_existing_godot()
    godot_log_path = log_dir / "d3_godot.log"
    env = os.environ.copy()
    env["GAMECLAW_INITIAL_IR_PATH"] = D3_INITIAL_IR_PATH
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

        print("Sending cast_fireball input action...", flush=True)
        fire_resp = _call("send_input_action", {"action_name": "cast_fireball"})
        fire_result = fire_resp.get("result")
        fire_data = fire_result.get("data") if isinstance(fire_result, dict) else None
        activations = fire_data.get("activations") if isinstance(fire_data, dict) else None
        if not activations:
            print(f"ERROR: send_input_action failed: {fire_resp}", flush=True)
            passed = False

        time.sleep(0.2)
        mana = _query("/entities/hero_1/components/attribute_set/attributes/mana/current")
        passed &= _assert("After cast: hero_1.mana.current == 15", mana, 15.0, log)

        state_after_cast = _get_state()
        entities_obj = state_after_cast.get("entities")
        entities = entities_obj if isinstance(entities_obj, dict) else {}
        proj_ids = []
        for eid, entry in entities.items():
            if isinstance(entry, dict) and entry.get("_projectile_def") == "proj_fireball_basic":
                proj_ids.append(eid)
        passed &= _assert("Projectile entity exists in IR", len(proj_ids) > 0, True, log)

        print("Waiting for projectile to hit enemy_1 (~0.8s)...", flush=True)
        time.sleep(0.8)

        state_after_hit = _get_state()
        entities_after_obj = state_after_hit.get("entities")
        entities_after = entities_after_obj if isinstance(entities_after_obj, dict) else {}
        proj_still_alive = []
        for eid, entry in entities_after.items():
            if isinstance(entry, dict) and entry.get("_projectile_def") == "proj_fireball_basic":
                proj_still_alive.append(eid)
        passed &= _assert("Projectile removed from IR after hit", len(proj_still_alive), 0, log)

        active_effects_obj = state_after_hit.get("active_effects")
        active_effects = active_effects_obj if isinstance(active_effects_obj, dict) else {}
        burn_effects = []
        for k, v in active_effects.items():
            if isinstance(v, dict) and v.get("target_entity") == "enemy_1" and v.get("effect_def") == "burn_on_hit":
                burn_effects.append(k)
        passed &= _assert("enemy_1 has burn_on_hit active_effect", len(burn_effects) > 0, True, log)

        time.sleep(0.2)
        tags = _query("/entities/enemy_1/components/tag_set/runtime_tags")
        tags_list = tags if isinstance(tags, list) else []
        passed &= _assert("enemy_1 has state.burning tag", "state.burning" in tags_list, True, log)

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    summary_path = log_dir / "d3_summary.json"
    summary_path.write_text(json.dumps({"passed": passed, "log": log}, indent=2), encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'} — summary: {summary_path}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(run_e2e())
