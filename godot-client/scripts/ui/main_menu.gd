## Main menu screen with dark fantasy theme.
##
## Shows the game title, menu buttons, and server connection status.
## Builds its entire UI tree programmatically so it has no .tscn dependency.
class_name MainMenu
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal new_game_requested
signal continue_requested
signal settings_requested
signal upgrade_shop_opened

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color("#140f1a")
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_TITLE := Color("#ebca42")
const COLOR_SUBTITLE := Color(0.6, 0.55, 0.75, 1.0)
const COLOR_BUTTON_BG := Color(0.12, 0.1, 0.16, 0.9)
const COLOR_BUTTON_HOVER := Color(0.2, 0.16, 0.24, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.08, 0.06, 0.1, 1.0)
const COLOR_BUTTON_DISABLED := Color(0.15, 0.13, 0.18, 0.6)
const COLOR_BUTTON_BORDER := Color(0.72, 0.58, 0.2, 0.6)
const COLOR_SERVER_OK := Color(0.3, 0.75, 0.35, 1.0)
const COLOR_SERVER_FAIL := Color(0.8, 0.25, 0.25, 1.0)
const COLOR_PARTICLE := Color(0.72, 0.58, 0.2, 0.15)
const COLOR_VERSION := Color(0.5, 0.48, 0.45, 0.5)

# ── Particle Configuration ───────────────────────────────────────────────────

const PARTICLE_COUNT: int = 30
const PARTICLE_SPEED_MIN: float = 15.0
const PARTICLE_SPEED_MAX: float = 40.0

# ── State ────────────────────────────────────────────────────────────────────

var _has_save: bool = false
var _particles: Array[Dictionary] = []

# ── UI Node References ───────────────────────────────────────────────────────

var _bg: ColorRect
var _particle_canvas: Control
var _title_label: Label
var _subtitle_label: Label
var _new_game_btn: Button
var _continue_btn: Button
var _upgrade_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _server_status_label: Label
var _version_label: Label

# Upgrade shop overlay.
var _upgrade_overlay: ColorRect
var _upgrade_panel: PanelContainer
var _upgrade_gold_label: Label
var _upgrade_buttons: Dictionary = {}
var _upgrade_level_labels: Dictionary = {}

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	_check_save_exists()
	_check_server_health()
	visible = true


func _process(delta: float) -> void:
	_update_particles(delta)


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark background.
	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.color = COLOR_BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Particle canvas (falling dots effect).
	_particle_canvas = Control.new()
	_particle_canvas.name = "ParticleCanvas"
	_particle_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_particle_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_particle_canvas)
	_init_particles()

	# Main content container.
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(main_vbox)

	# Spacer above title.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 40)
	main_vbox.add_child(top_spacer)

	# Game title.
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "심연의 강림"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 52)
	_title_label.add_theme_color_override("font_color", COLOR_TITLE)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_title_label)

	# English subtitle.
	var english_title := Label.new()
	english_title.text = "Abyssal Descent"
	english_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	english_title.add_theme_font_size_override("font_size", 18)
	english_title.add_theme_color_override("font_color", Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.6))
	english_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(english_title)

	# Subtitle.
	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = "AI 던전 마스터"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	_subtitle_label.add_theme_color_override("font_color", COLOR_SUBTITLE)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_subtitle_label)

	# Spacer between title and buttons.
	var mid_spacer := Control.new()
	mid_spacer.custom_minimum_size = Vector2(0, 40)
	main_vbox.add_child(mid_spacer)

	# Menu buttons.
	_new_game_btn = _create_menu_button("새 게임 시작")
	_new_game_btn.name = "NewGameButton"
	main_vbox.add_child(_new_game_btn)

	_continue_btn = _create_menu_button("이어하기")
	_continue_btn.name = "ContinueButton"
	main_vbox.add_child(_continue_btn)

	_upgrade_btn = _create_menu_button("영구 강화")
	_upgrade_btn.name = "UpgradeButton"
	main_vbox.add_child(_upgrade_btn)

	_settings_btn = _create_menu_button("설정")
	_settings_btn.name = "SettingsButton"
	main_vbox.add_child(_settings_btn)

	_quit_btn = _create_menu_button("종료")
	_quit_btn.name = "QuitButton"
	main_vbox.add_child(_quit_btn)

	# Spacer below buttons.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 60)
	main_vbox.add_child(bottom_spacer)

	# Server status indicator (bottom-center).
	_server_status_label = Label.new()
	_server_status_label.name = "ServerStatusLabel"
	_server_status_label.text = "AI 서버: 확인 중..."
	_server_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_server_status_label.add_theme_font_size_override("font_size", 13)
	_server_status_label.add_theme_color_override("font_color", COLOR_SUBTITLE)

	# Anchor to bottom-center.
	_server_status_label.anchor_left = 0.0
	_server_status_label.anchor_right = 1.0
	_server_status_label.anchor_top = 1.0
	_server_status_label.anchor_bottom = 1.0
	_server_status_label.offset_top = -50.0
	_server_status_label.offset_bottom = -30.0
	_server_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_server_status_label)

	# Version text (bottom-right).
	_version_label = Label.new()
	_version_label.name = "VersionLabel"
	_version_label.text = "v0.1.0-alpha"
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_label.add_theme_font_size_override("font_size", 11)
	_version_label.add_theme_color_override("font_color", COLOR_VERSION)

	_version_label.anchor_left = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -160.0
	_version_label.offset_right = -16.0
	_version_label.offset_top = -30.0
	_version_label.offset_bottom = -10.0
	_version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_version_label)


