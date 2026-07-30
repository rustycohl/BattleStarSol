extends RefCounted

## Pure tactical-HUD geometry and contrast model.
##
## `TacticalUI` applies these values to live controls; headless tests and the
## M05-B evidence emitter read them without a viewport, a scene tree, or the
## gameplay autoloads. Keeping them here means the artifact and the shipped
## layout cannot describe different rules.

const STATUS_RAIL_RIGHT := 230.0
const RESPONSIVE_GUTTER := 14.0
const TUTORIAL_LEFT_ANCHOR := 0.24
const ACTION_DOCK_LEFT_ANCHOR := 0.16

# Vertical geometry of the built HUD. These mirror the constructed offsets in
# `TacticalUI._build_ui`.
const TUTORIAL_TOP := 14.0
const TUTORIAL_HEIGHT := 98.0
const ACTION_DOCK_BOTTOM_MARGIN := 12.0
# Measured from the live dock in the 2026-07-29 M05-B matrix rather than
# estimated, so the headless model and the browser agree.
const ACTION_DOCK_BASE_HEIGHT := 116.0
const STATUS_RAIL_TOP := 14.0
const STATUS_RAIL_BASE_BOTTOM := 410.0
const EVENT_RAIL_GAP := 14.0
# Reported, not gated: below this the tactical feed still renders without
# overlapping anything, but shows very little history.
const EVENT_RAIL_COMFORT_HEIGHT := 96.0
const EVENT_RAIL_TOP := STATUS_RAIL_BASE_BOTTOM + EVENT_RAIL_GAP

# Supported tactical-canvas sizes. These are the canvas sizes the game reports,
# not browser window sizes: the embedded launcher gives the runtime less room
# than the window. Measured on 2026-07-29 in the M05-B live matrix:
#
#   1920x1080 and 1600x900 browser -> 1172x659 canvas
#   1440x900 browser               -> 1112x626 canvas
#   1366x768 browser               -> 1038x584 canvas
#
# Shorter canvases are deliberately absent: the HUD cannot serve them without a
# compact mode. See UNSUPPORTED_SHORT_CANVASES.
const SUPPORTED_VIEWPORTS: Array[Vector2i] = [
	Vector2i(1172, 659),
	Vector2i(1112, 626),
	Vector2i(1038, 584)
]

# Known-short canvases the current HUD cannot serve. They must be *detected* as
# constrained rather than silently overlapped. Browser origins measured in the
# same run: 1280x800 -> 952x536, 1024x768 -> 696x420, 768x1024 -> 734x413.
const UNSUPPORTED_SHORT_CANVASES: Array[Vector2i] = [
	Vector2i(952, 536),
	Vector2i(696, 420),
	Vector2i(734, 413)
]

# Deterministic keyboard traversal order for the core tactical controls.
const FOCUS_ORDER_KEYS: Array[String] = [
	"brace",
	"take_cover",
	"toggle_run",
	"endturn",
	"evac"
]

# --- Adaptive surfaces -------------------------------------------------------
#
# Every HUD surface is adaptive along three independent axes:
#
#   opacity  a continuous 0.15..1.0 multiplier, never fully invisible so a
#            surface can always be found again;
#   slide    parked off its own edge, leaving a grab handle, or fully open;
#   scroll   content taller than the surface scrolls instead of spilling.
#
# The layout model treats a parked surface as contributing only its handle, which
# is what lets a short canvas stay usable instead of being reported constrained.

const OPACITY_MIN := 0.15
const OPACITY_MAX := 1.0
const OPACITY_STEPS: Array[float] = [1.0, 0.75, 0.5, 0.3, 0.15]
const HANDLE_EXTENT := 18.0

enum Slide { OPEN, PARKED }

## Named surfaces, in the order the cycle control visits them.
const SURFACE_KEYS: Array[String] = [
	"status",
	"feed",
	"tutorial",
	"dock"
]

static func clamp_opacity(value: float) -> float:
	return clampf(value, OPACITY_MIN, OPACITY_MAX)

## Next opacity in the cycle. Wraps, so repeated presses always return to full.
static func next_opacity(value: float) -> float:
	var current := clamp_opacity(value)
	var closest := 0
	for index in OPACITY_STEPS.size():
		if absf(OPACITY_STEPS[index] - current) < absf(OPACITY_STEPS[closest] - current):
			closest = index
	return OPACITY_STEPS[(closest + 1) % OPACITY_STEPS.size()]

