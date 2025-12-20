import 'dart:async';
import 'dart:convert'; // Added for SystemEncoding
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart';

import '../models/layer_config.dart';
import '../state/show_state.dart';

class RenderService {
  final ShowState showState;
  final GlobalKey repaintBoundaryKey;

  RenderService(this.showState, this.repaintBoundaryKey);

  // Status Callback
  Function(String status, double progress)? onProgress;

  Future<void> renderShow({
    required String outputPath,
    required int width,
    required int height,
    required int fps,
    required bool motionInterpolation,
    required Map<LayerTarget, Player> players,
  }) async {
    // 1. Setup
    onProgress?.call("Initializing...", 0.0);
    
    // Create Temp Dir
    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory('${tempDir.path}/frames_${DateTime.now().millisecondsSinceEpoch}');
    await framesDir.create();

    try {
      // 2. Determine Duration
      double maxDuration = 10.0; 
      bool hasVideo = false;
      if (players.isNotEmpty) {
         for (var player in players.values) {
             if (player.state.duration.inSeconds > 0) {
                 final d = player.state.duration.inMilliseconds / 1000.0;
                 if (!hasVideo || d > maxDuration) {
                    maxDuration = d;
                 }
                 hasVideo = true;
             }
         }
      }

      // 3. PREPARE DIMENSIONS
      // Trigger "Render Mode" in UI (removes padding) and wait for layout
      showState.setOverrideTime(0.0);
      final preCompleter = Completer<void>();
      SchedulerBinding.instance.addPostFrameCallback((_) => preCompleter.complete());
      await preCompleter.future;
      await Future.delayed(const Duration(milliseconds: 100)); // Extra safety for layout build

      // We must match the captured raw bytes EXACTLY to the ffmpeg input size.
      // 1. Get Boundary Size
      RenderRepaintBoundary? boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception("Could not find RepaintBoundary");
      
      // 2. Calculate PIXEL RATIO to achieve target Width
      // targetWidth = boundaryWidth * ratio
      // ratio = targetWidth / boundaryWidth
      double calcRatio = width / boundary.size.width; 
      
      // 3. Capture TEST Frame to get exact integer dimensions
      // Flutter's toImage might round dimensions resulting in off-by-one errors if we just guess.
      ui.Image testImage = await boundary.toImage(pixelRatio: calcRatio);
      int actualW = testImage.width;
      int actualH = testImage.height;
      testImage.dispose();
      
      debugPrint("Render Info: Target ${width}x$height. Boundary ${boundary.size}. Ratio $calcRatio. Actual Input ${actualW}x$actualH");

      // 4. Start FFmpeg Process
      // Construct Filter Chain
      // 1. Bicubic Scaling for decent downsizing quality
      // 2. Gaussian Blur (sigma 0.8) to soften artifacts/edges
      String filter = 'scale=$width:$height:flags=bicubic,gblur=sigma=0.8:steps=1'; 
      
      // Removed minterpolate to prevent choppiness/artifacts
      // if (motionInterpolation) ...

      // -f rawvideo -pixel_format rgba -video_size {actualW}x{actualH} -framerate FPS -i -
      List<String> args = [
        '-f', 'rawvideo',
        '-pixel_format', 'rgba',
        '-video_size', '${actualW}x${actualH}',
        '-framerate', '$fps',
        '-i', '-', // Read from Stdin
        
        // Balanced Settings
        '-c:v', 'libx264',
        '-crf', '21',        // Good Quality
        '-preset', 'veryfast', // Fast but reasonable
        '-tune', 'film',
        
        '-pix_fmt', 'yuv420p',
        '-vf', filter,
        outputPath,
        '-y'
      ];
      
      debugPrint("Starting FFmpeg: ffmpeg ${args.join(' ')}");
      
      final process = await Process.start('ffmpeg', args);
      
      process.stderr.transform(SystemEncoding().decoder).listen((data) {
         debugPrint("FFmpeg STDERR: $data");
      });

      // 5. Frame Loop
      int totalFrames = (maxDuration * fps).ceil();
      double step = 1.0 / fps;

      for (int i = 0; i < totalFrames; i++) {
        double t = i * step;
        
        onProgress?.call("Rendering Frame $i / $totalFrames", i / totalFrames);

        // A. Seek / Set Time
        await _seekAll(t, players);
        
        // B. Wait for Texture Update
        if (hasVideo) {
           await Future.delayed(const Duration(milliseconds: 20)); 
        } else {
           final completer = Completer<void>();
           SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
           await completer.future;
        } 
        
        // C. Capture Frame (Use Calculated Ratio)
        await _pipeFrameToProcess(process, calcRatio);
      }
      
      onProgress?.call("Finalizing Video...", 1.0);
      
      // 6. Close Pipe
      await process.stdin.close();
      final exitCode = await process.exitCode;
      
      if (exitCode == 0) {
         debugPrint("Encode Success");
      } else {
         throw Exception("FFmpeg exited with code $exitCode");
      }
      
    } catch (e) {
      debugPrint("Render Error: $e");
      rethrow;
    } finally {
       showState.setOverrideTime(null);
       try {
          if (await framesDir.exists()) {
             await framesDir.delete(recursive: true);
          }
       } catch (_) {}
    }
  }

  Future<void> _seekAll(double t, Map<LayerTarget, Player> players) async { 
     showState.setOverrideTime(t);
     
     List<Future> seeks = [];
     for(var player in players.values) {
        seeks.add(player.seek(Duration(milliseconds: (t * 1000).toInt())));
     }
     await Future.wait(seeks);
  }

  Future<void> _pipeFrameToProcess(Process process, double pixelRatio) async {
    RenderRepaintBoundary? boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    
    if (byteData != null) {
       process.stdin.add(byteData.buffer.asUint8List());
    }
    image.dispose();
  }
}
