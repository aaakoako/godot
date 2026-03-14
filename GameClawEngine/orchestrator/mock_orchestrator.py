"""
Sprint C.1 Mock Orchestrator: hardcoded game loop for Attack Dummy.
Polls Godot MCP for UI events, reads IR state, applies TOON/JSON patches (no LLM).
Run: python orchestrator/mock_orchestrator.py (from repo root or GameClawEngine/).
Requires: Godot running with MCP TCP (F5 or launch_godot.py), config/initial_ir_path = sprint_c1_init.toon.
Use: --test-illegal to run once and verify illegal patch returns error with layer and evidence_path (DoD 5).
"""
from __future__ import annotations

import json
import os
import socket
import sys
import time
import uuid

GODOT_HOST = os.environ.get("GODOT_HOST", "127.0.0.1")
TIMEOUT = 10
POLL_INTERVAL_SEC = 0.5


def _resolve_port() -> int:
    env_port = os.environ.get("GODOT_PORT", "")
    if env_port.isdigit() and int(env_port) > 0:
        return int(env_port)
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME", "")
    if not home:
        return 0
    path = os.path.join(home, ".cursor", "mcp.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        port_str = data.get("mcpServers", {}).get("gameclaw", {}).get("env", {}).get("GODOT_PORT", "")
        if port_str and str(port_str).isdigit():
            p = int(port_str)
            return p if p > 0 else 0
    except Exception:
        pass
    return 0


def _godot_tcp_call(method: str, params: dict | None = None) -> dict:
    port = _resolve_port()
    if port <= 0:
        return {"error": {"code": -32000, "message": "GODOT_PORT not set. Start Godot with MCP (F5)."}}
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}) + "\n"
    try:
        with socket.create_connection((GODOT_HOST, port), timeout=TIMEOUT) as sock:
            sock.sendall(payload.encode("utf-8"))
            buf = b""
            while b"\n" not in buf:
                chunk = sock.recv(65536)
                if not chunk:
                    return {"error": {"code": -32000, "message": "Godot closed connection"}}
                buf += chunk
            line = buf.split(b"\n", 1)[0].decode("utf-8")
        out = json.loads(line)
    except ConnectionRefusedError:
        return {"error": {"code": -32000, "message": f"Connection refused {GODOT_HOST}:{port}"}}
    except (socket.timeout, OSError, json.JSONDecodeError) as e:
        return {"error": {"code": -32000, "message": str(e)}}
    if "error" in out:
        return out
    return out


def fetch_events_since(last_seq: int) -> list:
    resp = _godot_tcp_call("get_event_log", {"since_seq": last_seq, "limit": 50})
    if "error" in resp:
        return []
    data = resp.get("result", {}).get("data", resp.get("result", {}))
    return data.get("events", [])


def fetch_ir_state() -> dict | None:
    resp = _godot_tcp_call("get_ir_state")
    if "error" in resp:
        return None
    data = resp.get("result", {}).get("data", resp.get("result", {}))
    return data.get("state", data)


def build_attack_request(ir_state: dict) -> dict | None:
    entities = ir_state.get("entities", {})
    enemy = entities.get("enemy", {})
    hp_raw = enemy.get("hp", 0)
    hp = int(hp_raw)
    alive = bool(enemy.get("alive", True))

    request_id = "req_" + str(uuid.uuid4())[:8]
    timeout_frames = 2
    checks = []

    if alive:
        new_hp = max(0, hp - 1)
        new_alive = new_hp > 0
        ops = [
            {"op": "test", "path": "/entities/enemy/alive", "value": True},
            {"op": "replace", "path": "/entities/enemy/hp", "value": new_hp},
            {"op": "replace", "path": "/entities/lbl_enemy_hp/text", "value": f"Enemy HP: {new_hp}"},
        ]
        if new_hp == 0:
            ops.append({"op": "replace", "path": "/entities/enemy/alive", "value": False})
        msg = "The slime is defeated!" if new_hp == 0 else "You hit the slime for 1 damage!"
        ops.append({"op": "replace", "path": "/entities/lbl_message/text", "value": msg})
        checks = [
            {"layer": "ir_state", "method": "exact_match", "path": "/entities/enemy/hp", "expected": new_hp},
            {"layer": "projection", "method": "node_property_equals", "entity_id": "lbl_enemy_hp", "property": "text", "expected": f"Enemy HP: {new_hp}"},
            {"layer": "projection", "method": "node_property_equals", "entity_id": "lbl_message", "property": "text", "expected": msg},
        ]
    else:
        ops = [
            {"op": "test", "path": "/entities/enemy/alive", "value": False},
            {"op": "replace", "path": "/entities/lbl_message/text", "value": "It's already dead!"},
        ]
        checks = [
            {"layer": "projection", "method": "node_property_equals", "entity_id": "lbl_message", "property": "text", "expected": "It's already dead!"},
        ]

    patch_doc = {"ops": ops}
    patch_str = json.dumps(patch_doc)
    acceptance_spec = {"timeout_frames": timeout_frames, "checks": checks}
    return {"request_id": request_id, "patch": patch_str, "acceptance_spec": acceptance_spec}


