## dungeon_data.gd
## Data container for generated dungeon output.
## Passed between generation, rendering, and AI systems.

class_name DungeonData
extends Resource

@export var grid: Array[Array] = []
@export var rooms: Array[Rect2i] = []
@export var corridors: Array[Dictionary] = []
@export var spawn_points: Array[Vector2i] = []
@export var width: int = 0
@export var height: int = 0
@export var tile_size: int = 16
@export var seed: int = 0

func get_room_centers() -> Array[Vector2i]:
	var centers: Array[Vector2i] = []
	for room in rooms:
		centers.append(room.position + room.size / 2)
	return centers

func get_walkable_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(width):
		for y in range(height):
			if grid[x][y] in [1, 3, 5]:  # FLOOR, CORRIDOR, SPAWN
				cells.append(Vector2i(x, y))
	return cells

func to_json() -> String:
	return JSON.stringify({
		"width": width,
		"height": height,
		"tile_size": tile_size,
		"seed": seed,
		"rooms": rooms.map(func(r): return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}),
		"spawn_points": spawn_points.map(func(p): return {"x": p.x, "y": p.y}),
		"room_count": rooms.size(),
		"corridor_count": corridors.size()
	})


## Returns all rooms as an array of Rect2.
func get_rooms() -> Array[Rect2]:
	return _room_list.duplicate()

## Total walkable tile count.
func walkable_tile_count() -> int:
	return _walkable_tiles.size()

## Check if a world position is walkable.
func is_walkable(world_pos: Vector2) -> bool:
	var tile := (world_pos / tile_size).floor()
	return _walkable_tiles.has(tile)
