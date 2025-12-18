import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/layer_config.dart';
import 'effect_renderer.dart';

class LayerRenderer extends StatelessWidget {
  final LayerConfig layer;
  final VideoController? controller;
  final bool isPlaying;

  const LayerRenderer({
    super.key,
    required this.layer,
    this.controller,
    this.isPlaying = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!layer.isVisible || layer.opacity <= 0) {
      return const SizedBox.shrink();
    }

    Widget content;
    switch (layer.type) {
      case LayerType.video:
        if (controller != null) {
          content = Video(controller: controller!);
        } else {
          content = const SizedBox.shrink();
        }
        break;
      case LayerType.effect:
        if (layer.effect != null) {
          content = EffectRenderer(
            type: layer.effect!,
            params: layer.effectParams,
            isPlaying: isPlaying,
          );
        } else {
          content = const SizedBox.shrink();
        }
        break;
      case LayerType.none:
      default:
        content = const SizedBox.shrink();
    }

    if (layer.opacity < 1.0) {
      return Opacity(
        opacity: layer.opacity,
        child: content,
      );
    }
    return content;
  }
}
