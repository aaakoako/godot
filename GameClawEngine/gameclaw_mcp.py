"""
GameClawEngine MCP server: single-file bridge from Cursor/Claude (stdio) to Godot (TCP).
Run: python gameclaw_mcp.py
Requires: pip install fastmcp
Env: GODOT_HOST (default 127.0.0.1), GODOT_PORT (set by Godot on F5 or manual).
"""
from __future__ import annotations

import json
import os
import socket
import sys
import threading

try:
    from fastmcp import FastMCP
    from fastmcp.utilities.types import Image
except ImportError:
    raise SystemExit("Install with: pip install fastmcp")

mcp = FastMCP("gameclaw")

GODOT_HOST = os.environ.get("GODOT_HOST", "127.0.0.1")
TIMEOUT = 10

# Persistent connection to Godot TCP (reused across _godot_call invocations).
_godot_lock = threading.Lock()
_connection: socket.socket | None = None
_connection_port: int = 0

_NOT_CONNECTED_NEXT_STEPS = [
    "Godot game is not running or MCP TCP server is not listening.",
    "Possible states: (a) Godot editor open but game not playing, (b) Godot not launched at all, (c) game crashed.",
    "Fix: run `python launch_godot.py --kill` from GameClawEngine/ to start editor + auto-play.",
    "Or: open Godot editor and press F5 to play the main scene manually.",
]


def _resolve_port() -> int:
    """Get the current Godot TCP port. Checks env first, then reads mcp.json live."""
    env_port = os.environ.get("GODOT_PORT", "")
    if env_port.isdigit() and int(env_port) > 0:
        return int(env_port)
    return _read_port_from_mcp_json() or 0


def _read_port_from_mcp_json() -> int | None:
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME", "")
    if not home:
        return None
    path = os.path.join(home, ".cursor", "mcp.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        port_str = data.get("mcpServers", {}).get("gameclaw", {}).get("env", {}).get("GODOT_PORT", "")
        if port_str and str(port_str).isdigit():
            p = int(port_str)
            return p if p > 0 else None
    except Exception:
        pass
    return None


def _close_connection() -> None:
    """Close the persistent Godot TCP connection so the next call will reconnect."""
    global _connection, _connection_port
    if _connection is not None:
        try:
            _connection.close()
        except OSError:
            pass
        _connection = None
    _connection_port = 0


def _get_connection(port: int) -> socket.socket | None:
    """Return a connected socket to Godot; reuses existing if same port, else creates new. Returns None on failure."""
    global _connection, _connection_port
    if _connection is not None:
        if _connection_port != port:
            _close_connection()
        else:
            return _connection
    try:
        sock = socket.create_connection((GODOT_HOST, port), timeout=TIMEOUT)
        sock.settimeout(TIMEOUT)
        _connection = sock
        _connection_port = port
        return sock
    except (ConnectionRefusedError, socket.timeout, OSError):
        return None


def _godot_call(method: str, params: dict | None = None) -> dict:
    """Send JSON-RPC request to Godot TCP server; return parsed response. Reuses one persistent connection."""
    port = _resolve_port()
    if port <= 0:
        return {
            "success": False,
            "error": {
                "code": -32000,
                "message": "GODOT_PORT is 0 or not set. Godot game has not started yet.",
                "data": {"next_steps": _NOT_CONNECTED_NEXT_STEPS},
            },
        }

    params = params or {}
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}) + "\n"
    line = ""
    with _godot_lock:
        for attempt in range(2):
            sock = _get_connection(port)
            if sock is None:
                return {
                    "success": False,
                    "error": {
                        "code": -32000,
                        "message": f"Connection refused on {GODOT_HOST}:{port}. "
                                   "Godot game is not running (editor may be open without playing).",
                        "data": {"port": port, "next_steps": _NOT_CONNECTED_NEXT_STEPS},
                    },
                }
            try:
                sock.sendall(payload.encode("utf-8"))
                buf = b""
                while b"\n" not in buf:
                    chunk = sock.recv(65536)
                    if not chunk:
                        _close_connection()
                        if attempt == 0:
                            continue
                        return {
                            "success": False,
                            "error": {
                                "code": -32000,
                                "message": f"Godot closed the connection on port {port} before responding.",
                                "data": {"port": port, "next_steps": _NOT_CONNECTED_NEXT_STEPS},
                            },
                        }
                    buf += chunk
                line = buf.split(b"\n", 1)[0].decode("utf-8")
                out = json.loads(line)
                if "error" in out:
                    return {"success": False, "error": out["error"]}
                return out.get("result", out)
            except (ConnectionResetError, BrokenPipeError, OSError, socket.timeout) as exc:
                _close_connection()
                if attempt == 1:
                    return {
                        "success": False,
                        "error": {
                            "code": -32000,
                            "message": f"Network error connecting to Godot on {GODOT_HOST}:{port}: {exc}",
                            "data": {"port": port, "next_steps": _NOT_CONNECTED_NEXT_STEPS},
                        },
                    }
            except json.JSONDecodeError as exc:
                _close_connection()
                if attempt == 1:
                    return {
                        "success": False,
                        "error": {
                            "code": -32000,
                            "message": f"Godot returned invalid JSON: {exc}",
                            "data": {"port": port, "raw": line[:500] if line else ""},
                        },
                    }
    return {"success": False, "error": {"code": -32603, "message": "Unexpected state in _godot_call"}}


