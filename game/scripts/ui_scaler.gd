extends Node

# UI_Scaler – handles UI scaling and stores a quick lookup for shortcuts.
# Base resolution is the size you designed the UI for (e.g., 1920x1080).
const BASE_RES : Vector2 = Vector2(1920, 1080)

# Mapping of action name -> keycode (filled in _setup_input_map).
var action_to_keycode : Dictionary = {}

func _ready() -> void:
    _setup_input_map()
    _apply_scaling()

# ------------------------------------------------------------------
# InputMap creation – add all of your actions here.
# ------------------------------------------------------------------
func _setup_input_map() -> void:
    var actions = {
        "brace": KEY_B,
        "crouch": KEY_C,
        "jump": KEY_SPACE,
        "attack": KEY_V,
        # Add any other actions you have defined in the game.
    }
    for action_name in actions.keys():
        InputMap.add_action(action_name)
        var ev = InputEventKey.new()
        ev.keycode = actions[action_name]
        InputMap.action_add_event(action_name, ev)
        action_to_keycode[action_name] = actions[action_name]

# ------------------------------------------------------------------
# Apply a uniform scaling factor based on the current window size.
# ------------------------------------------------------------------
func _apply_scaling() -> void:
    var win_sz : Vector2 = DisplayServer.window_get_size()
    var scale  : Vector2 = win_sz / BASE_RES
    # Clamp to a reasonable max (prevent UI from becoming huge).
    scale = scale.clamp(Vector2.ZERO, Vector2(2, 2))
    # The root UI CanvasLayer – adjust the path if your hierarchy differs.
    var ui_root = get_node_or_null("/root/Root/CanvasLayer")
    if ui_root:
        ui_root.scale = scale
    else:
        push_warning("UI_Scaler: couldn't find CanvasLayer at /root/Root/CanvasLayer – scaling not applied.")

# Helper to retrieve the stored keycode for a given action name.
func get_action_keycode(action_name: String) -> int:
    return action_to_keycode.get(action_name, 0)
