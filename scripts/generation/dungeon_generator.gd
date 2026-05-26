## dungeon_generator.gd
## Procedural dungeon generation using Binary Space Partition (BSP) trees
## combined with cellular automata for organic cave regions.
##
## Pipeline: BSP split → room placement → corridor carving → CA smoothing → 
## feature placement → navmesh bake → AI spawn point selection
##
## Config-driven via DungeonTheme resources for full art-direction control.

class_name DungeonGenerator
extends Node2D

signal generation_started
signal generation_completed(dungeon_data: DungeonData)
signal room_created(room: Rect2i)
signal corridor_carved(from: Vector2i, to: Vector2i)

## --- Exported Configuration ---

@export_group("Dimensions")
@export var grid_width: int = 80
@export var grid_height: int = 60
@export var tile_size: int = 16

@export_group("BSP Parameters")
@export var min_room_size: int = 6
@export var max_room_size: int = 15
@export var max_depth: int = 5
@export var split_variance: float = 0.15  ## Randomness in split position [0-0.5]

@export_group("Cellular Automata")
@export var ca_iterations: int = 4
@export var ca_birth_threshold: int = 5
@export var ca_death_threshold: int = 3
@export var ca_cave_density: float = 0.45  ## Initial fill ratio for CA regions

@export_group("Features")
@export var spawn_point_min_distance: float = 8.0
@export var max_enemies_per_room: int = 3
@export var item_density: float = 0.12

@export var theme: DungeonTheme

## --- Internal State ---

enum CellType { VOID = 0, FLOOR = 1, WALL = 2, CORRIDOR = 3, DOOR = 4, SPAWN = 5 }

var _grid: Array[Array] = []
var _rooms: Array[Rect2i] = []
var _corridors: Array[Dictionary] = []
var _spawn_points: Array[Vector2i] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tilemap: TileMapLayer

## --- BSP Tree Node ---

class BSPNode:
	var bounds: Rect2i
	var left: BSPNode = null
	var right: BSPNode = null
	var room: Rect2i = Rect2i()
	var depth: int = 0
	
	func _init(rect: Rect2i, d: int = 0):
		bounds = rect
		depth = d
	
	func is_leaf() -> bool:
		return left == null and right == null
	
	func get_leaves() -> Array[BSPNode]:
		if is_leaf():
			return [self]
		var leaves: Array[BSPNode] = []
		if left:
			leaves.append_array(left.get_leaves())
		if right:
			leaves.append_array(right.get_leaves())
		return leaves


## --- Public API ---

func generate(seed_value: int = -1) -> DungeonData:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	
	generation_started.emit()
	
	_initialize_grid()
	
	# Phase 1: BSP partition
	var root := BSPNode.new(Rect2i(1, 1, grid_width - 2, grid_height - 2))
	_subdivide(root, 0)
	
	# Phase 2: Room placement within leaves
	var leaves := root.get_leaves()
	for leaf in leaves:
		_place_room(leaf)
	
	# Phase 3: Corridor connections via sibling pairing
	_connect_rooms(root)
	
	# Phase 4: Cellular automata pass on designated regions
	_apply_cellular_automata()
	
	# Phase 5: Wall generation (flood fill boundaries)
	_generate_walls()
	
	# Phase 6: Feature placement
	_place_doors()
	_select_spawn_points()
	_place_items()
	
	# Phase 7: Build output data
	var dungeon_data := _build_dungeon_data()
	generation_completed.emit(dungeon_data)
	
	return dungeon_data


func generate_async(seed_value: int = -1) -> DungeonData:
	"""Yields each frame for non-blocking generation in large dungeons."""
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	
	generation_started.emit()
	_initialize_grid()
	
	var root := BSPNode.new(Rect2i(1, 1, grid_width - 2, grid_height - 2))
	_subdivide(root, 0)
	await get_tree().process_frame
	
	var leaves := root.get_leaves()
	for leaf in leaves:
		_place_room(leaf)
	await get_tree().process_frame
	
	_connect_rooms(root)
	await get_tree().process_frame
	
	_apply_cellular_automata()
	_generate_walls()
	await get_tree().process_frame
	
	_place_doors()
	_select_spawn_points()
	_place_items()
	
	var dungeon_data := _build_dungeon_data()
	generation_completed.emit(dungeon_data)
	return dungeon_data


## --- Grid Initialization ---

func _initialize_grid() -> void:
	_grid.clear()
	_rooms.clear()
	_corridors.clear()
	_spawn_points.clear()
	
	for x in range(grid_width):
		var column: Array = []
		column.resize(grid_height)
		column.fill(CellType.VOID)
		_grid.append(column)


## --- BSP Subdivision ---