## Effective extent of a surface along the axis it parks against. A parked
## surface keeps only its handle, so the layout can reclaim the rest.
static func surface_extent(extent: float, slide: int) -> float:
	if slide == Slide.PARKED:
		return minf(HANDLE_EXTENT, maxf(extent, 0.0))
	return maxf(extent, 0.0)

static func default_surface_states() -> Dictionary:
	var states := {}
	for key in SURFACE_KEYS:
		states[key] = {"opacity": OPACITY_MAX, "slide": Slide.OPEN}
	return states

static func metrics_for_width(
	viewport_width: float,
	status_rail_right: float = STATUS_RAIL_RIGHT,
	event_rail_right: float = STATUS_RAIL_RIGHT
) -> Dictionary:
	var safe_width := maxf(viewport_width, 1.0)
	var status_clearance := status_rail_right + RESPONSIVE_GUTTER
	var event_clearance := event_rail_right + RESPONSIVE_GUTTER
	return {
		"status_rail_right": status_rail_right,
		"event_rail_right": event_rail_right,
		"tutorial_clearance": status_clearance,
		"action_dock_clearance": event_clearance,
		"tutorial_left": maxf(safe_width * TUTORIAL_LEFT_ANCHOR, status_clearance),
		"action_dock_left": maxf(safe_width * ACTION_DOCK_LEFT_ANCHOR, event_clearance)
	}

## Vertical companion to `metrics_for_width`. The action dock grows upward from
## the bottom margin, so its measured height decides how much room the
## tactical-feed rail and the tutorial callout actually have.
static func metrics_for_viewport(
	viewport_width: float,
	viewport_height: float,
	status_rail_right: float = STATUS_RAIL_RIGHT,
	event_rail_right: float = STATUS_RAIL_RIGHT,
	tutorial_height: float = TUTORIAL_HEIGHT,
	action_dock_height: float = ACTION_DOCK_BASE_HEIGHT,
	status_rail_content_bottom: float = STATUS_RAIL_BASE_BOTTOM
) -> Dictionary:
	var metrics := metrics_for_width(
		viewport_width,
		status_rail_right,
		event_rail_right
	)
	var safe_height := maxf(viewport_height, 1.0)
	var dock_height := maxf(action_dock_height, 0.0)
	var dock_top := safe_height - ACTION_DOCK_BOTTOM_MARGIN - dock_height
	var tutorial_bottom := TUTORIAL_TOP + maxf(tutorial_height, 0.0)
	var event_rail_bottom := dock_top - RESPONSIVE_GUTTER
	var tutorial_dock_clear := dock_top >= tutorial_bottom + RESPONSIVE_GUTTER

	# The status rail is measured, not assumed. Its authored box ends at 410 but
	# its content (stance line and core-cost line) runs past that, so a feed rail
	# pinned to 424 covered them. Compressing the box instead would only spill the
	# content, since a shorter box does not shorten what it holds. A canvas with
	# no room left below the measured rail is reported as constrained and left to
	# a later compact-HUD module.
	var status_rail_bottom := maxf(STATUS_RAIL_BASE_BOTTOM, status_rail_content_bottom)
	var event_rail_top := status_rail_bottom + EVENT_RAIL_GAP
	var event_rail_height := event_rail_bottom - event_rail_top
	# The gate is disjoint panels with a positive feed rail. How much room the
	# feed deserves above that is a design decision, so it is reported, not gated.
	var event_rail_visible := event_rail_height > 0.0
	var event_rail_cramped := event_rail_height < EVENT_RAIL_COMFORT_HEIGHT

	metrics["viewport_width"] = maxf(viewport_width, 1.0)
	metrics["viewport_height"] = safe_height
	metrics["tutorial_top"] = TUTORIAL_TOP
	metrics["tutorial_bottom"] = tutorial_bottom
	metrics["action_dock_height"] = dock_height
	metrics["action_dock_top"] = dock_top
	metrics["status_rail_top"] = STATUS_RAIL_TOP
	metrics["status_rail_bottom"] = status_rail_bottom
	metrics["event_rail_top"] = event_rail_top
	metrics["event_rail_bottom"] = event_rail_bottom
	metrics["event_rail_height"] = event_rail_height
	# Bottom-anchored controls take a negative offset from the viewport edge.
	metrics["event_rail_bottom_offset"] = event_rail_bottom - safe_height
	metrics["tutorial_dock_clear"] = tutorial_dock_clear
	metrics["event_rail_visible"] = event_rail_visible
	metrics["event_rail_cramped"] = event_rail_cramped
	metrics["constrained"] = not tutorial_dock_clear or not event_rail_visible
	return metrics

