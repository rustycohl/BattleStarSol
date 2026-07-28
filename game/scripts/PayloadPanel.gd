extends Control
## PayloadPanel — the "Payload Vault". Native save/load + export/import for the client.
## Framing: single-player saves that are secretly portable MOD states. The game builds the
## exportable payload for you (no filesystem spelunking) — "Hackers" energy, on purpose.
## Operates on the PayloadBridge autoload.

var _list: ItemList
var _name_edit: LineEdit
var _status: Label
var _fd: FileDialog

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
    sb.bg_color = Color(0.04, 0.06, 0.09, 0.98)
    sb.border_color = Color(0.1, 0.5, 0.7)
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(6)
    sb.content_margin_left = 18
    sb.content_margin_right = 18
    sb.content_margin_top = 16
    sb.content_margin_bottom = 16
    panel.add_theme_stylebox_override("panel", sb)
    add_child(panel)

    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    panel.add_child(v)

    var head := HBoxContainer.new()
    var title := _lbl("◈ PAYLOAD VAULT", 16, Color(0.1, 0.8, 0.9))
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(title)
    head.add_child(_btn("✕", queue_free))
    v.add_child(head)

    v.add_child(_lbl("Saves are portable payloads. Extract one to a file, inject it anywhere — a friend's game, Discord, another server. It's modding, natively.", 10, Color(0.5, 0.6, 0.7), true))

    _list = ItemList.new()
    _list.custom_minimum_size = Vector2(0, 190)
    v.add_child(_list)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    _name_edit = LineEdit.new()
    _name_edit.placeholder_text = "payload name"
    _name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(_name_edit)
    row.add_child(_btn("SAVE", _on_save))
    row.add_child(_btn("LOAD", _on_load))
    v.add_child(row)

    var row2 := HBoxContainer.new()
    row2.add_theme_constant_override("separation", 6)
    var ex := _btn("EXTRACT ▸ FILE", _on_export)
    ex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var im := _btn("◂ INJECT FILE", _on_import)
    im.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row2.add_child(ex)
    row2.add_child(im)
    v.add_child(row2)

    _status = _lbl("", 10, Color(0.2, 0.9, 0.6), true)
    v.add_child(_status)

    _fd = FileDialog.new()
    _fd.access = FileDialog.ACCESS_FILESYSTEM
    _fd.use_native_dialog = true
    _fd.filters = PackedStringArray(["*.json ; Payload JSON"])
    _fd.file_selected.connect(_on_file_chosen)
    add_child(_fd)

    _refresh()

func _refresh() -> void:
    _list.clear()
    for n in PayloadBridge.list_saves():
        _list.add_item(n)

func _current_state() -> Dictionary:
    return PayloadBridge.get_payload()

func _selected_name() -> String:
    var sel := _list.get_selected_items()
    if sel.is_empty():
        return ""
    return _list.get_item_text(sel[0])

func _on_save() -> void:
    var nm := _name_edit.text.strip_edges()
    if nm == "":
        nm = "payload_%d" % int(Time.get_unix_time_from_system())
    PayloadBridge.save_payload(nm, _current_state())
    _status.text = "Saved payload: %s" % nm
    _refresh()

func _on_load() -> void:
    var nm := _selected_name()
    if nm == "":
        _status.text = "Select a payload to load."
        return
    var d := PayloadBridge.load_payload(nm)
    if d.is_empty():
        _status.text = "Load failed."
        return
    var ptype = d.get("type", "")
    if ptype in ["deploy", "tactical_state"] and PayloadBridge.set_payload(d):
        _status.text = "Loaded payload: %s (seed %d)" % [nm, PayloadBridge.get_seed()]
        _status.text = "Launching Tactical Layer..."
        if GameState: GameState.return_action = "vault"
        await get_tree().create_timer(0.5).timeout
        get_tree().change_scene_to_file("res://Main.tscn")
    elif ptype == "extraction":
        _status.text = "Extraction result selected. It is a result, not a deployable mission."
    else:
        _status.text = "Unsupported or invalid payload."

func _on_export() -> void:
    _fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    var nm := _name_edit.text.strip_edges()
    _fd.current_file = (nm if nm != "" else "payload") + ".json"
    _fd.popup_centered_ratio(0.6)

func _on_import() -> void:
    _fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _fd.popup_centered_ratio(0.6)

func _on_file_chosen(path: String) -> void:
    if _fd.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
        if PayloadBridge.export_payload(_current_state(), path):
            _status.text = "Extracted payload → %s" % path
        else:
            _status.text = "Export failed."
    else:
        var d := PayloadBridge.import_payload(path)
        if d.is_empty():
            _status.text = "Inject failed / invalid payload."
            return
        var ptype = d.get("type", "")
        if ptype in ["deploy", "tactical_state"] and PayloadBridge.set_payload(d):
            _status.text = "Injected payload (seed %d)" % PayloadBridge.get_seed()
            _refresh()
            _status.text = "Injected! Launching Tactical..."
            if GameState: GameState.return_action = "vault"
            await get_tree().create_timer(0.5).timeout
            get_tree().change_scene_to_file("res://Main.tscn")
        elif ptype == "extraction":
            _status.text = "Imported extraction result. Results cannot launch missions."
        else:
            _status.text = "Unsupported or invalid payload."