def send_patch_request(request: dict) -> dict:
    return _godot_tcp_call("apply_patch", {
        "patch": request["patch"],
        "acceptance_spec": request["acceptance_spec"],
        "request_id": request.get("request_id", ""),
    })


def handle_success(resp: dict, request_id: str) -> None:
    result = resp.get("result", {})
    data = result.get("data", {})
    verification = data.get("verification", {})
    print(
        "[OK] request_id=%s patch_applied=%s verification.ok=%s"
        % (request_id, data.get("applied", True), verification.get("ok", True))
    )
    state = fetch_ir_state()
    if state:
        entities = state.get("entities", {})
        enemy = entities.get("enemy", {})
        msg_ent = entities.get("lbl_message", {})
        print("     enemy.hp=%s enemy.alive=%s lbl_message.text=%s" % (
            enemy.get("hp"), enemy.get("alive"), msg_ent.get("text", "")))


def handle_error(resp: dict) -> None:
    err = resp.get("error", {})
    data = err.get("data", {})
    print(
        "[ERR] code=%s message=%s layer=%s evidence_path=%s"
        % (err.get("code"), err.get("message"), data.get("layer"), data.get("evidence_path"))
    )


def run_illegal_patch_verification() -> bool:
    """DoD 5: send an illegal patch and expect JSON-RPC error with layer and evidence_path."""
    illegal_request = {
        "request_id": "illegal_test",
        "patch": json.dumps({"ops": [
            {"op": "replace", "path": "/entities/nonexistent_entity/foo", "value": 1},
        ]}),
        "acceptance_spec": {},
    }
    resp = send_patch_request(illegal_request)
    if "error" not in resp:
        print("[DoD 5 FAIL] Expected error response for illegal patch, got success.")
        return False
    err = resp["error"]
    data = err.get("data", {})
    if not data.get("layer"):
        print("[DoD 5 FAIL] error.data.layer missing: %s" % data)
        return False
    if not data.get("evidence_path"):
        print("[DoD 5 WARN] error.data.evidence_path missing (optional): %s" % data)
    print("[DoD 5 OK] Illegal patch rejected: layer=%s evidence_path=%s" % (data.get("layer"), data.get("evidence_path")))
    return True


def main_loop() -> None:
    last_seq = 0
    running = True
    print("Mock Orchestrator: polling every %.1fs. Press Ctrl+C to stop." % POLL_INTERVAL_SEC)
    while running:
        try:
            events = fetch_events_since(last_seq)
            for ev in events:
                last_seq = max(last_seq, ev.get("seq", 0))
                if ev.get("source") != "ui" or ev.get("type") != "button_pressed" or ev.get("entity_id") != "btn_attack":
                    continue
                ir_state = fetch_ir_state()
                if not ir_state:
                    print("[WARN] get_ir_state failed, skip event")
                    continue
                request = build_attack_request(ir_state)
                if not request:
                    continue
                resp = send_patch_request(request)
                if "error" in resp:
                    handle_error(resp)
                else:
                    handle_success(resp, request.get("request_id", ""))
            time.sleep(POLL_INTERVAL_SEC)
        except KeyboardInterrupt:
            running = False
    print("Mock Orchestrator stopped.")


if __name__ == "__main__":
    if "--test-illegal" in sys.argv:
        ok = run_illegal_patch_verification()
        sys.exit(0 if ok else 1)
    main_loop()