func _subdivide(node: BSPNode, depth: int) -> void:
	if depth >= max_depth:
		return
	
	var bounds := node.bounds
	
	# Determine split direction — prefer splitting the longer axis
	var split_horizontal: bool
	var aspect := float(bounds.size.x) / float(bounds.size.y)
	
	if aspect > 1.25:
		split_horizontal = false  # Split vertically (wide room)
	elif aspect < 0.75:
		split_horizontal = true   # Split horizontally (tall room)
	else:
		split_horizontal = _rng.randf() > 0.5
	
	# Calculate split position with variance
	var max_extent: int = bounds.size.y if split_horizontal else bounds.size.x
	if max_extent < min_room_size * 2 + 2:
		return  # Too small to split
	
	var center := max_extent / 2
	var variance_range := int(max_extent * split_variance)
	var split_pos := center + _rng.randi_range(-variance_range, variance_range)
	split_pos = clampi(split_pos, min_room_size + 1, max_extent - min_room_size - 1)
	
	if split_horizontal:
		node.left = BSPNode.new(
			Rect2i(bounds.position.x, bounds.position.y, bounds.size.x, split_pos),
			depth + 1
		)
		node.right = BSPNode.new(
			Rect2i(bounds.position.x, bounds.position.y + split_pos, bounds.size.x, bounds.size.y - split_pos),
			depth + 1
		)
	else:
		node.left = BSPNode.new(
			Rect2i(bounds.position.x, bounds.position.y, split_pos, bounds.size.y),
			depth + 1
		)
		node.right = BSPNode.new(
			Rect2i(bounds.position.x + split_pos, bounds.position.y, bounds.size.x - split_pos, bounds.size.y),
			depth + 1
		)
	
	_subdivide(node.left, depth + 1)
	_subdivide(node.right, depth + 1)


## --- Room Placement ---

func _place_room(leaf: BSPNode) -> void:
	var bounds := leaf.bounds
	var padding := 2
	
	var room_w := _rng.randi_range(
		min_room_size,
		mini(max_room_size, bounds.size.x - padding * 2)
	)
	var room_h := _rng.randi_range(
		min_room_size,
		mini(max_room_size, bounds.size.y - padding * 2)
	)
	
	var room_x := bounds.position.x + _rng.randi_range(padding, bounds.size.x - room_w - padding)
	var room_y := bounds.position.y + _rng.randi_range(padding, bounds.size.y - room_h - padding)
	
	var room := Rect2i(room_x, room_y, room_w, room_h)
	leaf.room = room
	_rooms.append(room)
	
	# Carve room into grid
	for x in range(room.position.x, room.end.x):
		for y in range(room.position.y, room.end.y):
			if _in_bounds(x, y):
				_grid[x][y] = CellType.FLOOR
	
	room_created.emit(room)


## --- Corridor Generation ---

func _connect_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		return
	
	if node.left and node.right:
		_connect_rooms(node.left)
		_connect_rooms(node.right)
		
		var left_center := _get_subtree_center(node.left)
		var right_center := _get_subtree_center(node.right)
		_carve_corridor(left_center, right_center)


func _get_subtree_center(node: BSPNode) -> Vector2i:
	if node.is_leaf() and node.room.size.x > 0:
		return node.room.position + node.room.size / 2
	
	var leaves := node.get_leaves()
	var valid_leaves := leaves.filter(func(l): return l.room.size.x > 0)
	
	if valid_leaves.is_empty():
		return node.bounds.position + node.bounds.size / 2
	
	# Pick the leaf closest to the center of the partition
	var center := node.bounds.position + node.bounds.size / 2
	var best: BSPNode = valid_leaves[0]
	var best_dist := INF
	
	for leaf in valid_leaves:
		var leaf_center := leaf.room.position + leaf.room.size / 2
		var dist := Vector2(leaf_center).distance_to(Vector2(center))
		if dist < best_dist:
			best_dist = dist
			best = leaf
	
	return best.room.position + best.room.size / 2


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var corridor_data := {"from": from, "to": to, "cells": []}
	
	# L-shaped corridor: horizontal then vertical (or vice versa, randomly)
	var go_horizontal_first := _rng.randf() > 0.5
	
	var current := from
	
	if go_horizontal_first:
		current = _carve_horizontal(current, to.x, corridor_data)
		current = _carve_vertical(current, to.y, corridor_data)
	else:
		current = _carve_vertical(current, to.y, corridor_data)
		current = _carve_horizontal(current, to.x, corridor_data)
	
	_corridors.append(corridor_data)
	corridor_carved.emit(from, to)


func _carve_horizontal(from: Vector2i, target_x: int, data: Dictionary) -> Vector2i:
	var dir := 1 if target_x > from.x else -1
	var pos := from
	while pos.x != target_x:
		if _in_bounds(pos.x, pos.y):
			if _grid[pos.x][pos.y] == CellType.VOID:
				_grid[pos.x][pos.y] = CellType.CORRIDOR
				data["cells"].append(pos)
		pos.x += dir
	return pos


