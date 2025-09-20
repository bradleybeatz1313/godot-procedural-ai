## ai_agent.gd
## Base AI agent with pluggable behavior tree and A* pathfinding integration.
## Agents observe the dungeon through a perception system and make decisions
## via a data-driven behavior tree loaded from AgentConfig resources.
##
## Architecture:
##   AIAgent → BehaviorTree (decision) → Steering (movement) → Perception (sensing)

class_name AIAgent
extends CharacterBody2D

signal state_changed(old_state: StringName, new_state: StringName)
signal target_acquired(target: Node2D)
signal target_lost
signal health_changed(new_health: float, max_health: float)
signal agent_died

## --- Configuration ---

@export var config: AgentConfig
@export var debug_draw: bool = false

@export_group("Movement")
@export var move_speed: float = 120.0
@export var acceleration: float = 800.0
@export var friction: float = 600.0

@export_group("Combat")
@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_range: float = 32.0
@export var attack_cooldown: float = 1.2

## --- State ---

var health: float
var current_target: Node2D = null
var current_path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var _behavior_tree: BehaviorTreeNode
var _perception: PerceptionComponent
var _steering: SteeringComponent
var _attack_timer: float = 0.0
var _current_state: StringName = &"idle"

## --- Lifecycle ---

func _ready() -> void:
	health = max_health
	
	_perception = PerceptionComponent.new()
	_perception.sight_range = config.sight_range if config else 200.0
	_perception.hearing_range = config.hearing_range if config else 100.0
	_perception.fov_angle = config.fov_angle if config else 120.0
	add_child(_perception)
	
	_steering = SteeringComponent.new()
	add_child(_steering)
	
	_behavior_tree = _build_behavior_tree()
	
	if config:
		move_speed = config.move_speed
		max_health = config.max_health
		health = max_health
		attack_damage = config.attack_damage
		attack_range = config.attack_range


func _physics_process(delta: float) -> void:
	if health <= 0:
		return
	
	_attack_timer = maxf(0.0, _attack_timer - delta)
	
	# Update perception
	_perception.update_perception(self, get_tree())
	
	# Evaluate behavior tree
	if _behavior_tree:
		var context := BehaviorContext.new()
		context.agent = self
		context.delta = delta
		context.perception = _perception
		context.has_target = current_target != null and is_instance_valid(current_target)
		context.health_ratio = health / max_health
		_behavior_tree.execute(context)
	
	# Apply steering forces
	var steering_force := _steering.calculate(self, delta)
	velocity = velocity.move_toward(steering_force * move_speed, acceleration * delta)
	
	if velocity.length() < 10.0 and _current_state == &"idle":
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	move_and_slide()
	
	if debug_draw:
		queue_redraw()


func _draw() -> void:
	if not debug_draw:
		return
	
	# Draw perception cone
	var sight_range: float = _perception.sight_range
	var fov_rad: float = deg_to_rad(_perception.fov_angle / 2.0)
	var facing := Vector2.RIGHT.rotated(rotation)
	
	var left_bound := facing.rotated(-fov_rad) * sight_range
	var right_bound := facing.rotated(fov_rad) * sight_range
	
	draw_line(Vector2.ZERO, left_bound, Color(1, 1, 0, 0.3), 1.0)
	draw_line(Vector2.ZERO, right_bound, Color(1, 1, 0, 0.3), 1.0)
	
	# Draw path
	if current_path.size() > 1:
		for i in range(path_index, current_path.size() - 1):
			var from_local := current_path[i] - global_position
			var to_local := current_path[i + 1] - global_position
			draw_line(from_local, to_local, Color(0, 1, 0, 0.5), 2.0)
	
	# Draw target indicator
	if current_target and is_instance_valid(current_target):
		var target_local := current_target.global_position - global_position
		draw_circle(target_local, 6.0, Color(1, 0, 0, 0.5))


## --- State Management ---

func set_state(new_state: StringName) -> void:
	if new_state == _current_state:
		return
	var old := _current_state
	_current_state = new_state
	state_changed.emit(old, new_state)
	EventBus.agent_state_changed.emit(self, old, new_state)


func get_state() -> StringName:
	return _current_state


## --- Actions ---

func navigate_to(target_pos: Vector2) -> void:
	var astar: AStar2D = GameManager.get_astar()
	if not astar:
		return
	
	var start_id := astar.get_closest_point(global_position)
	var end_id := astar.get_closest_point(target_pos)
	
	current_path = astar.get_point_path(start_id, end_id)
	path_index = 0
	
	if current_path.size() > 0:
		set_state(&"moving")


func follow_path(delta: float) -> bool:
	"""Advances along current_path. Returns true when destination reached."""
	if path_index >= current_path.size():
		set_state(&"idle")
		return true
	
	var target_point := current_path[path_index]
	var direction := (target_point - global_position)
	
	if direction.length() < 8.0:
		path_index += 1
		if path_index >= current_path.size():
			set_state(&"idle")
			return true
	
	_steering.seek(target_point)
	return false


func attempt_attack() -> bool:
	"""Tries to attack current target. Returns true if attack executed."""
	if not current_target or not is_instance_valid(current_target):
		return false
	
	if _attack_timer > 0.0:
		return false
	
	var dist := global_position.distance_to(current_target.global_position)
	if dist > attack_range:
		return false
	
	_attack_timer = attack_cooldown
	set_state(&"attacking")
	
	if current_target.has_method("take_damage"):
		current_target.take_damage(attack_damage, self)
	
	EventBus.agent_attacked.emit(self, current_target, attack_damage)
	return true