# ── Particle System ──────────────────────────────────────────────────────────

func _init_particles() -> void:
	_particles.clear()
	for i in range(PARTICLE_COUNT):
		var p: Dictionary = {
			"node": _create_particle_dot(),
			"x": randf() * 1920.0,
			"y": randf() * 1080.0,
			"speed": randf_range(PARTICLE_SPEED_MIN, PARTICLE_SPEED_MAX),
			"alpha": randf_range(0.05, 0.2),
			"size": randf_range(2.0, 6.0),
		}
		_particles.append(p)


func _create_particle_dot() -> ColorRect:
	var dot := ColorRect.new()
	dot.color = COLOR_PARTICLE
	dot.custom_minimum_size = Vector2(4, 4)
	dot.size = Vector2(4, 4)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_particle_canvas.add_child(dot)
	return dot


func _update_particles(delta: float) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1920, 1080)

	for p in _particles:
		p["y"] += p["speed"] * delta
		# Subtle horizontal drift.
		p["x"] += sin(p["y"] * 0.01) * 10.0 * delta

		# Wrap around when off-screen.
		if p["y"] > viewport_size.y + 10.0:
			p["y"] = -10.0
			p["x"] = randf() * viewport_size.x

		if p["x"] < -10.0:
			p["x"] = viewport_size.x + 10.0
		elif p["x"] > viewport_size.x + 10.0:
			p["x"] = -10.0

		var node: ColorRect = p["node"]
		node.position = Vector2(p["x"], p["y"])
		node.size = Vector2(p["size"], p["size"])
		node.color = Color(COLOR_PARTICLE.r, COLOR_PARTICLE.g, COLOR_PARTICLE.b, p["alpha"])


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_new_game_btn.pressed.connect(_on_new_game)
	_continue_btn.pressed.connect(_on_continue)
	_upgrade_btn.pressed.connect(_on_upgrade)
	_settings_btn.pressed.connect(_on_settings)
	_quit_btn.pressed.connect(_on_quit)

	# Connect to AIClient health check result.
	call_deferred("_deferred_connect_ai")


func _deferred_connect_ai() -> void:
	var ai_client := _get_autoload("AIClient")
	if ai_client != null and ai_client.has_signal("server_health_checked"):
		ai_client.server_health_checked.connect(_on_health_result)


# ── Button Handlers ──────────────────────────────────────────────────────────

func _on_new_game() -> void:
	new_game_requested.emit()


func _on_continue() -> void:
	if _has_save:
		continue_requested.emit()


func _on_settings() -> void:
	settings_requested.emit()


