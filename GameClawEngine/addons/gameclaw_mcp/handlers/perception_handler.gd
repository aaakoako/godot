## Handler for Render Output layer MCP commands.
## Provides visual perception: viewport screenshots and log reading.
## Enables AI to verify that projected scene looks correct.
class_name MCPPerceptionHandler
extends RefCounted

const LAYER_RENDER: String = "render_output"
const MAX_LOG_LINES: int = 200


## Register all perception-related tools on the given router.
static func register_tools(router: MCPCommandRouter) -> void:
	var handler := MCPPerceptionHandler.new()
	router.register_handler_instance(handler)
	router.register("capture_screenshot", handler._handle_capture_screenshot)
	router.register("capture_viewport", handler._handle_capture_viewport)
	router.register("read_godot_log", handler._handle_read_godot_log)


func _handle_capture_screenshot(params: Variant) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", ["Ensure the game is running."])

	var viewport: Viewport = tree.root
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return _fail("Viewport texture is null", ["Ensure the viewport has rendered at least one frame."])

	var image: Image = texture.get_image()
	if image == null:
		return _fail("Failed to get image from viewport texture", [])

	var png_buffer: PackedByteArray = image.save_png_to_buffer()
	if png_buffer.is_empty():
		return _fail("Failed to encode image to PNG", [])

	var base64: String = Marshalls.raw_to_base64(png_buffer)
	return {
		"success": true,
		"data": {
			"format": "png",
			"encoding": "base64",
			"width": image.get_width(),
			"height": image.get_height(),
			"data": base64,
		}
	}


func _handle_capture_viewport(params: Variant) -> Dictionary:
	var width: int = 640
	var height: int = 360

	if params is Dictionary:
		width = int((params as Dictionary).get("width", width))
		height = int((params as Dictionary).get("height", height))

	width = clampi(width, 64, 3840)
	height = clampi(height, 64, 2160)

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return _fail("SceneTree not available", [])

	var viewport: Viewport = tree.root
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return _fail("Viewport texture is null", [])

	var image: Image = texture.get_image()
	if image == null:
		return _fail("Failed to get image from viewport texture", [])

	if image.get_width() != width or image.get_height() != height:
		image.resize(width, height, Image.INTERPOLATE_BILINEAR)

	var png_buffer: PackedByteArray = image.save_png_to_buffer()
	if png_buffer.is_empty():
		return _fail("Failed to encode resized image to PNG", [])

	var base64: String = Marshalls.raw_to_base64(png_buffer)
	return {
		"success": true,
		"data": {
			"format": "png",
			"encoding": "base64",
			"width": image.get_width(),
			"height": image.get_height(),
			"data": base64,
		}
	}


func _handle_read_godot_log(params: Variant) -> Dictionary:
	var max_lines: int = MAX_LOG_LINES
	var filter: String = ""

	if params is Dictionary:
		max_lines = int((params as Dictionary).get("lines", max_lines))
		filter = str((params as Dictionary).get("filter", ""))

	max_lines = clampi(max_lines, 1, 1000)

	var log_path: String = _get_godot_log_path()
	if log_path.is_empty():
		return _fail("Could not determine Godot log file path", [])

	if not FileAccess.file_exists(log_path):
		return _fail("Log file not found at %s" % log_path, [])

	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open log file", [])

	var all_lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var result_lines: Array = []
	var start_idx: int = maxi(0, all_lines.size() - max_lines)

	for i: int in range(start_idx, all_lines.size()):
		var line: String = all_lines[i]
		if filter.is_empty() or line.containsn(filter):
			result_lines.append(line)

	return {"success": true, "data": {"line_count": result_lines.size(), "lines": result_lines}}


func _get_godot_log_path() -> String:
	var base_dir: String = OS.get_user_data_dir()
	var log_dir: String = base_dir.path_join("logs")
	var log_file: String = log_dir.path_join("godot.log")
	if FileAccess.file_exists(log_file):
		return log_file
	return ""


func _fail(message: String, next_steps: Array) -> Dictionary:
	var result: Dictionary = {"success": false, "error": message, "layer": LAYER_RENDER}
	if not next_steps.is_empty():
		result["next_steps"] = next_steps
	return result
