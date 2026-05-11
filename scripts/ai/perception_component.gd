## perception_component.gd
## Handles visual and auditory perception for AI agents.
## Supports line-of-sight checks, field-of-view cones, and sound propagation.

class_name PerceptionComponent
extends Node

var sight_range: float = 200.0
var hearing_range: float = 120.0
var fov_angle: float = 120.0  ## Degrees

var visible_targets: Array[Node2D] = []
var last_heard_position: Vector2 = Vector2.INF
var _memory: Dictionary = {}  ## target -> {last_seen_pos, last_seen_time, threat_level}

func update_perception(owner: Node2D, tree: SceneTree) -> void:
	_scan_visual(owner, tree)
	_process_memory(owner)

func _scan_visual(owner: Node2D, tree: SceneTree) -> void:
	visible_targets.clear()
	var targets := tree.get_nodes_in_group("player")
	var facing := Vector2.RIGHT.rotated(owner.rotation)
	
	for target in targets:
		if not is_instance_valid(target):
			continue
		
		var to_target := target.global_position - owner.global_position
		var distance := to_target.length()
		
		if distance > sight_range:
			continue
		
		# FOV check
		var angle := rad_to_deg(facing.angle_to(to_target.normalized()))
		if absf(angle) > fov_angle / 2.0:
			continue
		
		# Line of sight (raycast)
		var space := owner.get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(
			owner.global_position, target.global_position, 1  # Wall layer
		)
		var result := space.intersect_ray(query)
		
		if result.is_empty():
			visible_targets.append(target)
			_memory[target] = {
				"last_seen_pos": target.global_position,
				"last_seen_time": Time.get_ticks_msec() / 1000.0,
				"threat_level": 1.0 - (distance / sight_range)
			}

func _process_memory(owner: Node2D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var stale_keys := []
	
	for target in _memory:
		if now - _memory[target]["last_seen_time"] > 10.0:
			stale_keys.append(target)
	
	for key in stale_keys:
		_memory.erase(key)

func get_visible_targets() -> Array[Node2D]:
	return visible_targets

func get_last_known_position(target: Node2D) -> Vector2:
	if _memory.has(target):
		return _memory[target]["last_seen_pos"]
	return Vector2.INF

func hear_sound(sound_pos: Vector2, owner_pos: Vector2, loudness: float = 1.0) -> void:
	var effective_range := hearing_range * loudness
	if owner_pos.distance_to(sound_pos) <= effective_range:
		last_heard_position = sound_pos


## Returns visible targets sorted by distance (nearest first).
func get_visible_targets_sorted() -> Array[Node2D]:
	var targets := get_visible_targets()
	targets.sort_custom(func(a, b):
		return global_position.distance_to(a.global_position) < \
		       global_position.distance_to(b.global_position)
	)
	return targets

## Returns true if node is within hearing range.
func can_hear(node: Node2D, intensity: float = 1.0) -> bool:
	return global_position.distance_to(node.global_position) <= hearing_range * intensity


## Alert level based on proximity of nearest visible target.
func get_alert_level() -> float:
	var targets := get_visible_targets()
	if targets.is_empty():
		return 0.0
	var nearest_dist := INF
	for t in targets:
		nearest_dist = minf(nearest_dist, global_position.distance_to(t.global_position))
	return 1.0 - clampf(nearest_dist / sight_range, 0.0, 1.0)

## Maximum number of simultaneous targets tracked.
@export var max_tracked_targets: int = 8

## Returns the count of currently visible targets.
func visible_target_count() -> int:
	return get_visible_targets().size()
