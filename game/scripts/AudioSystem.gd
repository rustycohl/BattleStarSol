extends Node

const MAX_PLAYERS = 16
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []

func _ready() -> void:
    for i in range(MAX_PLAYERS):
        var p3d = AudioStreamPlayer3D.new()
        p3d.bus = "SFX"
        add_child(p3d)
        _pool_3d.append(p3d)

        var p2d = AudioStreamPlayer.new()
        p2d.bus = "SFX"
        add_child(p2d)
        _pool_2d.append(p2d)

func play_3d(event_name: String, pos: Vector3) -> void:
    var stream = _get_stream(event_name)
    if not stream: return
    for p in _pool_3d:
        if not p.playing:
            p.position = pos
            p.stream = stream
            p.play()
            return

func play_2d(event_name: String) -> void:
    var stream = _get_stream(event_name)
    if not stream: return
    for p in _pool_2d:
        if not p.playing:
            p.stream = stream
            p.play()
            return

func _get_stream(event_name: String) -> AudioStream:
    # Try to load a real file if it exists
    var path = "res://audio/%s.wav" % event_name
    if ResourceLoader.exists(path):
        return load(path)
    path = "res://audio/%s.ogg" % event_name
    if ResourceLoader.exists(path):
        return load(path)

    # Missing audio is deliberately silent. Returning an unfilled
    # AudioStreamGenerator caused a warning every time an action attempted to
    # play it and provided no sound. Real assets can be added by event name.
    return null
