
import 'media_transform.dart';
import '../services/effect_service.dart';

enum LayerType {
  none,
  video,
  effect,
}

class LayerConfig {
  final LayerType type;
  final String? path; // Path to video file
  final EffectType? effect; // Effect type
  final Map<String, double> effectParams;
  final double opacity;
  final bool isVisible;
  final MediaTransform? transform;

  const LayerConfig({
    this.type = LayerType.none,
    this.path,
    this.effect,
    this.effectParams = const {},
    this.opacity = 1.0,
    this.isVisible = true,
    this.transform,
  });

  LayerConfig copyWith({
    LayerType? type,
    String? path,
    EffectType? effect,
    Map<String, double>? effectParams,
    double? opacity,
    bool? isVisible,
    MediaTransform? transform,
  }) {
    return LayerConfig(
      type: type ?? this.type,
      path: path ?? this.path,
      effect: effect ?? this.effect,
      effectParams: effectParams ?? this.effectParams,
      opacity: opacity ?? this.opacity,
      isVisible: isVisible ?? this.isVisible,
      transform: transform ?? this.transform,
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
      effectParams: (json['effectParams'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const {},
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      isVisible: json['isVisible'] as bool? ?? true,
      transform: json['transform'] != null
          ? MediaTransform.fromJson(json['transform'] as Map<String, dynamic>)
          : null,
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
    };
  }
}
