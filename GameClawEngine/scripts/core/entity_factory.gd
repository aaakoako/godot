## Entity Factory: maps IR entity type to Godot nodes (Node3D or Control).
## Pure projection logic — creates visual representations of IR data.
class_name EntityFactory
extends RefCounted

## Valid entity types as defined in Game IR v1 schema (3D + Sprint C.1 UI + Phase 2).
var _valid_types: Array[String] = ["cube", "sphere", "plane", "sprite", "combat_dummy", "label", "button", "game_entity"]

const AttributeSetComponentScript = preload("res://scripts/core/components/attribute_set_component.gd")
const TagSetComponentScript = preload("res://scripts/core/components/tag_set_component.gd")
const LifecycleComponentScript = preload("res://scripts/core/components/lifecycle_component.gd")
const PresentationComponentScript = preload("res://scripts/core/components/presentation_component.gd")
const Transform2DComponentScript = preload("res://scripts/core/components/transform_2d_component.gd")

## Asset registry cache for icon_ref resolution.
var _asset_registry_cache: Dictionary = {}


func _resolve_asset_ref(icon_ref: String) -> String:
	if _asset_registry_cache.is_empty():
		_load_asset_registry()
	if _asset_registry_cache.has(icon_ref):
		return _asset_registry_cache[icon_ref].get("local_path", "")
	return ""


