import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/show_state.dart';
import '../../models/layer_config.dart';
import 'dart:io';

class LayerControls extends StatelessWidget {
  final LayerTarget selectedLayer;
  final ValueChanged<LayerTarget> onSelectLayer;

  const LayerControls({
    super.key,
    required this.selectedLayer,
    required this.onSelectLayer,
  });

  @override
  Widget build(BuildContext context) {
    final show = context.watch<ShowState>().currentShow;
    if (show == null) return const SizedBox.shrink();

    // Render 3 Layers in Reverse Order (Foreground Top, Background Bottom)
    // Actually, lists usually top-down. 
    // Foreground should be at top of list.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLayerItem(context, show.foregroundLayer, LayerTarget.foreground, "FOREGROUND"),
        const SizedBox(height: 8),
        _buildLayerItem(context, show.middleLayer, LayerTarget.middle, "MIDDLE"),
        const SizedBox(height: 8),
        _buildLayerItem(context, show.backgroundLayer, LayerTarget.background, "BACKGROUND"),
      ],
    );
  }

  Widget _buildLayerItem(BuildContext context, LayerConfig layer, LayerTarget target, String label) {
    final isSelected = selectedLayer == target;

    return GestureDetector(
      onTap: () => onSelectLayer(target),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected ? const Color(0xFF90CAF9) : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + Label + Visibility
            Row(
              children: [
                Icon(
                  layer.type == LayerType.video ? Icons.movie : (layer.type == LayerType.effect ? Icons.auto_fix_high : Icons.layers),
                  size: 16,
                  color: isSelected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 12,
                    letterSpacing: 1.0
                  )),
                ),
                // Visibility Toggle
                InkWell(
                  onTap: () {
                     context.read<ShowState>().updateLayer(
                       target: target,
                       isVisible: !layer.isVisible
                     );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      layer.isVisible ? Icons.visibility : Icons.visibility_off, 
                      size: 16, 
                      color: layer.isVisible ? (isSelected ? Colors.white70 : Colors.white38) : Colors.white24
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Content Info Row
            Row(
              children: [
                 Expanded(
                   child: Text(
                      layer.type == LayerType.none 
                         ? "Empty" 
                         : (layer.type == LayerType.video 
                             ? (layer.path?.split(Platform.pathSeparator).last ?? "Unknown Video")
                             : "Effect: ${layer.effect?.name.toUpperCase() ?? 'NONE'}"),
                      style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                   ),
                 ),
                 // Clear Button (Next to Name)
                 if (layer.type != LayerType.none)
                    InkWell(
                      onTap: () {
                         context.read<ShowState>().updateLayer(
                           target: target,
                           type: LayerType.none,
                           path: null,
                           effect: null
                         );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: const Icon(Icons.close, size: 14, color: Colors.white38),
                      ),
                    )
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Opacity Slider
            Row(
              children: [
                const Icon(Icons.opacity, size: 12, color: Colors.white38),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 20,
                    child: SliderTheme(
                       data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                       ),
                       child: Slider(
                        value: layer.opacity,
                        min: 0.0,
                        max: 1.0,
                         activeColor: isSelected ? const Color(0xFF90CAF9) : Colors.white30,
                         inactiveColor: Colors.white10,
                         onChangeStart: (_) {
                            if (!isSelected) onSelectLayer(target);
                         },
                         onChanged: (v) {
                            context.read<ShowState>().updateLayer(
                               target: target,
                               opacity: v
                            );
                         },
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
