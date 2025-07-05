## steering_component.gd
## Craig Reynolds-style steering behaviors for smooth AI movement.

class_name SteeringComponent
extends Node

var _seek_target: Vector2 = Vector2.INF
var _flee_target: Vector2 = Vector2.INF
var _wander_angle: float = 0.0

func seek(target: Vector2) -> void:
	_seek_target = target
	_flee_target = Vector2.INF

func flee(target: Vector2) -> void:
	_flee_target = target
	_seek_target = Vector2.INF

func calculate(owner: CharacterBody2D, delta: float) -> Vector2:
	var steering := Vector2.ZERO
	
	if _seek_target != Vector2.INF:
		var desired := (_seek_target - owner.global_position).normalized()
		steering += desired
	
	if _flee_target != Vector2.INF:
		var desired := (owner.global_position - _flee_target).normalized()
		steering += desired * 1.5
	
	# Obstacle avoidance via raycasts
	steering += _avoid_obstacles(owner) * 2.0
	
	return steering.normalized() if steering.length() > 0 else Vector2.ZERO

func _avoid_obstacles(owner: CharacterBody2D) -> Vector2:
	var avoidance := Vector2.ZERO
	var space := owner.get_world_2d().direct_space_state
	var facing := Vector2.RIGHT.rotated(owner.rotation)
	
	for angle_offset in [-30.0, -15.0, 0.0, 15.0, 30.0]:
		var ray_dir := facing.rotated(deg_to_rad(angle_offset))
		var query := PhysicsRayQueryParameters2D.create(
			owner.global_position,
			owner.global_position + ray_dir * 48.0,
			1  # Wall layer
		)
		var result := space.intersect_ray(query)
		if not result.is_empty():
			var hit_normal: Vector2 = result.get("normal", Vector2.ZERO)
			avoidance += hit_normal
	
	return avoidance


## Flee from a position (opposite of seek).
func flee(from_pos: Vector2) -> void:
	var dir := (global_position - from_pos).normalized()
	_desired_velocity = dir * max_speed

## Arrive: slows down as agent approaches target.
func arrive(target_pos: Vector2, slow_radius: float = 48.0) -> void:
	var to_target := target_pos - global_position
	var dist := to_target.length()
	var speed := max_speed if dist > slow_radius else max_speed * (dist / slow_radius)
	_desired_velocity = to_target.normalized() * speed
