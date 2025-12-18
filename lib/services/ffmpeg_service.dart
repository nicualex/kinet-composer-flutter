import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/show_manifest.dart';
import '../models/layer_config.dart';
import '../models/media_transform.dart';
import 'effect_service.dart';

class FfmpegService {
  static const String ffmpeg = 'ffmpeg';
  static const String ffprobe = 'ffprobe';

  /// Probes the duration of a video file in seconds.
  /// Returns 10.0 if probing fails or for non-video files.
  static Future<double> probeDuration(String path) async {
    try {
      final result = await Process.run(ffprobe, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        path
      ]);

      if (result.exitCode == 0) {
        final val = double.tryParse(result.stdout.toString().trim());
        if (val != null) return val;
      }
    } catch (e) {
      debugPrint("Probing error for $path: $e");
    }
    return 10.0; // Default fallback
  }

  /// Renders the composite show to a single video file.
  static Future<ProcessResult> renderShow({
    required ShowManifest show,
    required Rect intersection, // visual logic space
    required int resW, // matrix resolution W
    required int resH, // matrix resolution H
    required String outputPath,
    required Size bgVideoSize, // Actual pixel resolution of BG Video (if any)
    required Size mdVideoSize,
    required Size fgVideoSize,
  }) async {
    
    // 1. Calculate Duration (Longest Video)
    double maxDuration = 10.0;
    
    // Probe all active video layers
    List<Future<double>> probes = [];
    if (show.backgroundLayer.type == LayerType.video && show.backgroundLayer.path != null) {
      probes.add(probeDuration(show.backgroundLayer.path!));
    }
    if (show.middleLayer.type == LayerType.video && show.middleLayer.path != null) {
      probes.add(probeDuration(show.middleLayer.path!));
    }
    if (show.foregroundLayer.type == LayerType.video && show.foregroundLayer.path != null) {
      probes.add(probeDuration(show.foregroundLayer.path!));
    }
    
    if (probes.isNotEmpty) {
      final durations = await Future.wait(probes);
      if (durations.isNotEmpty) {
        maxDuration = durations.reduce(max);
      }
    }
    
    debugPrint("Render Duration: ${maxDuration}s");

    // 2. Build Filter Graph
    // Canvas Size = Matrix Intersection visual Logic Space Size * 10 (arbitrary high res for composition)
    // Or simpler: Composition should happen at "Video Source High Res".
    // 
    // Logic:
    // - Intersection is defined in "Matrix Logic Space" where Grid=10px.
    // - Video Layers have transforms relative to this Logic Space.
    // 
    // To minimize aliasing, let's composite at a HIGH resolution (e.g. 1920x1080 or the size of the Intersection in logic*20).
    // Actually, `_renderVideo` used source pixels.
    // Here we have mixed sources (Video A 4K, Video B 1080p, Effect).
    // 
    // Let's define the "Canvas" as the Intersection Rectangle in Logic Space * SCALE_FACTOR (e.g. 20).
    // - Grid=10. Intersection 50x50 logic -> 500x500 logic pixels? No, logic is just units.
    // - Let's say intersection width is 500.0 logic units (50 cols * 10).
    // - We want output 50x50.
    // - Let's render at 500x500 (1:1 with logic units) or 1000x1000 (2x).
    // 
    // Let's stick to 1:1 with Logic Units for simplicity of math.
    // Canvas W = Intersection.width
    // Canvas H = Intersection.height
    // (Ensure even for ffmpeg)
    
    int canvasW = intersection.width.ceil();
    int canvasH = intersection.height.ceil();
    if (canvasW % 2 != 0) canvasW++;
    if (canvasH % 2 != 0) canvasH++;
    
    // 3. Inputs
    List<String> inputs = [];
    List<String> filterComplex = [];
    
    // Base Canvas (Black)
    // Using virtual source
    String lastStream = "bg_canvas";
    filterComplex.add("color=c=black:s=${canvasW}x${canvasH} [bg_canvas]");
    
    int inputIdx = 0;
    
    // Helper to process a layer
    void processLayer(LayerConfig layer, String layerName, Size videoSize) {
      if (layer.type == LayerType.none) return;
      
      String streamName = "${layerName}_raw";
      
      if (layer.type == LayerType.video && layer.path != null) {
        inputs.add('-stream_loop'); inputs.add('-1'); // Loop input
        inputs.add('-i'); inputs.add(layer.path!);
        streamName = "$inputIdx:v";
        inputIdx++;
      } else if (layer.type == LayerType.effect && layer.effect != null) {
        // Generate Effect Source
        // Assume HD default for effect gen
        String filter = EffectService.getFFmpegFilter(layer.effect!, layer.effectParams);
        // Extract basic syntax, assume "color=..." or similar
        // If it returns a chain, we need to adapt.
        // `getFFmpegFilter` returns e.g. "color=...,noise=..."
        
        // Lavfi Input
        inputs.add('-f'); inputs.add('lavfi');
        inputs.add('-i'); inputs.add("$filter"); 
        // Note: EffectService usually returns 1920x1080 source.
        streamName = "$inputIdx:v";
        inputIdx++;
      } else {
        return;
      }
      
      // Calculate Transform
      // Target: Logic Space Canvas (Origin at Intersection Top-Left)
      // Visual Logic TopLeft in Global Space = Intersection.left, Intersection.top
      
      final t = layer.transform ?? MediaTransform.identity();
      
      // Layer Visual Rect (Global Logic Space)
      // Center: (t.tx, t.ty)
      // Size: (VideoW * t.sx, VideoH * t.sy)
      // TopLeft: tx - W/2, ty - H/2
      
      double srcW = (layer.type == LayerType.video) ? videoSize.width : 1920.0;
      double srcH = (layer.type == LayerType.video) ? videoSize.height : 1080.0;
      if (srcW <= 0) srcW = 1920;
      if (srcH <= 0) srcH = 1080;
      
      double visualW = srcW * t.scaleX;
      double visualH = srcH * t.scaleY;
      
      double globalLeft = t.translateX - (visualW / 2);
      double globalTop = t.translateY - (visualH / 2);
      
      // Relative to Canvas (Intersection)
      double relativeX = globalLeft - intersection.left;
      double relativeY = globalTop - intersection.top;
      
      // Scale Filter
      String scaledStream = "${layerName}_scaled";
      // Ensure positive dimensions
      int targetW = visualW.round();
      int targetH = visualH.round();
      if (targetW < 1) targetW = 1;
      if (targetH < 1) targetH = 1;
      
      filterComplex.add("[$streamName]scale=$targetW:$targetH [$scaledStream]");
      
      // Opacity
      String alphaStream = "${layerName}_alpha";
      if (layer.opacity < 1.0) {
         filterComplex.add("[$scaledStream]format=rgba,colorchannelmixer=aa=${layer.opacity} [$alphaStream]");
      } else {
         // Just rename for consistency
         alphaStream = scaledStream;
      }
      
      // Overlay
      String outStream = "${layerName}_comp";
      // x and y can be negative
      filterComplex.add("[$lastStream][$alphaStream]overlay=x=${relativeX.round()}:y=${relativeY.round()}:shortest=0 [$outStream]");
      lastStream = outStream;
    }
    
    // Process Layers Bottom to Top
    processLayer(show.backgroundLayer, "lyr_bg", bgVideoSize);
    processLayer(show.middleLayer, "lyr_md", mdVideoSize);
    processLayer(show.foregroundLayer, "lyr_fg", fgVideoSize);
    
    // Final Scale to Matrix Resolution
    filterComplex.add("[$lastStream]scale=$resW:$resH:flags=lanczos [final]");

    // Build Command
    List<String> args = [
      '-y',
    ];
    args.addAll(inputs);
    args.add('-filter_complex');
    args.add(filterComplex.join(';'));
    args.add('-map'); args.add('[final]');
    args.add('-c:v'); args.add('libx264');
    args.add('-pix_fmt'); args.add('yuv420p');
    args.add('-t'); args.add(maxDuration.toStringAsFixed(2));
    args.add(outputPath);
    
    debugPrint("FFmpeg Render Command: $ffmpeg ${args.join(' ')}");
    
    return Process.run(ffmpeg, args);
  }
}
