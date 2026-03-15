"""
Sprint D3 E2E verifier: Fireball ability → projectile → hit → burn effect.

Flow:
  Start Godot with sprint_d3_fireball_init.toon
  → send_input_action(cast_fireball)
  → hero_1.mana decreases by 5  (20 → 15)
  → IR contains a projectile entity (proj_fireball_basic_1)
  → Wait for projectile to travel and hit enemy_1 (~200px / 400 speed = 0.5s)
  → projectile removed from IR
  → enemy_1 has active_effect referencing burn_on_hit
  → enemy_1.runtime_tags contains state.burning

Public API (for regression_runner.py --sprint d3):
    run_e2e(log_dir: Path | None = None) -> int

CLI:
    python orchestrator/verify_d3_fireball_e2e.py
"""
from __future__ import annotations

import json
import os
import re
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
    if "error" in resp:
        return None
    data = resp.get("result", resp).get("data", resp.get("result", {}))
    return data.get("value", None)


def _get_state() -> dict:
    resp = _call("get_ir_state")
    if "error" in resp:
        return {}
    data = resp.get("result", resp).get("data", resp.get("result", {}))
    return data.get("state", {})


def _assert(label: str, actual: object, expected: object, log: list[str]) -> bool:
    ok = actual == expected
    status = "PASS" if ok else "FAIL"
    msg = f"[{status}] {label}: expected={expected!r}, actual={actual!r}"
    print(msg, flush=True)
    log.append(msg)
    return ok


def _set_initial_path(path: str) -> None:
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    text = re.sub(
        r'config/initial_ir_path="[^"]*"',
        f'config/initial_ir_path="{path}"',
        text,
    )
    PROJECT_GODOT.write_text(text, encoding="utf-8")


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

    _set_initial_path("res://test_data/sprint_d3_fireball_init.toon")
    kill_existing_godot()

    godot_log_path = log_dir / "d3_godot.log"
    proc = subprocess.Popen(
        [godot_exe, "--path", str(PROJECT), "--headless"],
        stdout=open(godot_log_path, "w"),
        stderr=subprocess.STDOUT,
    )

    try:
        print("Waiting for Godot MCP...", flush=True)
        for _ in range(30):
            time.sleep(0.5)
            resp = _call("ping")
            if resp.get("result", {}).get("pong") or resp.get("result") == "pong":
                break
        else:
            print("ERROR: Godot did not respond to ping", flush=True)
            return 1

        # Trigger fireball.
        print("Sending cast_fireball input action...", flush=True)
        fire_resp = _call("send_input_action", {"action_name": "cast_fireball"})
        fire_ok = fire_resp.get("result", {}).get("data", {}).get("activations")
        if not fire_ok:
            print(f"ERROR: send_input_action failed: {fire_resp}", flush=True)
            passed = False

        time.sleep(0.2)

        # Mana should be 15.
        mana = _query("/entities/hero_1/components/attribute_set/attributes/mana/current")
        passed &= _assert("After cast: hero_1.mana.current == 15", mana, 15.0, log)

        # A projectile entity should exist.
        state_after_cast = _get_state()
        entities = state_after_cast.get("entities", {})
        proj_ids = [eid for eid in entities if entities[eid].get("_projectile_def") == "proj_fireball_basic"]
        passed &= _assert("Projectile entity exists in IR", len(proj_ids) > 0, True, log)

        # Wait for projectile to hit enemy_1 (~0.5s travel + buffer).
        print("Waiting for projectile to hit enemy_1 (~0.8s)...", flush=True)
        time.sleep(0.8)

        # Projectile should be gone.
        state_after_hit = _get_state()
        entities_after = state_after_hit.get("entities", {})
        proj_still_alive = [eid for eid in entities_after if entities_after[eid].get("_projectile_def") == "proj_fireball_basic"]
        passed &= _assert("Projectile removed from IR after hit", len(proj_still_alive), 0, log)

        # enemy_1 should have a burn active_effect.
        active_effects = state_after_hit.get("active_effects", {})
        burn_effects = [k for k, v in active_effects.items() if isinstance(v, dict) and v.get("target_entity") == "enemy_1" and v.get("effect_def") == "burn_on_hit"]
        passed &= _assert("enemy_1 has burn_on_hit active_effect", len(burn_effects) > 0, True, log)

        # enemy_1 runtime_tags should contain state.burning (EffectSystem grants it within 50ms).
        time.sleep(0.2)
        tags = _query("/entities/enemy_1/components/tag_set/runtime_tags")
        passed &= _assert("enemy_1 has state.burning tag", "state.burning" in (tags or []), True, log)

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        _set_initial_path("res://test_data/initial_state.toon")

    summary_path = log_dir / "d3_summary.json"
    summary_path.write_text(json.dumps({"passed": passed, "log": log}, indent=2), encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'} — summary: {summary_path}", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(run_e2e())
