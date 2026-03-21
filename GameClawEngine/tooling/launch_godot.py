#!/usr/bin/env python3
"""
Launch Godot editor + auto-play, wait for MCP TCP, then run verify_mcp.py.
Default mode: opens the editor (-e) so LSP is available, then auto-plays via EditorPlugin.
Usage:
  python launch_godot.py          # editor + auto-play + verify
  python launch_godot.py --kill   # kill existing Godot first (recommended)
  python launch_godot.py --no-editor  # run game directly without editor (no LSP)
  python launch_godot.py --headless   # no window (for CI, no LSP)
Exit code 0 = MCP verified OK. Non-zero = something failed.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MCP_READY_PATTERN = re.compile(r"\[MCP TCP\] Listening on .+:(\d+)")
MAX_WAIT_SECONDS = 60
POLL_INTERVAL = 0.5


def _get_global_mcp_json_path() -> str:
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME", "")
    return os.path.join(home, ".cursor", "mcp.json")


def find_godot_exe() -> str | None:
    """Find a Godot executable in the project directory."""
    candidates = sorted(glob.glob(os.path.join(PROJECT_DIR, "Godot_*_console.exe")))
    if candidates:
        return candidates[-1]
    candidates = sorted(glob.glob(os.path.join(PROJECT_DIR, "Godot_*.exe")))
    if candidates:
        return candidates[-1]
    for name in ("godot", "godot.exe"):
        full = os.path.join(PROJECT_DIR, name)
        if os.path.isfile(full):
            return full
    return None


def kill_existing_godot() -> None:
    """Kill all Godot processes related to this project."""
    if sys.platform != "win32":
        return
    try:
        out = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command",
             "Get-CimInstance Win32_Process | Where-Object { $_.Name -like '*Godot*' } | "
             "Select-Object ProcessId, CommandLine | Format-List"],
            text=True, stderr=subprocess.DEVNULL, timeout=10
        )
        project_lower = PROJECT_DIR.replace("\\", "/").lower()
        current_pid = None
        current_cmd = ""
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("ProcessId"):
                val = line.split(":", 1)[1].strip() if ":" in line else ""
                current_pid = int(val) if val.isdigit() else None
            elif line.startswith("CommandLine"):
                current_cmd = line.split(":", 1)[1].strip() if ":" in line else ""
            elif not line and current_pid is not None:
                if project_lower in current_cmd.replace("\\", "/").lower() or "godot" in current_cmd.lower():
                    print(f"  Killing Godot PID {current_pid}")
                    subprocess.run(["taskkill", "/F", "/PID", str(current_pid)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                current_pid = None
                current_cmd = ""
        if current_pid is not None:
            if project_lower in current_cmd.replace("\\", "/").lower() or "godot" in current_cmd.lower():
                print(f"  Killing Godot PID {current_pid}")
                subprocess.run(["taskkill", "/F", "/PID", str(current_pid)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as exc:
        print(f"  Warning: kill_existing_godot failed: {exc}")
        _fallback_kill_by_name()


def _clear_mcp_port() -> None:
    """Reset GODOT_PORT in mcp.json to 0 so we can detect when Godot writes a fresh port."""
    path = _get_global_mcp_json_path()
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        env = data.get("mcpServers", {}).get("gameclaw", {}).get("env", {})
        if env.get("GODOT_PORT"):
            env["GODOT_PORT"] = "0"
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print("  Cleared GODOT_PORT in mcp.json")
    except Exception:
        pass


def _fallback_kill_by_name() -> None:
    """Last resort: kill all processes with 'Godot' in the name via taskkill."""
    try:
        subprocess.run(["taskkill", "/F", "/IM", "Godot_v4*"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


class GodotOutputReader:
    """Background thread that reads Godot stdout, prints it, and watches for MCP port."""

    def __init__(self, proc: subprocess.Popen):
        self._proc = proc
        self._port: int | None = None
        self._port_event = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self) -> None:
        assert self._proc.stdout is not None
        for raw_line in self._proc.stdout:
            text = raw_line.strip()
            if text:
                print(f"  [Godot] {text}")
            m = MCP_READY_PATTERN.search(text)
            if m and self._port is None:
                self._port = int(m.group(1))
                self._port_event.set()

    def wait_for_port(self, timeout: float) -> int | None:
        self._port_event.wait(timeout=timeout)
        return self._port


def _read_port_from_mcp_json() -> int | None:
    """Read GODOT_PORT from global mcp.json (written by Godot game process on startup).
    Returns None if port is 0 or missing (0 means cleared by kill)."""
    path = _get_global_mcp_json_path()
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        port_str = data.get("mcpServers", {}).get("gameclaw", {}).get("env", {}).get("GODOT_PORT")
        if port_str:
            port = int(port_str)
            return port if port > 0 else None
    except Exception:
        pass
    return None


def wait_for_mcp_port(reader: GodotOutputReader, proc: subprocess.Popen, use_editor: bool) -> int | None:
    """Wait for MCP port via stdout (non-editor) or mcp.json polling (editor mode).
    In editor mode, the game is a child process whose stdout may not reach our pipe,
    so we also poll mcp.json for the port written by the game's TCP server."""
    if not use_editor:
        return reader.wait_for_port(MAX_WAIT_SECONDS)

    deadline = time.time() + MAX_WAIT_SECONDS
    print("  Editor mode: polling mcp.json for new port (cleared to 0 by --kill)...")

    while time.time() < deadline:
        if proc.poll() is not None:
            print(f"  Godot editor exited (code {proc.returncode}).", file=sys.stderr)
            return None

        port_from_stdout = reader._port
        if port_from_stdout is not None:
            print(f"  Detected port {port_from_stdout} from stdout")
            return port_from_stdout

        new_port = _read_port_from_mcp_json()
        if new_port is not None and new_port > 0:
            if tcp_ping("127.0.0.1", new_port, timeout=1):
                print(f"  Detected port {new_port} from mcp.json (ping OK)")
                return new_port

        time.sleep(POLL_INTERVAL)

    return reader._port


