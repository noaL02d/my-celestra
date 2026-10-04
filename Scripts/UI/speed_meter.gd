extends CanvasLayer

## 右上角的调试用速度表：分别显示 X / Y 轴带方向的速度，以及整体速度（合成速度）。
## 不需要的时候，把 SpeedMeter 节点隐藏或删掉即可。

## 要监视的角色。留空就会自动在当前场景里找第一个 CharacterBody2D。
@export var player_path: NodePath

@onready var label: Label = $Label

var player: CharacterBody2D

func _ready() -> void:
	if player_path != NodePath():
		player = get_node_or_null(player_path) as CharacterBody2D
	if player == null:
		player = _find_player(get_tree().current_scene)

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var v := player.velocity
	# %+7.1f 会带上正负号，方便看出方向
	label.text = "X %+7.1f   Y %+7.1f\n速度 %6.1f px/s" % [v.x, v.y, v.length()]

## 在场景里递归查找第一个 CharacterBody2D（也就是玩家）。
func _find_player(node: Node) -> CharacterBody2D:
	if node == null:
		return null
	if node is CharacterBody2D:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