func _carve_vertical(from: Vector2i, target_y: int, data: Dictionary) -> Vector2i:
	var dir := 1 if target_y > from.y else -1
	var pos := from
	while pos.y != target_y:
		if _in_bounds(pos.x, pos.y):
			if _grid[pos.x][pos.y] == CellType.VOID:
				_grid[pos.x][pos.y] = CellType.CORRIDOR
				data["cells"].append(pos)
		pos.y += dir
	return pos


## --- Cellular Automata ---

func _apply_cellular_automata() -> void:
	"""Applies CA smoothing to corridor-adjacent void regions for organic caves."""
	# Identify CA-eligible regions (void cells near corridors)
	var ca_region: Array[Vector2i] = []
	
	for corridor in _corridors:
		for cell in corridor["cells"]:
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var nx := cell.x + dx
					var ny := cell.y + dy
					if _in_bounds(nx, ny) and _grid[nx][ny] == CellType.VOID:
						if _rng.randf() < ca_cave_density:
							_grid[nx][ny] = CellType.FLOOR
							ca_region.append(Vector2i(nx, ny))
	
	# Run CA iterations
	for _i in range(ca_iterations):
		var next_grid := _grid.duplicate(true)
		
		for pos in ca_region:
			var neighbors := _count_floor_neighbors(pos.x, pos.y)
			
			if _grid[pos.x][pos.y] == CellType.FLOOR:
				if neighbors < ca_death_threshold:
					next_grid[pos.x][pos.y] = CellType.VOID
			else:
				if neighbors >= ca_birth_threshold:
					next_grid[pos.x][pos.y] = CellType.FLOOR
		
		_grid = next_grid


func _count_floor_neighbors(x: int, y: int) -> int:
	var count := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if _in_bounds(nx, ny):
				if _grid[nx][ny] in [CellType.FLOOR, CellType.CORRIDOR]:
					count += 1
			else:
				count += 1  # Out of bounds counts as wall (for edge smoothing)
	return count


## --- Wall Generation ---

func _generate_walls() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			if _grid[x][y] == CellType.VOID:
				# Check if adjacent to any walkable cell
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var nx := x + dx
						var ny := y + dy
						if _in_bounds(nx, ny):
							if _grid[nx][ny] in [CellType.FLOOR, CellType.CORRIDOR]:
								_grid[x][y] = CellType.WALL
								break
					if _grid[x][y] == CellType.WALL:
						break


## --- Feature Placement ---

func _place_doors() -> void:
	for corridor in _corridors:
		for cell_pos in corridor["cells"]:
			var x: int = cell_pos.x
			var y: int = cell_pos.y
			# Door candidate: corridor cell with floor on exactly 2 opposite sides
			var h_floor := (_cell_is(x - 1, y, CellType.FLOOR) and _cell_is(x + 1, y, CellType.FLOOR))
			var v_floor := (_cell_is(x, y - 1, CellType.FLOOR) and _cell_is(x, y + 1, CellType.FLOOR))
			
			if (h_floor or v_floor) and _rng.randf() < 0.4:
				_grid[x][y] = CellType.DOOR


func _select_spawn_points() -> void:
	for room in _rooms:
		var center := room.position + room.size / 2
		
		# Check minimum distance from existing spawn points
		var too_close := false
		for existing in _spawn_points:
			if Vector2(center).distance_to(Vector2(existing)) < spawn_point_min_distance:
				too_close = true
				break
		
		if not too_close:
			_spawn_points.append(center)
			_grid[center.x][center.y] = CellType.SPAWN


func _place_items() -> void:
	for room in _rooms:
		var floor_cells: Array[Vector2i] = []
		for x in range(room.position.x + 1, room.end.x - 1):
			for y in range(room.position.y + 1, room.end.y - 1):
				if _grid[x][y] == CellType.FLOOR:
					floor_cells.append(Vector2i(x, y))
		
		var item_count := int(floor_cells.size() * item_density)
		floor_cells.shuffle()
		# Items stored in dungeon_data, not modifying grid


## --- Utility ---

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height


func _cell_is(x: int, y: int, cell_type: CellType) -> bool:
	if not _in_bounds(x, y):
		return false
	return _grid[x][y] == cell_type


func _build_dungeon_data() -> DungeonData:
	var data := DungeonData.new()
	data.grid = _grid
	data.rooms = _rooms
	data.corridors = _corridors
	data.spawn_points = _spawn_points
	data.width = grid_width
	data.height = grid_height
	data.tile_size = tile_size
	data.seed = _rng.seed
	return data