func take_damage(amount: float, attacker: Node2D = null) -> void:
	health -= amount
	health_changed.emit(health, max_health)
	EventBus.agent_damaged.emit(self, amount, attacker)
	
	if health <= 0:
		_die()
	elif _current_state != &"fleeing":
		# Aggro on attacker if not already engaged
		if current_target == null and attacker:
			current_target = attacker
			target_acquired.emit(attacker)
			set_state(&"pursuing")


func _die() -> void:
	set_state(&"dead")
	agent_died.emit()
	EventBus.agent_died.emit(self)
	
	# Death animation/cleanup handled by visual component
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


## --- Behavior Tree Construction ---

func _build_behavior_tree() -> BehaviorTreeNode:
	"""Builds a selector-based behavior tree for this agent type."""
	
	# Root: Priority Selector
	var root := SelectorNode.new("root")
	
	# 1. Flee when low health
	var flee_seq := SequenceNode.new("flee_sequence")
	flee_seq.add_child(ConditionNode.new("health_critical", func(ctx):
		return ctx.health_ratio < 0.2
	))
	flee_seq.add_child(ActionNode.new("flee", _action_flee))
	root.add_child(flee_seq)
	
	# 2. Attack if target in range
	var attack_seq := SequenceNode.new("attack_sequence")
	attack_seq.add_child(ConditionNode.new("has_target", func(ctx):
		return ctx.has_target
	))
	attack_seq.add_child(ConditionNode.new("in_range", func(ctx):
		return ctx.agent.global_position.distance_to(
			ctx.agent.current_target.global_position
		) <= ctx.agent.attack_range
	))
	attack_seq.add_child(ActionNode.new("attack", _action_attack))
	root.add_child(attack_seq)
	
	# 3. Pursue detected target
	var pursue_seq := SequenceNode.new("pursue_sequence")
	pursue_seq.add_child(ConditionNode.new("has_target", func(ctx):
		return ctx.has_target
	))
	pursue_seq.add_child(ActionNode.new("pursue", _action_pursue))
	root.add_child(pursue_seq)
	
	# 4. Investigate sounds
	var investigate_seq := SequenceNode.new("investigate_sequence")
	investigate_seq.add_child(ConditionNode.new("heard_noise", func(ctx):
		return ctx.perception.last_heard_position != Vector2.INF
	))
	investigate_seq.add_child(ActionNode.new("investigate", _action_investigate))
	root.add_child(investigate_seq)
	
	# 5. Patrol (default)
	root.add_child(ActionNode.new("patrol", _action_patrol))
	
	return root


## --- Behavior Actions ---

func _action_flee(context: BehaviorContext) -> int:
	set_state(&"fleeing")
	if current_target and is_instance_valid(current_target):
		var flee_dir := (global_position - current_target.global_position).normalized()
		var flee_target := global_position + flee_dir * 200.0
		navigate_to(flee_target)
		follow_path(context.delta)
	return BehaviorTreeNode.SUCCESS


func _action_attack(context: BehaviorContext) -> int:
	if attempt_attack():
		return BehaviorTreeNode.SUCCESS
	return BehaviorTreeNode.RUNNING


func _action_pursue(context: BehaviorContext) -> int:
	set_state(&"pursuing")
	if current_target and is_instance_valid(current_target):
		navigate_to(current_target.global_position)
		follow_path(context.delta)
		return BehaviorTreeNode.RUNNING
	
	current_target = null
	target_lost.emit()
	return BehaviorTreeNode.FAILURE


func _action_investigate(context: BehaviorContext) -> int:
	set_state(&"investigating")
	var noise_pos := context.perception.last_heard_position
	if noise_pos != Vector2.INF:
		navigate_to(noise_pos)
		if follow_path(context.delta):
			context.perception.last_heard_position = Vector2.INF
			return BehaviorTreeNode.SUCCESS
		return BehaviorTreeNode.RUNNING
	return BehaviorTreeNode.FAILURE


func _action_patrol(context: BehaviorContext) -> int:
	set_state(&"patrolling")
	
	if current_path.is_empty() or path_index >= current_path.size():
		# Pick a random reachable point
		var patrol_target := GameManager.get_random_walkable_position()
		navigate_to(patrol_target)
	
	follow_path(context.delta)
	
	# Check for newly visible targets
	var visible_enemies := _perception.get_visible_targets()
	if visible_enemies.size() > 0:
		current_target = visible_enemies[0]
		target_acquired.emit(current_target)
		return BehaviorTreeNode.FAILURE  # Fall through to pursue
	
	return BehaviorTreeNode.RUNNING


## Returns health as a ratio [0-1].
func get_health_ratio() -> float:
	return health / max_health

## Returns true if agent is alive.
func is_alive() -> bool:
	return health > 0.0

## Returns distance to current target, INF if none.
func get_target_distance() -> float:
	if current_target and is_instance_valid(current_target):
		return global_position.distance_to(current_target.global_position)
	return INF


## Heal by amount, clamped to max_health.
func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)

## Stun for duration seconds.
func stun(duration: float) -> void:
	set_state(&"stunned")
	await get_tree().create_timer(duration).timeout
	if is_alive() and _current_state == &"stunned":
		set_state(&"idle")
