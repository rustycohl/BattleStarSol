extends Node3D

# CameraController.gd — Smooth & tactical 3D orbit/zoom/pan camera system

@export var target_node: Node3D = null
var yaw: float = 42.0
var pitch: float = 54.0
var distance: float = 30.0
var camera: Camera3D

var dragging: bool = false
var desired_pivot_pos: Vector3 = Vector3.ZERO

enum Mode { BEV, OTS, FPS }
var active_mode: Mode = Mode.BEV

# Free Fly / Remote Drone Camera Mode
var free_fly_mode: bool = false
var fly_speed: float = 20.0

func toggle_free_fly() -> bool:
	free_fly_mode = not free_fly_mode
	if free_fly_mode:
		desired_pivot_pos = global_position
	return free_fly_mode

func _ready() -> void:
	desired_pivot_pos = global_position
	_build_camera()

func _build_camera() -> void:
	camera = Camera3D.new()
	add_child(camera)
	apply_camera_transform()

func apply_camera_transform() -> void:
	rotation_degrees = Vector3(0, yaw, 0)
	var p_rad := deg_to_rad(pitch)
	if camera:
		if active_mode == Mode.BEV:
			camera.fov = 62.0
			camera.position = Vector3(0.0, sin(p_rad), cos(p_rad)) * distance
			camera.look_at(global_position, Vector3.UP)
		elif active_mode == Mode.OTS:
			camera.fov = 72.0
			camera.position = Vector3(1.15, 2.15, 4.25)
			camera.look_at(global_position + Vector3(0, 1.15, 0), Vector3.UP)
		elif active_mode == Mode.FPS:
			camera.fov = 78.0
			camera.position = Vector3(0.0, 1.65, 0.1)
			camera.rotation_degrees = Vector3(-pitch, 0, 0)

func set_mode(m: Mode) -> void:
	active_mode = m
	if active_mode == Mode.FPS:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(self, "pitch", 0.0, 0.3)
		tw.tween_property(self, "distance", 2.0, 0.3)
	elif active_mode == Mode.OTS:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(self, "pitch", 10.0, 0.3)
		tw.tween_property(self, "distance", 4.0, 0.3)
	else:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(self, "pitch", 54.0, 0.3)
		tw.tween_property(self, "distance", 30.0, 0.3)
	apply_camera_transform()

func orbit(delta_yaw: float, delta_pitch: float) -> void:
	var target_yaw = yaw - delta_yaw
	var min_p = -80.0 if active_mode == Mode.FPS else (5.0 if free_fly_mode else 20.0)
	var max_p = 80.0 if active_mode == Mode.FPS else (88.0 if free_fly_mode else 75.0)
	var target_pitch = clampf(pitch + delta_pitch, min_p, max_p)

	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "yaw", target_yaw, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "pitch", target_pitch, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func zoom(delta_dist: float) -> void:
	var target_distance = clampf(distance + delta_dist, 2.0 if free_fly_mode else 8.0, 60.0 if free_fly_mode else 44.0)
	var tw = create_tween()
	tw.tween_property(self, "distance", target_distance, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func pan_keyboard(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_action_pressed("camera_up"): dir.z -= 1.0
	if Input.is_action_pressed("camera_down"): dir.z += 1.0
	if Input.is_action_pressed("camera_left"): dir.x -= 1.0
	if Input.is_action_pressed("camera_right"): dir.x += 1.0
	if dir == Vector3.ZERO:
		return
	var yr := deg_to_rad(yaw)
	var forward := Vector3(sin(yr), 0.0, cos(yr))
	var right := Vector3(cos(yr), 0.0, -sin(yr))
	desired_pivot_pos += (right * dir.x + forward * dir.z).normalized() * 18.0 * delta

func _process_free_fly(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_action_pressed("camera_up"): move.z -= 1.0
	if Input.is_action_pressed("camera_down"): move.z += 1.0
	if Input.is_action_pressed("camera_left"): move.x -= 1.0
	if Input.is_action_pressed("camera_right"): move.x += 1.0
	if Input.is_action_pressed("camera_elevate") or Input.is_action_pressed("jump"): move.y += 1.0
	if Input.is_action_pressed("camera_descend"): move.y -= 1.0

	if move != Vector3.ZERO:
		var mult := 2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var yr := deg_to_rad(yaw)
		var forward := Vector3(sin(yr), 0.0, cos(yr))
		var right := Vector3(cos(yr), 0.0, -sin(yr))
		desired_pivot_pos += (right * move.x + forward * move.z + Vector3.UP * move.y).normalized() * fly_speed * mult * delta
	global_position = global_position.lerp(desired_pivot_pos, 12.0 * delta)
	apply_camera_transform()

func focus_position(world_pos: Vector3) -> void:
	desired_pivot_pos = world_pos
	var tw := create_tween()
	tw.tween_property(self, "global_position", world_pos, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func focus_unit(u_node: Node3D) -> void:
	if u_node:
		target_node = u_node
		focus_position(u_node.global_position)

func _process(delta: float) -> void:
	if free_fly_mode:
		_process_free_fly(delta)
		return

	pan_keyboard(delta)
	if target_node:
		desired_pivot_pos = target_node.global_position
	global_position = global_position.lerp(desired_pivot_pos, 10.0 * delta)
	apply_camera_transform()
