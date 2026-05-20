## ai_director.gd
## Dynamic difficulty and pacing system inspired by L4D's AI Director.
## Monitors player performance metrics in real-time and adjusts enemy
## spawning, item placement, and encounter intensity to maintain
## optimal tension curves.
##
## Autoloaded singleton — access via AIDirector anywhere.

extends Node

signal intensity_changed(new_intensity: float)
signal difficulty_adjusted(new_difficulty: float)
signal encounter_triggered(encounter_type: StringName, position: Vector2)

## --- Tuning Parameters ---

@export_group("Intensity Curve")
@export var target_intensity: float = 0.6       ## Desired average intensity [0-1]
@export var intensity_decay: float = 0.02        ## Per-second decay during calm periods
@export var intensity_spike_threshold: float = 0.8
@export var calm_duration_min: float = 15.0      ## Minimum seconds between peaks
@export var calm_duration_max: float = 30.0

@export_group("Difficulty Scaling")
@export var base_difficulty: float = 1.0
@export var difficulty_ramp_rate: float = 0.005  ## Per-second increase
@export var difficulty_max: float = 3.0
@export var death_penalty: float = -0.3          ## Difficulty reduction on player death
@export var performance_window: float = 60.0     ## Seconds of history to evaluate

@export_group("Spawn Control")
@export var max_active_enemies: int = 12
@export var spawn_check_interval: float = 3.0
@export var min_spawn_distance: float = 300.0    ## From player
@export var max_spawn_distance: float = 600.0

## --- Internal State ---

var current_intensity: float = 0.0
var current_difficulty: float = 1.0
var _active_enemies: Array[AIAgent] = []
var _spawn_timer: float = 0.0
var _calm_timer: float = 0.0
var _calm_duration: float = 20.0
var _in_calm_period: bool = false
var _performance_log: Array[Dictionary] = []  ## {time, event, value}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## --- Performance Metrics (rolling window) ---

var _damage_dealt_window: float = 0.0    ## Damage player dealt in window
var _damage_taken_window: float = 0.0    ## Damage player took in window
var _kills_window: int = 0
var _deaths_window: int = 0
var _items_collected_window: int = 0
var _rooms_explored: int = 0
var _total_rooms: int = 1

## --- Lifecycle ---

func _ready() -> void:
	_rng.randomize()
	_calm_duration = _rng.randf_range(calm_duration_min, calm_duration_max)
	
	# Connect to EventBus signals
	EventBus.agent_died.connect(_on_agent_died)
	EventBus.agent_damaged.connect(_on_agent_damaged)
	EventBus.player_entered_room.connect(_on_room_entered)
	EventBus.item_collected.connect(_on_item_collected)


func _process(delta: float) -> void:
	_update_intensity(delta)
	_update_difficulty(delta)
	_prune_performance_log()
	
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_check_interval
		_evaluate_spawning()


## --- Intensity System ---

func _update_intensity(delta: float) -> void:
	var prev_intensity := current_intensity
	
	if _in_calm_period:
		# Decay intensity during calm
		current_intensity = maxf(0.0, current_intensity - intensity_decay * delta)
		_calm_timer -= delta
		
		if _calm_timer <= 0.0:
			_in_calm_period = false
	else:
		# Calculate intensity from current game state
		var combat_factor := _get_combat_intensity()
		var exploration_factor := float(_rooms_explored) / float(_total_rooms)
		var enemy_pressure := float(_active_enemies.size()) / float(max_active_enemies)
		
		var raw_intensity := (
			combat_factor * 0.5 +
			enemy_pressure * 0.3 +
			(1.0 - exploration_factor) * 0.2
		)
		
		# Smooth intensity changes
		current_intensity = lerpf(current_intensity, raw_intensity, 3.0 * delta)
		
		# Trigger calm period after intensity spike
		if current_intensity > intensity_spike_threshold:
			_in_calm_period = true
			_calm_timer = _rng.randf_range(calm_duration_min, calm_duration_max)
	
	if absf(current_intensity - prev_intensity) > 0.01:
		intensity_changed.emit(current_intensity)


func _get_combat_intensity() -> float:
	"""Computes real-time combat intensity from recent events."""
	var now := Time.get_ticks_msec() / 1000.0
	var recent_window := 10.0  # Last 10 seconds
	
	var recent_damage := 0.0
	var recent_kills := 0
	
	for entry in _performance_log:
		if now - entry["time"] > recent_window:
			continue
		match entry["event"]:
			"damage_dealt":
				recent_damage += entry["value"]
			"kill":
				recent_kills += 1
	
	# Normalize: assume 200 DPS and 3 kills/10s is max intensity
	var dps_factor := clampf(recent_damage / (200.0 * recent_window), 0.0, 1.0)
	var kill_factor := clampf(float(recent_kills) / 3.0, 0.0, 1.0)
	
	return (dps_factor + kill_factor) / 2.0


## --- Difficulty Scaling ---

func _update_difficulty(delta: float) -> void:
	# Baseline ramp
	current_difficulty += difficulty_ramp_rate * delta
	
	# Performance-based adjustment
	var performance := _evaluate_player_performance()
	
	if performance > 0.7:
		# Player is dominating — ramp faster
		current_difficulty += difficulty_ramp_rate * delta * 2.0
	elif performance < 0.3:
		# Player is struggling — slow ramp or reduce
		current_difficulty -= difficulty_ramp_rate * delta * 0.5
	
	current_difficulty = clampf(current_difficulty, 0.5, difficulty_max)


