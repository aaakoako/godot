#!/usr/bin/env python3
"""
MCP self-check: verify Godot game is running and MCP TCP responds correctly.
Exit codes:
  0 = all checks passed
  1 = no port configured (Godot never started)
  2 = connection refused (editor open but game not playing, or Godot not running)
  3 = ping failed (TCP connected but bad response)
  4 = get_ir_state failed
  5 = get_ir_state returned unexpected data
"""
from __future__ import annotations

import json
import os
import socket
import sys

GODOT_HOST = os.environ.get("GODOT_HOST", "127.0.0.1")
TIMEOUT = 5


def _read_global_mcp_port() -> int | None:
    """Read GODOT_PORT from env or global Cursor mcp.json. Returns None if missing or 0."""
    env_port = os.environ.get("GODOT_PORT", "")
    if env_port.isdigit() and int(env_port) > 0:
        return int(env_port)
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME", "")
    if not home:
        return None
    path = os.path.join(home, ".cursor", "mcp.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        port_str = (data.get("mcpServers") or {}).get("gameclaw", {}).get("env", {}).get("GODOT_PORT", "")
        if port_str and str(port_str).isdigit():
            p = int(port_str)
            return p if p > 0 else None
    except Exception:
        pass
    return None


def _godot_tcp_call(port: int, method: str, params: dict | None = None) -> dict:
    params = params or {}
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}) + "\n"
    with socket.create_connection((GODOT_HOST, port), timeout=TIMEOUT) as sock:
        sock.sendall(payload.encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                return {"_error": "Connection closed before newline"}
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8")
    out = json.loads(line)
    if "error" in out:
        err = out["error"]
        msg = err.get("message", err) if isinstance(err, dict) else str(err)
        return {"_error": msg, "_raw_error": err}
    return out.get("result", out)


def main() -> int:
    port = _read_global_mcp_port()
    if port is None:
        print("FAIL: GODOT_PORT not set and not found in ~/.cursor/mcp.json.", file=sys.stderr)
        print("  Diagnosis: Godot game has never started, or port was cleared.", file=sys.stderr)
        print("  Fix: run `python launch_godot.py --kill`", file=sys.stderr)
        return 1

    # 1. ping
    try:
        r = _godot_tcp_call(port, "ping")
    except ConnectionRefusedError:
        print(f"FAIL: Connection refused on {GODOT_HOST}:{port}.", file=sys.stderr)
        print("  Diagnosis: Godot editor may be open but game is NOT playing.", file=sys.stderr)
        print("  The MCP TCP server only runs inside the game process (autoload).", file=sys.stderr)
        print("  Fix: press F5 in Godot editor, or run `python launch_godot.py --kill`", file=sys.stderr)
        return 2
    except socket.timeout:
        print(f"FAIL: Timeout connecting to {GODOT_HOST}:{port}.", file=sys.stderr)
        print("  Diagnosis: Port exists in config but nothing is listening.", file=sys.stderr)
        print("  Fix: run `python launch_godot.py --kill`", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"FAIL: Network error on {GODOT_HOST}:{port}: {exc}", file=sys.stderr)
        print("  Fix: run `python launch_godot.py --kill`", file=sys.stderr)
        return 2

    if "_error" in r:
        print(f"FAIL: ping returned error: {r['_error']}", file=sys.stderr)
        return 3
    data = r.get("data", r) if isinstance(r, dict) else r
    if isinstance(data, dict) and data.get("pong") is not True:
        print(f"FAIL: ping unexpected response: {r}", file=sys.stderr)
        return 3
    print("ping: OK")

    # 2. get_ir_state
    try:
        r = _godot_tcp_call(port, "get_ir_state")
    except Exception as exc:
        print(f"FAIL: get_ir_state connection error: {exc}", file=sys.stderr)
        return 4

    if "_error" in r:
        print(f"FAIL: get_ir_state error: {r['_error']}", file=sys.stderr)
        if "_raw_error" in r:
            print(f"  raw: {json.dumps(r['_raw_error'], ensure_ascii=False)}", file=sys.stderr)
        return 4
    # JSON-RPC result may be { data: { state, entity_count }, evidence: null }
    data = r.get("data", r) if isinstance(r, dict) else {}
    state = data.get("state") if isinstance(data, dict) else None
    if state is None:
        print(f"FAIL: get_ir_state missing .state: {r}", file=sys.stderr)
        return 5
    entities = state.get("entities", {}) if isinstance(state, dict) else {}
    print(f"get_ir_state: OK (entities: {len(entities)})")

    print("MCP verify: all checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
