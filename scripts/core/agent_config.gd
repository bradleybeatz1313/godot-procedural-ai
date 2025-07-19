## agent_config.gd
## Data-driven agent configuration. Create different enemy types
## by varying these parameters in the editor.

class_name AgentConfig
extends Resource

@export_group("Identity")
@export var agent_name: String = "Enemy"
@export var agent_type: StringName = &"standard"

@export_group("Movement")
@export var move_speed: float = 120.0

@export_group("Combat")
@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_range: float = 32.0

@export_group("Perception")
@export var sight_range: float = 200.0
@export var hearing_range: float = 100.0
@export var fov_angle: float = 120.0

@export_group("Behavior")
@export var aggression: float = 0.5      ## 0=passive, 1=always attacks
@export var flee_threshold: float = 0.2  ## Health ratio to trigger flee
@export var patrol_radius: float = 150.0


## Patrol radius around spawn point (0 = entire dungeon).
@export var patrol_radius: float = 0.0

## Whether agent respawns after death.
@export var respawns: bool = false

## Respawn delay in seconds.
@export var respawn_delay: float = 5.0
