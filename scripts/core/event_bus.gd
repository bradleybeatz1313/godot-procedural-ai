## event_bus.gd
## Global event bus for decoupled communication between game systems.
## Autoloaded singleton — emit and connect signals from anywhere.

extends Node

# Agent events
signal agent_state_changed(agent: Node2D, old_state: StringName, new_state: StringName)
signal agent_attacked(attacker: Node2D, target: Node2D, damage: float)
signal agent_damaged(agent: Node2D, amount: float, source: Node2D)
signal agent_died(agent: Node2D)

# Player events
signal player_entered_room(room_index: int)
signal player_health_changed(health: float, max_health: float)
signal player_died

# Dungeon events
signal dungeon_generation_started
signal dungeon_generation_completed(dungeon_data: Resource)
signal room_discovered(room_index: int)

# Item events
signal item_collected(item_data: Dictionary)
signal item_spawned(item_data: Dictionary, position: Vector2)

# AI Director events
signal difficulty_changed(new_difficulty: float)
signal encounter_spawned(type: StringName, position: Vector2)
signal calm_period_started(duration: float)
signal calm_period_ended

# Debug / Metrics
signal metric_logged(category: String, key: String, value: Variant)


## Emitted when the dungeon is fully generated and navigation mesh is ready.
signal dungeon_ready(dungeon_data)

## Emitted when an agent picks up an item.
signal item_collected(agent, item_type)

## Emitted each wave start.
signal wave_started(wave_number: int)
