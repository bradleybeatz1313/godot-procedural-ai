## behavior_tree.gd
## Lightweight behavior tree implementation for Godot 4.
## Supports Selector, Sequence, Condition, Action, Decorator, and Parallel nodes.

class_name BehaviorTreeNode
extends RefCounted

const SUCCESS := 0
const FAILURE := 1
const RUNNING := 2

var name: String
var children: Array[BehaviorTreeNode] = []

func _init(node_name: String = ""):
	name = node_name

func add_child(child: BehaviorTreeNode) -> BehaviorTreeNode:
	children.append(child)
	return self

func execute(context: BehaviorContext) -> int:
	return FAILURE


class BehaviorContext extends RefCounted:
	var agent: AIAgent
	var delta: float
	var perception: PerceptionComponent
	var has_target: bool
	var health_ratio: float
	var blackboard: Dictionary = {}


## Selector: tries children in order, succeeds on first success
class SelectorNode extends BehaviorTreeNode:
	func execute(context: BehaviorContext) -> int:
		for child in children:
			var result := child.execute(context)
			if result != FAILURE:
				return result
		return FAILURE


## Sequence: runs children in order, fails on first failure
class SequenceNode extends BehaviorTreeNode:
	func execute(context: BehaviorContext) -> int:
		for child in children:
			var result := child.execute(context)
			if result != SUCCESS:
				return result
		return SUCCESS


## Condition: evaluates a callable, returns SUCCESS or FAILURE
class ConditionNode extends BehaviorTreeNode:
	var _predicate: Callable
	
	func _init(node_name: String, predicate: Callable):
		super(node_name)
		_predicate = predicate
	
	func execute(context: BehaviorContext) -> int:
		return SUCCESS if _predicate.call(context) else FAILURE


## Action: executes a callable that returns SUCCESS/FAILURE/RUNNING
class ActionNode extends BehaviorTreeNode:
	var _action: Callable
	
	func _init(node_name: String, action: Callable):
		super(node_name)
		_action = action
	
	func execute(context: BehaviorContext) -> int:
		return _action.call(context)


## Inverter: flips SUCCESS/FAILURE, passes RUNNING through
class InverterNode extends BehaviorTreeNode:
	func execute(context: BehaviorContext) -> int:
		if children.is_empty():
			return FAILURE
		var result := children[0].execute(context)
		match result:
			SUCCESS: return FAILURE
			FAILURE: return SUCCESS
			_: return RUNNING


## Repeat: runs child N times or until failure
class RepeatNode extends BehaviorTreeNode:
	var _max_repeats: int
	var _current: int = 0
	
	func _init(node_name: String, repeats: int):
		super(node_name)
		_max_repeats = repeats
	
	func execute(context: BehaviorContext) -> int:
		if children.is_empty():
			return FAILURE
		
		while _current < _max_repeats:
			var result := children[0].execute(context)
			if result == FAILURE:
				_current = 0
				return FAILURE
			if result == RUNNING:
				return RUNNING
			_current += 1
		
		_current = 0
		return SUCCESS


## Parallel: runs all children simultaneously
## Succeeds when success_threshold children succeed
## Fails when enough children fail that threshold is unreachable
class ParallelNode extends BehaviorTreeNode:
	var _success_threshold: int
	
	func _init(node_name: String, threshold: int = -1):
		super(node_name)
		_success_threshold = threshold
	
	func execute(context: BehaviorContext) -> int:
		if _success_threshold < 0:
			_success_threshold = children.size()
		
		var successes := 0
		var failures := 0
		
		for child in children:
			var result := child.execute(context)
			match result:
				SUCCESS: successes += 1
				FAILURE: failures += 1
		
		if successes >= _success_threshold:
			return SUCCESS
		if failures > children.size() - _success_threshold:
			return FAILURE
		return RUNNING