def tcp_ping(host: str, port: int, timeout: float = 3) -> bool:
    """Quick TCP connect test: send ping, accept both legacy/new pong envelopes."""
    try:
        with socket.create_connection((host, port), timeout=timeout) as s:
            s.settimeout(timeout)
            payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping", "params": {}}) + "\n"
            s.sendall(payload.encode())
            buf = b""
            while b"\n" not in buf:
                chunk = s.recv(4096)
                if not chunk:
                    return False
                buf += chunk
            resp = json.loads(buf.split(b"\n")[0].decode())
            result = resp.get("result", {})
            if not isinstance(result, dict):
                return False
            # Compatibility: some handlers return {"result":{"pong":true}},
            # newer handlers wrap payload as {"result":{"data":{"pong":true}}}.
            if result.get("pong") is True:
                return True
            data = result.get("data", {})
            return isinstance(data, dict) and data.get("pong") is True
    except Exception:
        return False


def run_verify(port: int) -> int:
    """Run verify_mcp.py with the discovered port."""
    env = os.environ.copy()
    env["GODOT_PORT"] = str(port)
    env["GODOT_HOST"] = "127.0.0.1"
    result = subprocess.run(
        [sys.executable, os.path.join(PROJECT_DIR, "verify_mcp.py")],
        cwd=PROJECT_DIR, env=env
    )
    return result.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Launch Godot editor + auto-play + verify MCP")
    parser.add_argument("--godot", help="Path to Godot executable")
    parser.add_argument("--no-editor", action="store_true", help="Run game directly (no editor, no LSP)")
    parser.add_argument("--headless", action="store_true", help="Run Godot headless (no window, no LSP, for CI)")
    parser.add_argument("--kill", action="store_true", help="Kill existing Godot processes for this project first")
    parser.add_argument("--no-verify", action="store_true", help="Only launch, skip verify_mcp.py")
    args = parser.parse_args()

    godot = args.godot or find_godot_exe()
    if not godot or not os.path.isfile(godot):
        print(f"Godot executable not found. Place Godot_*.exe in {PROJECT_DIR} or pass --godot.", file=sys.stderr)
        return 1

    if args.kill:
        print("Killing existing Godot processes...")
        kill_existing_godot()
        _clear_mcp_port()
        time.sleep(2)

    use_editor = not args.no_editor and not args.headless
    cmd = [godot, "--path", PROJECT_DIR]
    if args.headless:
        cmd.append("--headless")
        cmd.append("main.tscn")
    elif use_editor:
        cmd.append("-e")
        cmd.extend(["--", "--autoplay"])

    print(f"Launching: {' '.join(cmd)}")
    if use_editor:
        print("  Mode: EDITOR (LSP active) + auto-play via EditorPlugin")
    else:
        print("  Mode: GAME ONLY (no LSP)")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        cwd=PROJECT_DIR,
    )

    reader = GodotOutputReader(proc)
    print(f"Waiting up to {MAX_WAIT_SECONDS}s for MCP TCP to be ready...")
    port = wait_for_mcp_port(reader, proc, use_editor)
    if port is None:
        print("Timed out waiting for MCP TCP. Godot may have crashed or MCP is disabled.", file=sys.stderr)
        proc.terminate()
        return 2

    print(f"MCP TCP ready on port {port}. Verifying connectivity...")
    time.sleep(2)
    ping_ok = False
    for attempt in range(10):
        if proc.poll() is not None:
            print(f"  Godot exited (code {proc.returncode}) before ping succeeded.", file=sys.stderr)
            break
        if tcp_ping("127.0.0.1", port):
            ping_ok = True
            break
        print(f"  ping attempt {attempt + 1}/10 failed, retrying...")
        time.sleep(1)
    if not ping_ok:
        print("TCP ping failed after MCP reported ready.", file=sys.stderr)
        if proc.poll() is None:
            proc.terminate()
        return 3

    if args.no_verify:
        print(f"Godot running (PID {proc.pid}), MCP on port {port}. --no-verify: skipping verify_mcp.py.")
        print(f"To verify manually: GODOT_PORT={port} python verify_mcp.py")
        return 0

    print("Running verify_mcp.py...")
    rc = run_verify(port)
    if rc == 0:
        print(f"\nAll checks passed. Godot running (PID {proc.pid}), MCP on port {port}.")
        print("Godot will keep running. Press Ctrl+C or kill the process to stop.")
    else:
        print(f"\nverify_mcp.py failed with exit code {rc}.", file=sys.stderr)

    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)
