## game_manager.gd
## Core game state manager. Handles A* navigation graph,
## dungeon state, and global queries.

extends Node

var _astar: AStar2D = AStar2D.new()
var _dungeon_data: DungeonData
var _walkable_cells: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func initialize_navigation(dungeon_data: DungeonData) -> void:
	_dungeon_data = dungeon_data
	_walkable_cells = dungeon_data.get_walkable_cells()
	_build_astar()

func _build_astar() -> void:
	_astar.clear()
	
	var cell_to_id: Dictionary = {}
	var id := 0
	
	# Add points
	for cell in _walkable_cells:
		_astar.add_point(id, Vector2(cell) * _dungeon_data.tile_size)
		cell_to_id[cell] = id
		id += 1
	
	# Connect neighbors (4-directional + diagonal)
	var directions := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	
	for cell in _walkable_cells:
		if not cell_to_id.has(cell):
			continue
		var from_id: int = cell_to_id[cell]
		
		for dir in directions:
			var neighbor := cell + dir
			if cell_to_id.has(neighbor):
				var to_id: int = cell_to_id[neighbor]
				var weight := 1.0 if dir.x == 0 or dir.y == 0 else 1.414
				if not _astar.are_points_connected(from_id, to_id):
					_astar.connect_points(from_id, to_id)

func get_astar() -> AStar2D:
	return _astar

func is_walkable(world_pos: Vector2) -> bool:
	var grid_pos := Vector2i(world_pos / _dungeon_data.tile_size)
	return grid_pos in _walkable_cells

func get_random_walkable_position() -> Vector2:
	if _walkable_cells.is_empty():
		return Vector2.ZERO
	var cell := _walkable_cells[_rng.randi() % _walkable_cells.size()]
	return Vector2(cell) * _dungeon_data.tile_size


## Total agents currently alive in the scene.
static func get_alive_agent_count() -> int:
	var count := 0
	for node in _instance.get_tree().get_nodes_in_group("agents"):
		if node.has_method("is_alive") and node.is_alive():
			count += 1
	return count


## Returns elapsed time since level start in seconds.
static func get_level_time() -> float:
	return _instance._level_timer if _instance else 0.0