## Adaptive layout. Identical to `metrics_for_viewport` when every surface is
## open, but a parked surface contributes only its handle, and a canvas that
## cannot fit the open layout is resolved by parking surfaces in a fixed,
## documented order rather than being reported constrained.
##
## Parking order is deliberate: the tactical feed is history and goes first, then
## the status rail, whose content the roster and unit HUD duplicate in part. The
## action dock and the tutorial callout are never auto-parked, because losing them
## silently would remove the player's actions or their instructions.
static func adaptive_metrics(
	viewport_width: float,
	viewport_height: float,
	surface_states: Dictionary = {},
	status_rail_right: float = STATUS_RAIL_RIGHT,
	event_rail_right: float = STATUS_RAIL_RIGHT,
	tutorial_height: float = TUTORIAL_HEIGHT,
	action_dock_height: float = ACTION_DOCK_BASE_HEIGHT,
	status_rail_content_bottom: float = STATUS_RAIL_BASE_BOTTOM
) -> Dictionary:
	var states := default_surface_states()
	for key in surface_states:
		if states.has(key):
			var incoming = surface_states[key]
			if incoming is Dictionary:
				if incoming.has("opacity"):
					states[key]["opacity"] = clamp_opacity(float(incoming["opacity"]))
				if incoming.has("slide"):
					states[key]["slide"] = int(incoming["slide"])
	var auto_parked: Array[String] = []
	var metrics := {}
	# Try the requested arrangement, then park in order until it fits. Only the
	# tactical feed is auto-parked: it is history, and it is the surface whose own
	# room is the constraint. Parking the status rail slides it along the same left
	# edge, so it would not give the feed the vertical room it lacks. The status
	# rail stays available to the player, who may still slide it away by hand.
	var attempts: Array[String] = ["", "feed", "status"]
	for attempt in attempts:
		if not attempt.is_empty():
			if int(states[attempt]["slide"]) == Slide.PARKED:
				continue
			states[attempt]["slide"] = Slide.PARKED
			auto_parked.append(attempt)
		metrics = _arranged_metrics(
			viewport_width,
			viewport_height,
			states,
			status_rail_right,
			event_rail_right,
			tutorial_height,
			action_dock_height,
			status_rail_content_bottom
		)
		if not bool(metrics["constrained"]):
			break
	metrics["surfaces"] = states
	metrics["auto_parked"] = auto_parked
	metrics["adaptive"] = true
	return metrics

static func _arranged_metrics(
	viewport_width: float,
	viewport_height: float,
	states: Dictionary,
	status_rail_right: float,
	event_rail_right: float,
	tutorial_height: float,
	action_dock_height: float,
	status_rail_content_bottom: float
) -> Dictionary:
	var status_slide := int(states["status"]["slide"])
	var feed_slide := int(states["feed"]["slide"])
	var dock_slide := int(states["dock"]["slide"])
	var tutorial_slide := int(states["tutorial"]["slide"])

	# A parked rail claims only its handle. The handle's right edge is the gutter
	# plus the handle width, which is where the slid panel's visible edge actually
	# lands — not the handle width alone.
	var parked_rail_right := RESPONSIVE_GUTTER + HANDLE_EXTENT
	var effective_status_right := status_rail_right
	if status_slide == Slide.PARKED:
		effective_status_right = parked_rail_right
	var effective_event_right := event_rail_right
	if feed_slide == Slide.PARKED:
		effective_event_right = parked_rail_right

	var effective_dock := surface_extent(action_dock_height, dock_slide)
	var effective_tutorial := surface_extent(tutorial_height, tutorial_slide)
	# A left-parked status rail slides sideways; it keeps its vertical extent, so
	# the tactical feed below it gains no room from that.
	var effective_status_bottom := status_rail_content_bottom

	var metrics := metrics_for_viewport(
		viewport_width,
		viewport_height,
		effective_status_right,
		effective_event_right,
		effective_tutorial,
		effective_dock,
		effective_status_bottom
	)
	# A parked feed rail cannot be crowded out; only an open one can fail.
	if feed_slide == Slide.PARKED:
		metrics["event_rail_visible"] = true
		metrics["event_rail_cramped"] = false
		metrics["constrained"] = not bool(metrics["tutorial_dock_clear"])
	# On a very short canvas the dock's top rises past the status rail's bottom, so
	# the two overlap even though each clears everything else. A parked status rail
	# leaves only its handle on the left edge, which the dock already clears.
	var dock_status_clear := (
		status_slide == Slide.PARKED
		or float(metrics["action_dock_top"]) >= status_rail_content_bottom + RESPONSIVE_GUTTER
	)
	metrics["dock_status_clear"] = dock_status_clear
	metrics["constrained"] = bool(metrics["constrained"]) or not dock_status_clear
	return metrics