def _result_text(resp: dict) -> str:
    """Extract text representation from Godot response for MCP text content."""
    if resp.get("success") is False:
        return json.dumps(resp, ensure_ascii=False)
    return json.dumps(resp.get("data", resp), ensure_ascii=False, indent=2)


# --- Diagnostic tools ---


@mcp.tool
def godot_status() -> str:
    """Check if Godot game is running and MCP TCP is reachable. Always call this first if unsure."""
    port = _resolve_port()
    if port <= 0:
        return json.dumps({
            "status": "no_port",
            "message": "GODOT_PORT is 0 or not configured. Godot game has never started or port was cleared.",
            "next_steps": _NOT_CONNECTED_NEXT_STEPS,
        }, ensure_ascii=False, indent=2)

    resp = _godot_call("ping")
    if resp.get("success") is False:
        err = resp.get("error", {})
        msg = err.get("message", str(err))
        if "refused" in msg.lower() or "Connection refused" in msg:
            return json.dumps({
                "status": "refused",
                "port": port,
                "message": f"Port {port} exists in config but connection refused. "
                           "Editor may be open without game playing, or game crashed.",
                "next_steps": [
                    "Run `python launch_godot.py --kill` to restart editor + auto-play.",
                    "Or press F5 in the Godot editor to play the main scene.",
                ],
            }, ensure_ascii=False, indent=2)
        return json.dumps({
            "status": "unreachable",
            "port": port,
            "message": msg,
            "next_steps": _NOT_CONNECTED_NEXT_STEPS,
        }, ensure_ascii=False, indent=2)

    data = resp if isinstance(resp, dict) else {}
    if data.get("data", {}).get("pong") is True:
        return json.dumps({
            "status": "connected",
            "port": port,
            "message": "Godot game is running and MCP TCP is responding.",
        }, ensure_ascii=False, indent=2)
    return json.dumps({
        "status": "unknown",
        "port": port,
        "message": "Connected but got unexpected response from Godot.",
    }, ensure_ascii=False, indent=2)


# --- IR tools ---


@mcp.tool
def get_ir_state() -> str:
    """Get the current Game IR state. Layer: ir_state. Use to inspect entity data or verify patch results."""
    return _result_text(_godot_call("get_ir_state"))


@mcp.tool
def apply_patch(patch: str) -> str:
    """Apply a TOON or JSON encoded patch string to the current IR. Layer: patch_transaction."""
    return _result_text(_godot_call("apply_patch", {"patch": patch}))


@mcp.tool
def query_ir_path(path: str) -> str:
    """Resolve a path in the IR tree (e.g. /entities/box_1/material/color). Layer: ir_state."""
    return _result_text(_godot_call("query_ir_path", {"path": path}))


@mcp.tool
def get_patch_history() -> str:
    """Return the ordered list of applied patches. Layer: patch_transaction."""
    return _result_text(_godot_call("get_patch_history"))


@mcp.tool
def validate_ir(data: dict) -> str:
    """Run schema validation on IR data without applying. Layer: ir_input."""
    return _result_text(_godot_call("validate_ir", {"data": data}))


@mcp.tool
def rollback_last() -> str:
    """Rollback to the state before the last applied patch. Layer: patch_transaction."""
    return _result_text(_godot_call("rollback_last"))


# --- Scene (projection) tools ---


@mcp.tool
def inspect_scene_tree(root_path: str | None = None, max_depth: int | None = None) -> str:
    """Return Godot scene tree structure. Layer: projection. Optional: root_path, max_depth (default 10)."""
    params = {}
    if root_path is not None:
        params["root_path"] = root_path
    if max_depth is not None:
        params["max_depth"] = max_depth
    return _result_text(_godot_call("inspect_scene_tree", params))


