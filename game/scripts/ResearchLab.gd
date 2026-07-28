extends Control

var _status: Label
var _vbox: VBoxContainer

func _lbl(t: String, sz: int, col: Color, text_wrap := false) -> Label:
    var l := Label.new()
    l.text = t
    l.add_theme_font_size_override("font_size", sz)
    l.add_theme_color_override("font_color", col)
    if text_wrap:
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l

func _btn(t: String, cb: Callable) -> Button:
    var b := Button.new()
    b.text = t
    b.add_theme_font_size_override("font_size", 12)
    b.pressed.connect(cb)
    return b

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.6)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(dim)

    var panel := PanelContainer.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    panel.custom_minimum_size = Vector2(480, 440)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.04, 0.04, 0.08, 0.98)
    sb.border_color = Color(0.5, 0.2, 0.7)
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(6)
    sb.content_margin_left = 18
    sb.content_margin_right = 18
    sb.content_margin_top = 16
    sb.content_margin_bottom = 16
    panel.add_theme_stylebox_override("panel", sb)
    add_child(panel)

    _vbox = VBoxContainer.new()
    _vbox.add_theme_constant_override("separation", 10)
    panel.add_child(_vbox)

    var head := HBoxContainer.new()
    var title := _lbl("◈ R&D LABORATORY", 16, Color(0.6, 0.3, 0.9))
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    head.add_child(_btn("✕", queue_free))
    _vbox.add_child(head)

    _vbox.add_child(_lbl("Reverse-engineer salvaged technology to unlock higher weapon tiers for deployment.", 10, Color(0.5, 0.5, 0.6), true))

    _status = _lbl("", 10, Color(0.8, 0.2, 0.2), true)

    _refresh()

func _refresh() -> void:
    for c in _vbox.get_children():
        if c != _vbox.get_child(0) and c != _vbox.get_child(1) and c != _status:
            c.queue_free()

    var resources := _lbl("AVAILABLE RESOURCES: %d CAPITAL | %d NEURAL" % [GameState.vault_fiat, GameState.vault_neural], 12, Color(0.2, 0.9, 0.6))
    _vbox.add_child(resources)

    var tiers = [
        {"tier": 2, "name": "Tier 2: Laser & Directed Energy", "fiat": 1000, "neural": 10},
        {"tier": 3, "name": "Tier 3: Electromagnetic & Rail", "fiat": 5000, "neural": 25},
        {"tier": 4, "name": "Tier 4: Plasma & Bio-Organic", "fiat": 10000, "neural": 50},
        {"tier": 5, "name": "Tier 5: Dark Energy & Next-Gen", "fiat": 25000, "neural": 100}
    ]

    for t in tiers:
        var row := HBoxContainer.new()
        var is_unlocked = GameState.unlocked_tiers.has(t.tier)

        var t_lbl = _lbl(t.name, 12, Color(0.8, 0.8, 0.8) if is_unlocked else Color(0.4, 0.4, 0.4))
        t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(t_lbl)

        if is_unlocked:
            var unl = _lbl("UNLOCKED", 12, Color(0.2, 0.8, 0.3))
            row.add_child(unl)
        else:
            var cost = _lbl("%d Cap / %d Neur" % [t.fiat, t.neural], 10, Color(0.7, 0.5, 0.2))
            row.add_child(cost)

            var btn = _btn("RESEARCH", func(): _try_unlock(t.tier, t.fiat, t.neural))
            if GameState.vault_fiat < t.fiat or GameState.vault_neural < t.neural:
                btn.disabled = true
            row.add_child(btn)

        _vbox.add_child(row)

    if not _status.get_parent():
        _vbox.add_child(_status)

func _try_unlock(tier: int, cost_fiat: int, cost_neural: int) -> void:
    if GameState.vault_fiat >= cost_fiat and GameState.vault_neural >= cost_neural:
        GameState.vault_fiat -= cost_fiat
        GameState.vault_neural -= cost_neural
        GameState.unlocked_tiers.append(tier)
        _status.text = ""
        _status.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3))
        _refresh()
    else:
        _status.text = "Insufficient resources for Tier %d." % tier
        _status.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