## Worst-case WCAG contrast for the core tactical text. Panel backgrounds are
## translucent, so each is composited over opaque white: the lightest backdrop a
## tactical scene can put behind them, and therefore the lowest ratio the text
## can reach.
static func contrast_report() -> Array[Dictionary]:
	var status_bg := composite_over_white(Color(0.04, 0.05, 0.08, 0.92))
	var event_bg := composite_over_white(Color(0.04, 0.05, 0.08, 0.78))
	var dock_bg := composite_over_white(Color(0.04, 0.05, 0.08, 0.94))
	var tutorial_bg := composite_over_white(Color(0.025, 0.12, 0.11, 0.96))
	var cases: Array[Dictionary] = [
		{"label": "turn banner", "fg": Color(1, 1, 1), "bg": status_bg},
		{"label": "NEURAL readout", "fg": Color(0.2, 0.9, 0.6), "bg": status_bg},
		{"label": "active pilot", "fg": Color(0.35, 1.0, 0.75), "bg": status_bg},
		{"label": "phase help", "fg": Color(0.72, 0.82, 0.95), "bg": status_bg},
		{"label": "core costs", "fg": Color(0.65, 0.76, 0.88), "bg": status_bg},
		{"label": "hostile roster", "fg": Color(1, 0.6, 0.55), "bg": status_bg},
		{"label": "squad heading", "fg": Color(0.6, 0.7, 0.8), "bg": status_bg},
		{"label": "targeting hint", "fg": Color(0.7, 0.85, 1.0), "bg": event_bg},
		{"label": "tactical feed heading", "fg": Color(0.7, 0.7, 0.9), "bg": event_bg},
		{"label": "tutorial title", "fg": Color(0.35, 1.0, 0.78), "bg": tutorial_bg},
		{"label": "tutorial title (alert)", "fg": Color(1.0, 0.85, 0.3), "bg": tutorial_bg},
		{"label": "tutorial body", "fg": Color(0.9, 0.96, 1.0), "bg": tutorial_bg},
		{"label": "action label", "fg": Color(1, 1, 1), "bg": dock_bg},
		{"label": "action group heading", "fg": Color(0.5, 0.6, 0.7), "bg": dock_bg},
		{"label": "End Turn label", "fg": Color(1, 0.4, 0.4), "bg": dock_bg},
		{"label": "Extract label", "fg": Color(1, 0.75, 0.2), "bg": dock_bg},
		{
			"label": "keyboard focus outline",
			"fg": Color(0.3, 0.95, 1.0),
			"bg": dock_bg,
			"minimum": 3.0
		}
	]
	var report: Array[Dictionary] = []
	for contrast_case in cases:
		var minimum := float(contrast_case.get("minimum", 4.5))
		var ratio := contrast_ratio(contrast_case["fg"], contrast_case["bg"])
		report.append({
			"label": String(contrast_case["label"]),
			"ratio": ratio,
			"minimum": minimum,
			"passes": ratio >= minimum
		})
	return report

static func contrast_ratio(foreground: Color, background: Color) -> float:
	var foreground_luminance := relative_luminance(foreground)
	var background_luminance := relative_luminance(background)
	var lighter := maxf(foreground_luminance, background_luminance)
	var darker := minf(foreground_luminance, background_luminance)
	return (lighter + 0.05) / (darker + 0.05)

static func composite_over_white(source: Color) -> Color:
	var alpha := clampf(source.a, 0.0, 1.0)
	return Color(
		source.r * alpha + (1.0 - alpha),
		source.g * alpha + (1.0 - alpha),
		source.b * alpha + (1.0 - alpha),
		1.0
	)

static func relative_luminance(color: Color) -> float:
	return (
		0.2126 * linear_channel(color.r)
		+ 0.7152 * linear_channel(color.g)
		+ 0.0722 * linear_channel(color.b)
	)

static func linear_channel(channel: float) -> float:
	var value := clampf(channel, 0.0, 1.0)
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)