func _on_upgrade() -> void:
	_show_upgrade_shop()


func _on_quit() -> void:
	get_tree().quit()


# ── Upgrade Shop ────────────────────────────────────────────────────────────

func _show_upgrade_shop() -> void:
	if _upgrade_overlay == null:
		_build_upgrade_shop()
	_refresh_upgrade_shop()
	_upgrade_overlay.visible = true


func _build_upgrade_shop() -> void:
	_upgrade_overlay = ColorRect.new()
	_upgrade_overlay.name = "UpgradeOverlay"
	_upgrade_overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	_upgrade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_upgrade_overlay.visible = false
	add_child(_upgrade_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upgrade_overlay.add_child(center)

	_upgrade_panel = PanelContainer.new()
	_upgrade_panel.custom_minimum_size = Vector2(440, 360)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.04, 0.08, 0.95)
	panel_style.border_color = COLOR_ACCENT
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	_apply_corner_radius(panel_style, 8)
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	_upgrade_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_upgrade_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_upgrade_panel.add_child(vbox)

	# Header.
	var header := Label.new()
	header.text = "── 영구 강화 ──"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(header)

	var desc := Label.new()
	desc.text = "사망 시 보존된 골드로 능력을 영구 강화합니다.\n강화 효과는 모든 런에 적용됩니다."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5, 1.0))
	vbox.add_child(desc)

	# Gold display.
	_upgrade_gold_label = Label.new()
	_upgrade_gold_label.text = "보유 골드: 0"
	_upgrade_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_gold_label.add_theme_font_size_override("font_size", 18)
	_upgrade_gold_label.add_theme_color_override("font_color", Color("#FFD700"))
	vbox.add_child(_upgrade_gold_label)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Upgrade rows.
	_build_upgrade_row(vbox, "atk", "공격력", "매 레벨 +2 ATK")
	_build_upgrade_row(vbox, "def", "방어력", "매 레벨 +1.5 DEF")
	_build_upgrade_row(vbox, "hp", "체력", "매 레벨 +10 HP")

	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 4)
	vbox.add_child(sep2)

	# Close button.
	var close_btn := _create_menu_button("닫기")
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.pressed.connect(func() -> void: _upgrade_overlay.visible = false)
	var close_center := CenterContainer.new()
	close_center.add_child(close_btn)
	vbox.add_child(close_center)


func _build_upgrade_row(parent: VBoxContainer, stat_key: String, label_text: String, bonus_text: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", COLOR_TEXT)
	info_vbox.add_child(name_lbl)

	var bonus_lbl := Label.new()
	bonus_lbl.text = bonus_text
	bonus_lbl.add_theme_font_size_override("font_size", 11)
	bonus_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 1.0))
	info_vbox.add_child(bonus_lbl)

	var level_lbl := Label.new()
	level_lbl.text = "Lv.0"
	level_lbl.add_theme_font_size_override("font_size", 12)
	level_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1.0))
	info_vbox.add_child(level_lbl)
	_upgrade_level_labels[stat_key] = level_lbl

	hbox.add_child(info_vbox)

	var btn := Button.new()
	btn.name = "UpgradeBtn_%s" % stat_key
	btn.text = "강화 (0G)"
	btn.custom_minimum_size = Vector2(140, 40)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.1, 0.16, 0.9)
	btn_style.border_color = Color(0.72, 0.58, 0.2, 0.5)
	btn_style.border_width_top = 1
	btn_style.border_width_bottom = 1
	btn_style.border_width_left = 1
	btn_style.border_width_right = 1
	_apply_corner_radius(btn_style, 4)
	btn.add_theme_stylebox_override("normal", btn_style)

	var hover_style := btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.2, 0.16, 0.24, 1.0)
	hover_style.border_color = COLOR_ACCENT
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.pressed.connect(_on_upgrade_buy.bind(stat_key))
	hbox.add_child(btn)
	_upgrade_buttons[stat_key] = btn

	parent.add_child(hbox)


