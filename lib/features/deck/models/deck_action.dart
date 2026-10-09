/// What a key does when tapped. Host actions run on the computer running the
/// app; device actions (paging, brightness) run on the deck itself.
enum ActionType {
  none,
  openApp, // params: path, args
  openUrl, // params: url
  runCommand, // params: command
  hotkey, // params: keys  e.g. "ctrl+shift+m"
  typeText, // params: text
  media, // params: op  (MediaOp.name)
  micMute, // toggle, reports state
  speakerMute, // toggle, reports state
  nextPage,
  prevPage,
  gotoPage, // params: page (index as string)
  brightnessUp,
  brightnessDown;

  bool get isToggle => this == micMute || this == speakerMute;
  bool get runsOnDevice =>
      this == nextPage || this == prevPage || this == gotoPage || this == brightnessUp || this == brightnessDown;
}

enum MediaOp { volumeUp, volumeDown, mute, playPause, next, previous, stop }

class DeckAction {
  const DeckAction(this.type, [this.params = const {}]);
  const DeckAction.none() : type = ActionType.none, params = const {};

  final ActionType type;
  final Map<String, String> params;

  String param(String k, [String def = '']) => params[k] ?? def;

  DeckAction copyWith({ActionType? type, Map<String, String>? params}) =>
      DeckAction(type ?? this.type, params ?? this.params);

  Map<String, dynamic> toJson() => {'type': type.name, if (params.isNotEmpty) 'params': params};

  factory DeckAction.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const DeckAction.none();
    final t = ActionType.values.firstWhere((e) => e.name == j['type'], orElse: () => ActionType.none);
    return DeckAction(t, (j['params'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {});
  }

  /// Device-side part of the manifest ("dev" field), if this action runs on the deck.
  Map<String, dynamic>? toDeviceJson() => switch (type) {
        ActionType.nextPage => {'nav': 'next'},
        ActionType.prevPage => {'nav': 'prev'},
        ActionType.gotoPage => {'nav': int.tryParse(param('page')) ?? 0},
        ActionType.brightnessUp => {'bright': 40},
        ActionType.brightnessDown => {'bright': -40},
        _ => null,
      };
}