func _evaluate_player_performance() -> float:
	"""Returns 0-1 score. >0.5 = player performing well, <0.5 = struggling."""
	if _performance_log.is_empty():
		return 0.5
	
	var kill_death_ratio := 1.0
	if _deaths_window > 0:
		kill_death_ratio = float(_kills_window) / float(_deaths_window)
	elif _kills_window > 0:
		kill_death_ratio = float(_kills_window) * 2.0
	
	var damage_ratio := 1.0
	if _damage_taken_window > 0:
		damage_ratio = _damage_dealt_window / _damage_taken_window
	
	var kd_score := clampf(kill_death_ratio / 3.0, 0.0, 1.0)
	var dmg_score := clampf(damage_ratio / 4.0, 0.0, 1.0)
	
	return (kd_score + dmg_score) / 2.0


## --- Spawn Control ---

func _evaluate_spawning() -> void:
	# Clean up dead/freed enemy references
	_active_enemies = _active_enemies.filter(func(e): return is_instance_valid(e) and e.health > 0)
	
	if _in_calm_period:
		return
	
	if _active_enemies.size() >= max_active_enemies:
		return
	
	# Determine how many to spawn based on difficulty and intensity gap
	var intensity_gap := target_intensity - current_intensity
	if intensity_gap <= 0:
		return  # Already at or above target
	
	var spawn_count := ceili(intensity_gap * current_difficulty * 3.0)
	spawn_count = clampi(spawn_count, 0, max_active_enemies - _active_enemies.size())
	
	if spawn_count <= 0:
		return
	
	var player := _get_player()
	if not player:
		return
	
	# Select spawn points outside player view but within range
	var spawn_points := _get_valid_spawn_points(player.global_position, spawn_count)
	
	for point in spawn_points:
		var encounter_type := _select_encounter_type()
		encounter_triggered.emit(encounter_type, point)


func _select_encounter_type() -> StringName:
	"""Selects encounter type weighted by current difficulty."""
	var roll := _rng.randf()
	
	if current_difficulty > 2.5 and roll < 0.2:
		return &"elite"
	elif current_difficulty > 1.5 and roll < 0.4:
		return &"pack"  # Group of 3-4
	elif roll < 0.7:
		return &"standard"
	else:
		return &"ambush"  # Spawns behind player


func _get_valid_spawn_points(player_pos: Vector2, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var attempts := 0
	
	while points.size() < count and attempts < 50:
		attempts += 1
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(min_spawn_distance, max_spawn_distance)
		var candidate := player_pos + Vector2.from_angle(angle) * dist
		
		# Validate: must be on walkable tile and not visible to player
		if GameManager.is_walkable(candidate) and not _is_visible_to_player(candidate, player_pos):
			points.append(candidate)
	
	return points


func _is_visible_to_player(point: Vector2, player_pos: Vector2) -> bool:
	var space_state := get_tree().root.world_2d.direct_space_state
	if not space_state:
		return false
	
	var query := PhysicsRayQueryParameters2D.create(player_pos, point, 1)  # Wall layer
	var result := space_state.intersect_ray(query)
	return result.is_empty()  # Empty = no wall between = visible


## --- Event Handlers ---

func _on_agent_died(agent: AIAgent) -> void:
	_active_enemies.erase(agent)
	_kills_window += 1
	_log_event("kill", 1.0)


func _on_agent_damaged(agent: Node2D, amount: float, attacker: Node2D) -> void:
	if agent is AIAgent:
		_damage_dealt_window += amount
		_log_event("damage_dealt", amount)
	else:
		# Player took damage
		_damage_taken_window += amount
		_log_event("damage_taken", amount)


func _on_room_entered(_room_index: int) -> void:
	_rooms_explored += 1
	_log_event("room_explored", 1.0)


func _on_item_collected(_item_data: Dictionary) -> void:
	_items_collected_window += 1
	_log_event("item_collected", 1.0)


## --- Utility ---

func _log_event(event_name: String, value: float) -> void:
	_performance_log.append({
		"time": Time.get_ticks_msec() / 1000.0,
		"event": event_name,
		"value": value
	})


func _prune_performance_log() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_performance_log = _performance_log.filter(func(e): return now - e["time"] < performance_window)


func _get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null


func register_enemy(enemy: AIAgent) -> void:
	_active_enemies.append(enemy)


func set_total_rooms(count: int) -> void:
	_total_rooms = maxi(count, 1)


func get_stats() -> Dictionary:
	return {
		"intensity": current_intensity,
		"difficulty": current_difficulty,
		"active_enemies": _active_enemies.size(),
		"kills": _kills_window,
		"performance": _evaluate_player_performance(),
		"in_calm": _in_calm_period,
	}


## Returns current threat level as a normalized float [0-1].
func get_threat_level() -> float:
	return clampf(_current_threat / _max_threat, 0.0, 1.0)

## Force-set the difficulty tier (0=easy 1=normal 2=hard 3=brutal).
func set_difficulty(tier: int) -> void:
	_difficulty_tier = clampi(tier, 0, 3)
	_recalculate_spawn_rates()

## Returns true if the director is currently in an active spawn wave.
func is_wave_active() -> bool:
	return _wave_active

## Returns the index of the current wave (0-based).
func get_wave_index() -> int:
	return _wave_index
