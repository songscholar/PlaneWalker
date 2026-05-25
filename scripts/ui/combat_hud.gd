extends CanvasLayer

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")

@export var player_path: NodePath

@onready var player: Node = get_node(player_path)
@onready var health: Node = player.get_node("HealthComponent")
@onready var time_manager: Node = player.get_node("TimeManager")
@onready var label: Label = $StatusLabel
@onready var build_label: Label = $BuildLabel
@onready var hp_bar: ProgressBar = $PlayerPanel/VBox/HPBar
@onready var time_bar: ProgressBar = $PlayerPanel/VBox/TimeBar
@onready var room_banner: Label = $RoomBanner
@onready var boss_panel: PanelContainer = $BossPanel
@onready var boss_name_label: Label = $BossPanel/VBox/BossName
@onready var boss_hp_bar: ProgressBar = $BossPanel/VBox/BossHPBar

var _boss: Node
var _banner_timer: float = 0.0


func _ready() -> void:
	boss_panel.visible = false
	room_banner.visible = false
	EventBus.room_started.connect(_on_room_started)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.reward_selected.connect(_on_reward_selected)
	EventBus.run_ended.connect(_on_run_ended)
	_update_build_label()


func _process(delta: float) -> void:
	_update_player_status()
	_update_boss_status()
	_update_banner(delta)


func _update_player_status() -> void:
	hp_bar.max_value = health.max_hp
	hp_bar.value = health.current_hp
	time_bar.max_value = time_manager.max_energy
	time_bar.value = time_manager.energy
	label.text = "Room %d/5 | HP %.0f/%.0f | Time %.0f/%.0f | Stop %.1f | Rewind %.1f | Rift %.1f" % [
		GameState.current_room,
		health.current_hp,
		health.max_hp,
		time_manager.energy,
		time_manager.max_energy,
		time_manager.get_cooldown(&"time_stop"),
		time_manager.get_cooldown(&"time_rewind"),
		time_manager.get_cooldown(&"time_rift"),
	]
	_update_build_label()


func _update_build_label() -> void:
	var archetype := GameState.get_dominant_archetype()
	if archetype.is_empty():
		build_label.text = "Build: Unformed"
	else:
		build_label.text = "Build: %s" % RewardPoolScript.get_archetype_label(archetype)


func _update_boss_status() -> void:
	if _boss == null or not is_instance_valid(_boss):
		boss_panel.visible = false
		return
	var boss_health: Node = _boss.get_node_or_null("HealthComponent")
	if boss_health == null:
		boss_panel.visible = false
		return
	boss_panel.visible = boss_health.is_alive()
	boss_hp_bar.max_value = boss_health.max_hp
	boss_hp_bar.value = boss_health.current_hp


func _update_banner(delta: float) -> void:
	if _banner_timer <= 0.0:
		room_banner.visible = false
		return
	_banner_timer = maxf(0.0, _banner_timer - delta)
	room_banner.visible = true


func _show_banner(text: String, duration: float = 1.6) -> void:
	room_banner.text = text
	_banner_timer = duration
	room_banner.visible = true


func _on_room_started(room_id: StringName) -> void:
	_boss = null
	boss_panel.visible = false
	if GameState.current_room >= 5:
		_show_banner("Boss Room")
	else:
		_show_banner("Room %d" % GameState.current_room)


func _on_room_cleared(_room_id: StringName) -> void:
	_show_banner("Room Cleared")


func _on_enemy_spawned(enemy: Node) -> void:
	call_deferred("_try_track_boss", enemy)


func _on_reward_selected(_reward: Dictionary) -> void:
	_update_build_label()


func _try_track_boss(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.is_in_group("bosses"):
		_boss = enemy
		boss_name_label.text = "Chrono Warden"
		boss_panel.visible = true
		_show_banner("Chrono Warden")


func _on_run_ended(result: Dictionary) -> void:
	boss_panel.visible = false
	var outcome := str(result.get("result", ""))
	_show_banner("Floor Cleared" if outcome == "floor_cleared" else "Run Failed", 3.0)