func _on_upgrade_buy(stat_key: String) -> void:
	var game_mgr := _get_autoload("GameManager")
	if game_mgr == null or not game_mgr.has_method("buy_upgrade"):
		return
	if game_mgr.buy_upgrade(stat_key):
		var sound_mgr := _get_autoload("SoundManager")
		if sound_mgr != null and sound_mgr.has_method("play_sfx"):
			sound_mgr.play_sfx("gold_pickup")
		_refresh_upgrade_shop()
		# Update main menu button text too.
		_upgrade_btn.text = "영구 강화 (%dG)" % game_mgr.permanent_gold


func _refresh_upgrade_shop() -> void:
	var game_mgr := _get_autoload("GameManager")
	if game_mgr == null:
		return
	_upgrade_gold_label.text = "보유 골드: %d" % game_mgr.permanent_gold
	for stat_key in ["atk", "def", "hp"]:
		if not _upgrade_buttons.has(stat_key):
			continue
		var cost: int = game_mgr.get_upgrade_cost(stat_key)
		var level: int = 0
		match stat_key:
			"atk": level = game_mgr.upgrade_atk
			"def": level = game_mgr.upgrade_def
			"hp": level = game_mgr.upgrade_hp
		var btn: Button = _upgrade_buttons[stat_key]
		btn.text = "강화 (%dG)" % cost
		btn.disabled = game_mgr.permanent_gold < cost
		if _upgrade_level_labels.has(stat_key):
			_upgrade_level_labels[stat_key].text = "Lv.%d" % level


# ── Server Health ────────────────────────────────────────────────────────────

func _check_server_health() -> void:
	_server_status_label.text = "AI 서버: 확인 중..."
	_server_status_label.add_theme_color_override("font_color", COLOR_SUBTITLE)

	var ai_client := _get_autoload("AIClient")
	if ai_client != null and ai_client.has_method("check_health"):
		ai_client.check_health()
	else:
		_server_status_label.text = "AI 서버: 클라이언트 없음"
		_server_status_label.add_theme_color_override("font_color", COLOR_SERVER_FAIL)


func _on_health_result(is_healthy: bool) -> void:
	if is_healthy:
		var ai_client := _get_autoload("AIClient")
		var has_key: bool = false
		if ai_client != null and ai_client.get("config") != null:
			has_key = not ai_client.config.api_key.is_empty()
		var key_info: String = " (API 키 설정됨)" if has_key else ""
		_server_status_label.text = "AI 서버: 연결됨 ✓%s" % key_info
		_server_status_label.add_theme_color_override("font_color", COLOR_SERVER_OK)
	else:
		_server_status_label.text = "AI 서버: 오프라인 — 오프라인 모드"
		_server_status_label.add_theme_color_override("font_color", COLOR_SERVER_FAIL)


# ── Save Detection ───────────────────────────────────────────────────────────

func _check_save_exists() -> void:
	_has_save = FileAccess.file_exists("user://game_save.json")
	_continue_btn.disabled = not _has_save

	if not _has_save:
		_continue_btn.add_theme_color_override("font_color", Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0.3))

	# Update upgrade button with current permanent gold.
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		var perm_gold: int = game_mgr.get("permanent_gold") if "permanent_gold" in game_mgr else 0
		_upgrade_btn.text = "영구 강화 (%dG)" % perm_gold


# ── Button Factory ───────────────────────────────────────────────────────────

func _create_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_BUTTON_BG
	normal_style.border_color = COLOR_BUTTON_BORDER
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	_apply_corner_radius(normal_style, 6)
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_BUTTON_HOVER
	hover_style.border_color = COLOR_ACCENT
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = COLOR_BUTTON_PRESSED
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style := normal_style.duplicate() as StyleBoxFlat
	disabled_style.bg_color = COLOR_BUTTON_DISABLED
	disabled_style.border_color = Color(COLOR_BUTTON_BORDER.r, COLOR_BUTTON_BORDER.g, COLOR_BUTTON_BORDER.b, 0.2)
	btn.add_theme_stylebox_override("disabled", disabled_style)

	return btn


# ── Helpers ──────────────────────────────────────────────────────────────────

func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius


func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