@mcp.tool
def get_entity_node_props(entity_id: str) -> str:
    """Read Godot node properties for a projected entity (position, material, mesh). Layer: projection."""
    return _result_text(_godot_call("get_entity_node_props", {"entity_id": entity_id}))


# --- Perception tools ---


def _screenshot_result(resp: dict):
    """Return FastMCP Image when PNG base64 payload is present; else text."""
    payload: dict | None = None
    if isinstance(resp, dict):
        if isinstance(resp.get("data"), dict):
            payload = resp.get("data")
        elif resp.get("success") and isinstance(resp.get("data"), str):
            payload = {"data": resp.get("data"), "format": "png", "encoding": "base64"}
        elif isinstance(resp.get("data"), str):
            payload = {"data": resp.get("data")}
        elif isinstance(resp.get("format"), str) and isinstance(resp.get("data"), str):
            payload = resp

    if isinstance(payload, dict):
        data_b64 = payload.get("data")
        fmt = str(payload.get("format", "png")).lower()
        encoding = str(payload.get("encoding", "base64")).lower()
        if isinstance(data_b64, str) and encoding == "base64":
            import base64
            try:
                raw = base64.b64decode(data_b64)
                return Image(data=raw, format=fmt)
            except Exception:
                pass

    return _result_text(resp)


@mcp.tool
def capture_screenshot() -> str | Image:
    """Capture the current viewport as PNG. Layer: render_output."""
    resp = _godot_call("capture_screenshot")
    return _screenshot_result(resp)


@mcp.tool
def capture_viewport(width: int | None = None, height: int | None = None) -> str | Image:
    """Capture viewport at resolution (default 640x360). Layer: render_output."""
    params = {}
    if width is not None:
        params["width"] = width
    if height is not None:
        params["height"] = height
    resp = _godot_call("capture_viewport", params)
    return _screenshot_result(resp)


@mcp.tool
def read_godot_log(lines: int | None = None, filter_text: str | None = None) -> str:
    """Read recent Godot engine log lines. Optional: lines (default 200), filter_text (case-insensitive)."""
    params = {}
    if lines is not None:
        params["lines"] = lines
    if filter_text is not None:
        params["filter"] = filter_text
    return _result_text(_godot_call("read_godot_log", params))


# --- Debug / probe / eval tools ---


@mcp.tool
def eval_gdscript(code: str, mode: str | None = None) -> str:
    """Execute restricted GDScript at runtime. Layer: eval. mode: 'expression' or 'statements'."""
    params = {"code": code}
    if mode is not None:
        params["mode"] = mode
    return _result_text(_godot_call("eval_gdscript", params))


@mcp.tool
def start_frame_probe(target: str, fields: list[str], max_frames: int | None = None) -> str:
    """Attach per-frame observer to a node. Layer: probe. fields e.g. ['position','visible']."""
    params = {"target": target, "fields": fields}
    if max_frames is not None:
        params["max_frames"] = max_frames
    return _result_text(_godot_call("start_frame_probe", params))


@mcp.tool
def read_probe_log() -> str:
    """Retrieve NDJSON log from the active frame probe. Layer: probe."""
    return _result_text(_godot_call("read_probe_log"))


@mcp.tool
def stop_frame_probe() -> str:
    """Stop the active frame probe and return its final log. Layer: probe."""
    return _result_text(_godot_call("stop_frame_probe"))


# --- Engine lifecycle tools ---


@mcp.tool
def launch_godot(kill_existing: bool = True) -> str:
    """Launch Godot editor + auto-play if not already running. Use when godot_status shows 'refused' or 'no_port'.
    Set kill_existing=True (default) to kill stale Godot processes first."""
    import subprocess
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "launch_godot.py")
    if not os.path.isfile(script):
        return json.dumps({"success": False, "error": "launch_godot.py not found"}, ensure_ascii=False)

    cmd = [sys.executable, script]
    if kill_existing:
        cmd.append("--kill")

    try:
        result = subprocess.run(
            cmd,
            cwd=os.path.dirname(script),
            capture_output=True,
            text=True,
            timeout=90,
        )
        return json.dumps({
            "success": result.returncode == 0,
            "exit_code": result.returncode,
            "stdout": result.stdout[-2000:] if result.stdout else "",
            "stderr": result.stderr[-1000:] if result.stderr else "",
        }, ensure_ascii=False, indent=2)
    except subprocess.TimeoutExpired:
        return json.dumps({
            "success": False,
            "error": "launch_godot.py timed out after 90s",
        }, ensure_ascii=False)
    except Exception as exc:
        return json.dumps({
            "success": False,
            "error": f"Failed to run launch_godot.py: {exc}",
        }, ensure_ascii=False)


if __name__ == "__main__":
    mcp.run()