func _load_asset_registry() -> void:
	var path := "res://data/asset_registry_draft.json"
	if not FileAccess.file_exists(path):
		push_warning("EntityFactory: asset registry not found at %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("EntityFactory: could not open asset registry")
		return
	var content := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(content)
	if data is Dictionary and data.has("assets"):
		for asset: Dictionary in data["assets"]:
			var ref := str(asset.get("asset_ref", ""))
			if not ref.is_empty():
				_asset_registry_cache[ref] = asset


func _create_sprite_material(entity_data: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var icon_ref: String = str(entity_data.get("icon_ref", ""))
	var local_path: String = ""
	if not icon_ref.is_empty():
		local_path = _resolve_asset_ref(icon_ref)
	if not local_path.is_empty() and FileAccess.file_exists(local_path):
		var tex := ImageTexture.create_from_image(Image.load_from_file(local_path))
		mat.albedo_texture = tex
	else:
		var fallback: String = str(entity_data.get("fallback_color", "#FFFFFF"))
		mat.albedo_color = Color.html(fallback)
	return mat


func _create_visual_from_icon_ref(icon_ref: String, entity_data: Dictionary) -> Node:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = QuadMesh.new()
	mesh_inst.material_override = _create_sprite_material(entity_data)
	return mesh_inst


## Create a Godot Node from an IR entity dictionary.
## Returns Node3D, Control (Label/Button), Node (game_entity), or null (e.g. combat_dummy).
func create(entity_id: String, entity_data: Dictionary) -> Node:
	var entity_type: String = entity_data.get("type", "")
	if entity_type not in _valid_types:
		push_error("EntityFactory: unknown entity type '%s' for '%s'" % [entity_type, entity_id])
		return null

	if entity_type == "game_entity":
		return _create_game_entity(entity_id, entity_data)

	if entity_type == "combat_dummy":
		return null

	if entity_type == "label":
		return _create_label(entity_id, entity_data)
	if entity_type == "button":
		return _create_button(entity_id, entity_data)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = entity_id
	mesh_instance.mesh = _create_mesh(entity_type)

	var material: StandardMaterial3D = _create_material(entity_data)
	mesh_instance.set_surface_override_material(0, material)

	_apply_transform(mesh_instance, entity_data)

	return mesh_instance


## Create a logical Node host for a game_entity and attach component children.
## If presentation.icon_ref is set, also create a visual MeshInstance3D child node.
func _create_game_entity(entity_id: String, entity_data: Dictionary) -> Node:
	var host: Node = Node.new()
	host.name = entity_id

	var components: Variant = entity_data.get("components", {})
	if components is not Dictionary:
		return host

	var comp_dict: Dictionary = components as Dictionary
	for comp_type: String in comp_dict:
		var comp_data: Variant = comp_dict[comp_type]
		if comp_data is not Dictionary:
			continue
		var comp_node: Node = _create_component(comp_type, comp_data as Dictionary)
		if comp_node != null:
			comp_node.name = comp_type
			host.add_child(comp_node)
		# Phase 2B: if presentation component has icon_ref, also attach a visual node
		if comp_type == "presentation":
			var pres_data: Dictionary = comp_data as Dictionary
			var icon_ref: String = str(pres_data.get("icon_ref", ""))
			if not icon_ref.is_empty():
				var vis_node: Node = _create_visual_from_icon_ref(icon_ref, entity_data)
				vis_node.name = "visual"
				host.add_child(vis_node)

	return host


func _create_component(comp_type: String, comp_data: Dictionary) -> Node:
	var comp: Node
	match comp_type:
		"attribute_set":
			comp = AttributeSetComponentScript.new()
			(comp as AttributeSetComponent).sync_from_ir(comp_data)
		"tag_set":
			comp = TagSetComponentScript.new()
			(comp as TagSetComponent).sync_from_ir(comp_data)
		"lifecycle":
			comp = LifecycleComponentScript.new()
			(comp as LifecycleComponent).sync_from_ir(comp_data)
		"presentation":
			comp = PresentationComponentScript.new()
			(comp as PresentationComponent).sync_from_ir(comp_data)
		"transform_2d":
			comp = Transform2DComponentScript.new()
			(comp as Transform2DComponent).sync_from_ir(comp_data)
		_:
			return null
	return comp


## Sync a game_entity host node's components from updated IR data.
func update_game_entity(host: Node, entity_data: Dictionary) -> void:
	var components: Variant = entity_data.get("components", {})
	if components is not Dictionary:
		return
	var comp_dict: Dictionary = components as Dictionary
	for comp_type: String in comp_dict:
		var comp_data: Variant = comp_dict[comp_type]
		if comp_data is not Dictionary:
			continue
		var comp_node: Node = host.get_node_or_null(comp_type)
		if comp_node == null:
			var new_comp: Node = _create_component(comp_type, comp_data as Dictionary)
			if new_comp != null:
				new_comp.name = comp_type
				host.add_child(new_comp)
		else:
			_sync_component(comp_node, comp_type, comp_data as Dictionary)


func _sync_component(comp_node: Node, comp_type: String, comp_data: Dictionary) -> void:
	match comp_type:
		"attribute_set":
			if comp_node is AttributeSetComponent:
				(comp_node as AttributeSetComponent).sync_from_ir(comp_data)
		"tag_set":
			if comp_node is TagSetComponent:
				(comp_node as TagSetComponent).sync_from_ir(comp_data)
		"lifecycle":
			if comp_node is LifecycleComponent:
				(comp_node as LifecycleComponent).sync_from_ir(comp_data)
		"presentation":
			if comp_node is PresentationComponent:
				(comp_node as PresentationComponent).sync_from_ir(comp_data)
		"transform_2d":
			if comp_node is Transform2DComponent:
				(comp_node as Transform2DComponent).sync_from_ir(comp_data)


func _create_label(entity_id: String, entity_data: Dictionary) -> Label:
	var label: Label = Label.new()
	label.name = entity_id
	_apply_control_props(label, entity_data)
	var txt: Variant = entity_data.get("text", "")
	label.text = str(txt)
	var font_size: Variant = entity_data.get("font_size", 16)
	if font_size is int or font_size is float:
		label.add_theme_font_size_override("font_size", int(font_size))
	var color_arr: Variant = entity_data.get("color", null)
	if color_arr is Array and (color_arr as Array).size() >= 4:
		var arr: Array = color_arr as Array
		label.add_theme_color_override("font_color", Color(_to_float(arr[0]), _to_float(arr[1]), _to_float(arr[2]), _to_float(arr[3])))
	return label


func _create_button(entity_id: String, entity_data: Dictionary) -> Button:
	var button: Button = Button.new()
	button.name = entity_id
	_apply_control_props(button, entity_data)
	var txt: Variant = entity_data.get("text", "")
	button.text = str(txt)
	return button


func _apply_control_props(control: Control, entity_data: Dictionary) -> void:
	var pos: Variant = entity_data.get("position", null)
	if pos is Array and (pos as Array).size() >= 2:
		var arr: Array = pos as Array
		control.position = Vector2(_to_float(arr[0]), _to_float(arr[1]))
	var sz: Variant = entity_data.get("size", null)
	if sz is Array and (sz as Array).size() >= 2:
		var arr: Array = sz as Array
		control.custom_minimum_size = Vector2(_to_float(arr[0]), _to_float(arr[1]))


## Update an existing node's visual properties from IR data.
## Used by the projection layer after a Patch modifies IR state.
func update_node(node: Node, entity_data: Dictionary) -> void:
	var entity_type: String = entity_data.get("type", "")
	if entity_type == "game_entity":
		update_game_entity(node, entity_data)
		return
	if node is Node3D:
		_apply_transform(node as Node3D, entity_data)
		if node is MeshInstance3D:
			var mat: StandardMaterial3D = _create_material(entity_data)
			(node as MeshInstance3D).set_surface_override_material(0, mat)
	elif node is Control:
		_apply_control_props(node as Control, entity_data)
		var txt: Variant = entity_data.get("text", null)
		if txt != null:
			if node is Label:
				(node as Label).text = str(txt)
			elif node is Button:
				(node as Button).text = str(txt)
		var font_size: Variant = entity_data.get("font_size", null)
		if font_size != null and node is Label:
			(node as Label).add_theme_font_size_override("font_size", int(font_size))
		var color_arr: Variant = entity_data.get("color", null)
		if color_arr is Array and (color_arr as Array).size() >= 4 and node is Label:
			var arr: Array = color_arr as Array
			(node as Label).add_theme_color_override("font_color", Color(_to_float(arr[0]), _to_float(arr[1]), _to_float(arr[2]), _to_float(arr[3])))


func _create_mesh(entity_type: String) -> Mesh:
	match entity_type:
		"cube":
			return BoxMesh.new()
		"sphere":
			return SphereMesh.new()
		"plane":
			return PlaneMesh.new()
		"sprite":
			return QuadMesh.new()
		_:
			return BoxMesh.new()


func _create_material(entity_data: Dictionary) -> StandardMaterial3D:
	var entity_type: String = entity_data.get("type", "")
	# Phase 2B: sprite entities use icon_ref / fallback_color
	if entity_type == "sprite":
		return _create_sprite_material(entity_data)
	var mat := StandardMaterial3D.new()
	var material_data: Dictionary = entity_data.get("material", {})
	var color_hex: String = material_data.get("color", "#FFFFFF")
	mat.albedo_color = Color.html(color_hex)
	return mat


func _apply_transform(node: Node3D, entity_data: Dictionary) -> void:
	var transform_data: Dictionary = entity_data.get("transform", {})

	var pos_arr: Variant = transform_data.get("position", [0, 0, 0])
	if pos_arr is Array and pos_arr.size() >= 3:
		node.position = Vector3(
			_to_float(pos_arr[0]),
			_to_float(pos_arr[1]),
			_to_float(pos_arr[2])
		)

	var rot_arr: Variant = transform_data.get("rotation", [0, 0, 0])
	if rot_arr is Array and rot_arr.size() >= 3:
		node.rotation_degrees = Vector3(
			_to_float(rot_arr[0]),
			_to_float(rot_arr[1]),
			_to_float(rot_arr[2])
		)

	var scale_arr: Variant = transform_data.get("scale", [1, 1, 1])
	if scale_arr is Array and scale_arr.size() >= 3:
		node.scale = Vector3(
			_to_float(scale_arr[0]),
			_to_float(scale_arr[1]),
			_to_float(scale_arr[2])
		)


func _to_float(value: Variant) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is String:
		return value.to_float()
	return 0.0
