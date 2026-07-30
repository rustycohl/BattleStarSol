extends SceneTree

## Headless M05-B evidence emitter.
##
##   Godot --path game --headless --script res://tests/A11yMatrix.gd
##
## Prints one JSON document describing the deterministic layout matrix and the
## worst-case contrast table. It reads the same functions the live HUD applies,
## so the artifact cannot drift from the shipped layout model.

const HudLayout = preload("res://scripts/HudLayout.gd")

# A wrapped multi-row action dock, measured from the flow container when the
# supported groups no longer fit on one row.
const WRAPPED_DOCK_HEIGHT := 212.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewports: Array = []
	for supported_viewport in HudLayout.SUPPORTED_VIEWPORTS:
		viewports.append(
			_viewport_row(supported_viewport, HudLayout.ACTION_DOCK_BASE_HEIGHT, "base", "supported")
		)
		viewports.append(
			_viewport_row(supported_viewport, WRAPPED_DOCK_HEIGHT, "wrapped", "supported")
		)
	for short_canvas in HudLayout.UNSUPPORTED_SHORT_CANVASES:
		viewports.append(
			_viewport_row(short_canvas, HudLayout.ACTION_DOCK_BASE_HEIGHT, "base", "unsupported")
		)
	var contrast: Array = []
	for contrast_case in HudLayout.contrast_report():
		contrast.append({
			"label": String(contrast_case["label"]),
			"ratio": snappedf(float(contrast_case["ratio"]), 0.01),
			"minimum": float(contrast_case["minimum"]),
			"passes": bool(contrast_case["passes"])
		})
	var constrained_probe := HudLayout.metrics_for_viewport(
		1024.0,
		360.0,
		HudLayout.STATUS_RAIL_RIGHT,
		HudLayout.STATUS_RAIL_RIGHT,
		HudLayout.TUTORIAL_HEIGHT,
		320.0
	)
	var document := {
		"schema": "gzg.battlestar.a11y-matrix/1.0",
		"engine": Engine.get_version_info().get("string", ""),
		"model": {
			"status_rail_right": HudLayout.STATUS_RAIL_RIGHT,
			"responsive_gutter": HudLayout.RESPONSIVE_GUTTER,
			"tutorial_top": HudLayout.TUTORIAL_TOP,
			"tutorial_height": HudLayout.TUTORIAL_HEIGHT,
			"action_dock_bottom_margin": HudLayout.ACTION_DOCK_BOTTOM_MARGIN,
			"action_dock_base_height": HudLayout.ACTION_DOCK_BASE_HEIGHT,
			"event_rail_top": HudLayout.EVENT_RAIL_TOP,
			"event_rail_comfort_height": HudLayout.EVENT_RAIL_COMFORT_HEIGHT,
			"wrapped_dock_height": WRAPPED_DOCK_HEIGHT
		},
		"canvas_note": "sizes are tactical-canvas sizes reported by the runtime, not browser windows",
		"focus_order": HudLayout.FOCUS_ORDER_KEYS,
		"contrast_backdrop": "opaque white; the lightest backdrop a tactical scene can place behind a translucent panel",
		"viewports": viewports,
		"contrast": contrast,
		"constrained_probe": {
			"viewport": "1024x360",
			"action_dock_height": 320.0,
			"constrained": bool(constrained_probe["constrained"]),
			"tutorial_dock_clear": bool(constrained_probe["tutorial_dock_clear"]),
			"event_rail_visible": bool(constrained_probe["event_rail_visible"])
		}
	}
	print(JSON.stringify(document, "  "))
	quit(0)

func _viewport_row(
	size: Vector2i,
	dock_height: float,
	dock_state: String,
	support: String
) -> Dictionary:
	var metrics: Dictionary = HudLayout.metrics_for_viewport(
		float(size.x),
		float(size.y),
		HudLayout.STATUS_RAIL_RIGHT,
		HudLayout.STATUS_RAIL_RIGHT,
		HudLayout.TUTORIAL_HEIGHT,
		dock_height
	)
	return {
		"viewport": "%dx%d" % [size.x, size.y],
		"width": size.x,
		"height": size.y,
		"support": support,
		"action_dock_state": dock_state,
		"action_dock_height": dock_height,
		"tutorial_left": float(metrics["tutorial_left"]),
		"tutorial_clearance": float(metrics["tutorial_clearance"]),
		"action_dock_left": float(metrics["action_dock_left"]),
		"action_dock_clearance": float(metrics["action_dock_clearance"]),
		"action_dock_top": float(metrics["action_dock_top"]),
		"tutorial_bottom": float(metrics["tutorial_bottom"]),
		"event_rail_top": float(metrics["event_rail_top"]),
		"event_rail_bottom": float(metrics["event_rail_bottom"]),
		"event_rail_height": float(metrics["event_rail_height"]),
		"event_rail_cramped": bool(metrics["event_rail_cramped"]),
		"event_rail_bottom_offset": float(metrics["event_rail_bottom_offset"]),
		"rails_clear": (
			float(metrics["tutorial_left"]) >= float(metrics["tutorial_clearance"])
			and float(metrics["action_dock_left"]) >= float(metrics["action_dock_clearance"])
		),
		"tutorial_dock_clear": bool(metrics["tutorial_dock_clear"]),
		"event_rail_visible": bool(metrics["event_rail_visible"]),
		"constrained": bool(metrics["constrained"])
	}
