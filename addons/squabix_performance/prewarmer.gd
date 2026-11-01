@icon("res://addons/squabix_performance/icons/stopwatch_mesh.svg")
class_name Prewarmer
extends Resource

signal progress(done: int, total: int)
signal finished

const SCENE_EXTENSIONS: PackedStringArray = ["tscn", "scn"]
const REMAP_SUFFIX := ".remap"
const CAMERA_FIT_MARGIN := 1.25
const MIN_CAMERA_DISTANCE := 2.0 # m
const MATERIAL_PREVIEW_RADIUS := 0.5 # m
const MATERIAL_PREVIEW_SIZE := Vector2(32.0, 32.0) # px

@export_group("Content")
@export var scenes: Array[PackedScene]
@export var materials: Array[Material]
@export var includes: Array[Prewarmer]

@export_group("Directory", "directory")
@export_dir var directory_paths: Array[String]
@export var directory_recursive := true

@export_group("Rendering", "render")
@export_custom(PROPERTY_HINT_NONE, "suffix:px") var render_viewport_size := Vector2i(64, 64)
@export_range(1.0, 179.0, 0.1, "suffix:°") var render_camera_fov := 60.0
@export_range(1, 30, 1, "suffix:frames") var render_frames := 3
@export_range(0, 256, 1) var render_batch_size := 16
@export var render_emit_particles := true

@export_group("Timing", "timing")
@export_range(1, 600, 1, "suffix:frames") var timing_start_delay_frames := 1
@export var timing_run_once := true

var is_warming := false
var is_warmed := false


static func warm_all(tree: SceneTree, prewarmers: Array[Prewarmer]) -> void:
	for prewarmer in prewarmers:
		if prewarmer != null:
			await prewarmer.warm(tree)


static func is_audio_player(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


static func is_particles(node: Node) -> bool:
	return node is GPUParticles3D or node is CPUParticles3D or node is GPUParticles2D or node is CPUParticles2D


static func get_subtree(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	return nodes


static func silence(root: Node) -> void:
	for node in get_subtree(root):
		if not is_audio_player(node):
			continue
		node.set(&"autoplay", false)
		node.set(&"stream", null)


static func start_particles(root: Node) -> void:
	for node in get_subtree(root):
		if is_particles(node):
			node.set(&"emitting", true)


static func get_world_radius(root: Node) -> float:
	var radius := 0.0
	for node in get_subtree(root):
		var visual := node as VisualInstance3D
		if visual == null or not visual.is_inside_tree():
			continue

		var bounds := visual.global_transform * visual.get_aabb()
		radius = maxf(radius, bounds.get_center().length() + bounds.size.length() * 0.5)
	return radius


static func create_material_preview(material: Material) -> Node:
	if is_canvas_material(material):
		var rect := ColorRect.new()
		rect.size = MATERIAL_PREVIEW_SIZE
		rect.material = material
		return rect

	if not is_spatial_material(material):
		return null

	var mesh := SphereMesh.new()
	mesh.radius = MATERIAL_PREVIEW_RADIUS
	mesh.height = MATERIAL_PREVIEW_RADIUS * 2.0
	mesh.material = material

	var preview := MeshInstance3D.new()
	preview.mesh = mesh
	return preview


static func is_canvas_material(material: Material) -> bool:
	if material is CanvasItemMaterial:
		return true
	var shader_material := material as ShaderMaterial
	return shader_material != null and shader_material.shader != null and shader_material.shader.get_mode() == Shader.MODE_CANVAS_ITEM


static func is_spatial_material(material: Material) -> bool:
	if material is BaseMaterial3D:
		return true
	var shader_material := material as ShaderMaterial
	return shader_material != null and shader_material.shader != null and shader_material.shader.get_mode() == Shader.MODE_SPATIAL


static func scan_directory(path: String, recursive: bool) -> Array[PackedScene]:
	var found: Array[PackedScene] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return found

	for file in directory.get_files():
		var resolved := file.trim_suffix(REMAP_SUFFIX)
		if resolved.get_extension() not in SCENE_EXTENSIONS:
			continue

		var scene := load(path.path_join(resolved)) as PackedScene
		if scene != null:
			found.append(scene)

	if not recursive:
		return found

	for subdirectory in directory.get_directories():
		found.append_array(scan_directory(path.path_join(subdirectory), recursive))
	return found


func warm(tree: SceneTree) -> void:
	if is_warming:
		await finished
		return
	if is_warmed and timing_run_once:
		return

	is_warming = true
	await wait_frames(tree, timing_start_delay_frames)

	var sources := collect_sources()
	var done := 0
	progress.emit(done, sources.size())

	for batch in split_batches(sources):
		await render_batch(tree, batch)
		done += batch.size()
		progress.emit(done, sources.size())

	is_warming = false
	is_warmed = true
	finished.emit()


func reset() -> void:
	is_warmed = false
	for included in includes:
		if included != null and included != self:
			included.reset()


func get_source_count() -> int:
	return collect_sources().size()


func collect_sources() -> Array:
	var sources: Array = []
	append_sources(sources, [])
	return sources


func append_sources(sources: Array, visited: Array[Prewarmer]) -> void:
	if self in visited:
		return
	visited.append(self)

	for included in includes:
		if included != null:
			included.append_sources(sources, visited)

	append_unique(sources, scenes)
	append_unique(sources, materials)
	for path in directory_paths:
		append_unique(sources, scan_directory(path, directory_recursive))


func append_unique(sources: Array, additions: Array) -> void:
	for addition in additions:
		if addition != null and addition not in sources:
			sources.append(addition)


func split_batches(sources: Array) -> Array[Array]:
	var batches: Array[Array] = []
	var size := render_batch_size if render_batch_size > 0 else maxi(sources.size(), 1)

	for start in range(0, sources.size(), size):
		batches.append(sources.slice(start, start + size))
	return batches


func render_batch(tree: SceneTree, batch: Array) -> void:
	var viewport := create_viewport(tree)
	tree.root.add_child(viewport)

	var camera := create_camera()
	viewport.add_child(camera)

	var radius := 0.0
	for source in batch:
		var node := create_node(source)
		if node == null:
			continue

		viewport.add_child(node)
		if render_emit_particles:
			start_particles(node)
		radius = maxf(radius, get_world_radius(node))

	camera.position.z = get_camera_distance(radius)
	await wait_frames(tree, render_frames)
	viewport.queue_free()


func create_viewport(tree: SceneTree) -> SubViewport:
	var source := tree.root
	var viewport := SubViewport.new()
	viewport.size = render_viewport_size
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = source.msaa_3d
	viewport.screen_space_aa = source.screen_space_aa
	viewport.use_taa = source.use_taa
	viewport.use_debanding = source.use_debanding
	return viewport


func create_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = render_camera_fov
	camera.current = true
	return camera


func create_node(source: Variant) -> Node:
	if source is PackedScene:
		var instance: Node = source.instantiate()
		silence(instance)
		return instance

	if source is Material:
		return create_material_preview(source)
	return null


func get_camera_distance(radius: float) -> float:
	var half_fov := deg_to_rad(render_camera_fov * 0.5)
	return maxf(MIN_CAMERA_DISTANCE, radius / tan(half_fov) * CAMERA_FIT_MARGIN + radius)


func wait_frames(tree: SceneTree, frames: int) -> void:
	for i in frames:
		await tree.process_frame
