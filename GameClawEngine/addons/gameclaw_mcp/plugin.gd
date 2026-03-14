@tool
extends EditorPlugin

## Editor plugin for GameClaw MCP.
## - Provides LSP (via the editor process).
## - Auto-plays the main scene when launched with --autoplay (used by launch_godot.py).
## - MCP TCP server runs in the game process via autoload (MCPTCPServer).

var _autoplay_requested: bool = false
var _autoplay_timer: Timer


func _enter_tree() -> void:
	if _has_cmdline_flag("--autoplay"):
		_autoplay_requested = true
		print("[GameClaw MCP] --autoplay detected. Will play main scene after editor is ready.")
		_autoplay_timer = Timer.new()
		_autoplay_timer.wait_time = 1.5
		_autoplay_timer.one_shot = true
		_autoplay_timer.timeout.connect(_on_autoplay_timer)
		add_child(_autoplay_timer)
		_autoplay_timer.start()
	else:
		print("[GameClaw MCP] Plugin loaded. Run the game (F5) or use launch_godot.py to start MCP.")


func _on_autoplay_timer() -> void:
	if _autoplay_timer:
		_autoplay_timer.queue_free()
		_autoplay_timer = null
	if not _autoplay_requested:
		return
	if EditorInterface.is_playing_scene():
		print("[GameClaw MCP] Scene already playing, skipping auto-play.")
		return
	print("[GameClaw MCP] Auto-play: launching main scene...")
	EditorInterface.play_main_scene()


func _exit_tree() -> void:
	pass


func _has_cmdline_flag(flag: String) -> bool:
	for arg: String in OS.get_cmdline_args():
		if arg.strip_edges() == flag:
			return true
	for arg: String in OS.get_cmdline_user_args():
		if arg.strip_edges() == flag:
			return true
	return false
