"""
Sprint C.1 end-to-end verifier via real MCP UI clicks.
Flow: start Godot with C1 init -> start mock orchestrator -> ui_click btn_attack x4
      -> verify final IR + event log + illegal patch DoD5.

Public API (for regression_runner.py):
    run_e2e(log_dir: Path | None = None) -> int
        Returns 0 on pass, non-zero on failure.
        log_dir defaults to PROJECT / "artifacts".

CLI:
    python verify_c1_ui_e2e.py
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
ORCH = PROJECT / "validation" / "orchestrator" / "mock_orchestrator.py"
C1_INITIAL_IR_PATH = "res://test_data/sprint_c1_init.toon"

launch_godot_mod = importlib.import_module("launch_godot")
find_godot_exe = launch_godot_mod.find_godot_exe
kill_existing_godot = launch_godot_mod.kill_existing_godot


def _find_godot() -> Path:
    exe = find_godot_exe()
    if exe is None:
        raise RuntimeError(
            f"No Godot executable found in {PROJECT}. "
            "Place Godot_*_console.exe there or set GODOT_EXE env var."
        )
    return Path(exe)


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
    with socket.create_connection((host, port), timeout=6) as s:
        s.sendall((json.dumps(req) + "\n").encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    line = buf.split(b"\n", 1)[0].decode("utf-8")
    return json.loads(line)


def _wait_port(timeout_sec: float = 20.0) -> None:
    t0 = time.time()
    while time.time() - t0 < timeout_sec:
        _, port = _load_mcp()
        if port > 0:
            try:
                ping = _call("ping", req_id=900)
                result = ping.get("result")
                if isinstance(result, dict):
                    data = result.get("data")
                    if isinstance(data, dict) and data.get("pong") is True:
                        return
            except Exception:
                pass
        time.sleep(0.3)
    raise RuntimeError("MCP port not ready")


def _kill_godot() -> None:
    kill_existing_godot()


def _result_value(resp: dict[str, object]) -> object:
    result = resp.get("result")
    if not isinstance(result, dict):
        return None
    data = result.get("data")
    if not isinstance(data, dict):
        return None
    return data.get("value")


def run_e2e(log_dir: Path | None = None) -> int:
    """
    Execute the C.1 Golden Case end-to-end test.

    Args:
        log_dir: Directory for log files. Defaults to PROJECT/artifacts.

    Returns:
        0 on pass, 1 on unexpected error, 2 on assertion failure.
    """
    if log_dir is None:
        log_dir = PROJECT / "artifacts"
    log_dir.mkdir(parents=True, exist_ok=True)

    godot_log = log_dir / "e2e_godot.log"
    orch_log = log_dir / "e2e_orchestrator.log"

    _kill_godot()

    with godot_log.open("w", encoding="utf-8") as gf:
        godot_exe = _find_godot()
        env = os.environ.copy()
        env["GAMECLAW_INITIAL_IR_PATH"] = C1_INITIAL_IR_PATH
        godot_proc = subprocess.Popen(
            [str(godot_exe), "--path", ".", "--headless", "main.tscn"],
            cwd=PROJECT,
            env=env,
            stdout=gf,
            stderr=subprocess.STDOUT,
        )
    try:
        _wait_port()

        with orch_log.open("w", encoding="utf-8") as of:
            orch_proc = subprocess.Popen(
                [sys.executable, str(ORCH)],
                cwd=PROJECT,
                stdout=of,
                stderr=subprocess.STDOUT,
            )

        try:
            time.sleep(1.0)
            r1 = _call("ui_click", {"entity_id": "btn_attack", "count": 4, "interval_ms": 120}, req_id=1001)
            if "error" in r1:
                print(json.dumps({"step": "ui_click", "resp": r1}, ensure_ascii=False))
                return 1

            time.sleep(2.5)
            state = _call("get_ir_state", req_id=1002)
            msg = _call("query_ir_path", {"path": "/entities/lbl_message/text"}, req_id=1003)
            hp = _call("query_ir_path", {"path": "/entities/enemy/hp"}, req_id=1004)
            alive = _call("query_ir_path", {"path": "/entities/enemy/alive"}, req_id=1005)
            ev = _call("get_event_log", {"since_seq": 0, "limit": 20}, req_id=1006)

            illegal = subprocess.run(
                [sys.executable, str(ORCH), "--test-illegal"],
                cwd=PROJECT,
                capture_output=True,
                text=True,
            )

            out = {
                "ui_click": r1,
                "state": state,
                "msg": msg,
                "hp": hp,
                "alive": alive,
                "events": ev,
                "illegal_stdout": illegal.stdout.strip(),
                "illegal_rc": illegal.returncode,
            }
            print(json.dumps(out, ensure_ascii=False, indent=2))

            ok = (
                _result_value(msg) == "It's already dead!"
                and _result_value(hp) in [0, 0.0]
                and _result_value(alive) is False
                and illegal.returncode == 0
            )
            return 0 if ok else 2
        finally:
            orch_proc.terminate()
            try:
                orch_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                orch_proc.kill()
    finally:
        godot_proc.terminate()
        try:
            godot_proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            godot_proc.kill()


def main() -> int:
    """CLI entry point."""
    return run_e2e()


if __name__ == "__main__":
    raise SystemExit(main())
