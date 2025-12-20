
import 'media_transform.dart';
import '../services/effect_service.dart';

enum LayerTarget {
  background,
  middle,
  foreground,
}

enum LayerType {
  none,
  video,
  effect,
}

class LayerConfig {
  final LayerType type;
  final String? path; // Path to video file
  final EffectType? effect; // Effect type
  final Map<String, dynamic> effectParams;
  final double opacity;
  final bool isVisible;
  final MediaTransform? transform;
  final bool lockAspectRatio;

  const LayerConfig({
    this.type = LayerType.none,
    this.path,
    this.effect,
    this.effectParams = const {},
    this.opacity = 1.0,
    this.isVisible = true,
    this.transform,
    this.lockAspectRatio = true,
  });

  LayerConfig copyWith({
    LayerType? type,
    String? path,
    EffectType? effect,
    Map<String, dynamic>? effectParams,
    double? opacity,
    bool? isVisible,
    MediaTransform? transform,
    bool? lockAspectRatio,
  }) {
    return LayerConfig(
      type: type ?? this.type,
      path: path ?? this.path,
      effect: effect ?? this.effect,
      effectParams: effectParams ?? this.effectParams,
      opacity: opacity ?? this.opacity,
      isVisible: isVisible ?? this.isVisible,
      transform: transform ?? this.transform,
      lockAspectRatio: lockAspectRatio ?? this.lockAspectRatio,
    );
  }

  factory LayerConfig.fromJson(Map<String, dynamic> json) {
    return LayerConfig(
      type: LayerType.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? 'none'),
        orElse: () => LayerType.none,
      ),
      path: json['path'] as String?,
      effect: json['effect'] != null
          ? EffectType.values.firstWhere(
              (e) => e.name == (json['effect'] as String),
              orElse: () => EffectType.rainbow,
            )
          : null,
      effectParams: json['effectParams'] as Map<String, dynamic>? ?? const {},
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      isVisible: json['isVisible'] as bool? ?? true,
      transform: json['transform'] != null
          ? MediaTransform.fromJson(json['transform'] as Map<String, dynamic>)
          : null,
      lockAspectRatio: json['lockAspectRatio'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'path': path,
      'effect': effect?.name,
      'effectParams': effectParams,
      'opacity': opacity,
      'isVisible': isVisible,
      'transform': transform?.toJson(),
      'lockAspectRatio': lockAspectRatio,
    };
  }
}
