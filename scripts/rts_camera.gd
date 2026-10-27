extends Node3D
## RTS camera. Mouse: left-drag pans (the ground under the cursor follows it), right-drag rotates,
## middle-drag tilts, wheel zooms. Left/right drags are routed here by game.gd, which also uses
## left/right clicks for selection and orders. Keys: WASD / arrows pan, Q/E rotate, R/F tilt.

const MIN_PITCH := deg_to_rad(12.0)
const MAX_PITCH := deg_to_rad(85.0)

var world: WorldGen
var cam := Camera3D.new()
var target := Vector3(150.0, 0.0, 0.0)
var dist := 420.0
var yaw := PI / 2.0
## Added to the zoom-based default pitch by tilting.
var tilt := 0.0
var _tilting := false
var _last := Vector2.ZERO
var _anchor := Vector3.ZERO


func _ready() -> void:
	cam.fov = 50.0
	cam.near = 0.5
	cam.far = 6000.0
	add_child(cam)
	cam.current = true
	_apply()


func set_view(t: Vector3, d: float, y: float) -> void:
	target = t
	dist = d
	yaw = y
	_apply()


func pitch() -> float:
	var base := lerpf(deg_to_rad(24.0), deg_to_rad(58.0), clampf((dist - 25.0) / 900.0, 0.0, 1.0))
	return clampf(base + tilt, MIN_PITCH, MAX_PITCH)


## Grab-style panning: remember the ground point under the cursor, then keep it there.
func grab_start(screen: Vector2, ground) -> void:
	_anchor = Vector3(ground.x, world.h_at(ground.x, ground.y), ground.y) if ground != null else Vector3(target.x, target.y, target.z)


func grab_move(screen: Vector2) -> void:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.02:
		return
	var t := (_anchor.y - o.y) / d.y
	if t <= 0.0:
		return
	var p := o + d * t
	target.x += _anchor.x - p.x
	target.z += _anchor.z - p.z
	_apply()


func rotate_by(dx: float) -> void:
	yaw -= dx * 0.005
	_apply()


func _process(delta: float) -> void:
	var speed := dist * 1.1 * delta
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): target += fwd * speed
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): target -= fwd * speed
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): target -= right * speed
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): target += right * speed
	if Input.is_key_pressed(KEY_Q): yaw += 1.4 * delta
	if Input.is_key_pressed(KEY_E): yaw -= 1.4 * delta
	if Input.is_key_pressed(KEY_R): tilt -= 0.8 * delta
	if Input.is_key_pressed(KEY_F): tilt += 0.8 * delta
	_apply()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = clampf(dist / 1.12, 25.0, 1400.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = clampf(dist * 1.12, 25.0, 1400.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_tilting = mb.pressed
			_last = mb.position
	elif e is InputEventMouseMotion and _tilting:
		var mm := e as InputEventMouseMotion
		# Drag down to look more steeply down on the battlefield, up to look toward the horizon.
		tilt += (mm.position.y - _last.y) * 0.004
		_last = mm.position
	tilt = clampf(tilt, -1.2, 1.2)


func _apply() -> void:
	if world == null:
		return
	target.x = clampf(target.x, -WorldGen.HALF, WorldGen.HALF)
	target.z = clampf(target.z, -WorldGen.HALF, WorldGen.HALF)
	target.y = world.h_at(target.x, target.z)
	var p := pitch()
	var pos := target + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	pos.y = maxf(pos.y, world.h_at(pos.x, pos.z) + 4.0)
	cam.global_position = pos
	cam.look_at(target + Vector3(0.0, minf(dist * 0.04, 6.0), 0.0), Vector3.UP if p < deg_to_rad(84.0) else Vector3(-sin(yaw), 0.0, -cos(yaw)))
