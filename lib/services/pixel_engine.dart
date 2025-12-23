import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';

import '../models/show_manifest.dart';
import '../models/layer_config.dart';
import 'effect_service.dart';
import 'discovery_service.dart';
import 'dmx_sender.dart';
import 'pixel_processor.dart';

/// The Heart of the Lighting System.
/// Renders effects to a virtual canvas, samples pixels based on fixture patches,
/// and sends data via KiNET v2.
class PixelEngine {
  final DiscoveryService _discovery;
  final DmxSender _sender = DmxSender();
  final PixelProcessor _processor = PixelProcessor();
  
  // State
  ShowManifest? _manifest;
  bool _isRunning = false;
  Timer? _timer;
  bool _isProcessing = false;
  int _lastFrameTime = 0;
  
  // Overload Warning (True if frames are being dropped)
  final ValueNotifier<bool> overloadWarning = ValueNotifier(false);
  
  // Zero-Alloc State
  // Flattened Instructions: [offsetX, offsetY, bufferIndex, channelIndex]
  // 4 integers per pixel
  Int32List? _pixelInstructions;
  
  // Pre-allocated Buffers
  final List<Uint8List> _dmxBuffers = [];
  final List<String> _bufferIps = [];
  final List<int> _bufferUniverses = [];
  
  // Render Source
  GlobalKey? _repaintBoundaryKey;
  GlobalKey? get repaintBoundaryKey => _repaintBoundaryKey;
  
  // Map for Legacy Bounds Calc only
  final Map<String, List<Point<int>>> _pixelMap = {};
  
  // Transformation Matrix for Global Layout
  Rect _renderBounds = Rect.zero;
  
  PixelEngine(this._discovery);

  void setBoundary(GlobalKey key) {
     _repaintBoundaryKey = key;
  }

  void setManifest(ShowManifest manifest) {
    _manifest = manifest;
    _pixelInstructions = null; // Mark dirty
  }
  
  void start() async {
    if (_isRunning) return;
    _isRunning = true;
    
    await _sender.start(); 
    if (_sender.isolateSendPort != null) {
       await _processor.start(_sender.isolateSendPort!);
    }
    
    print("PixelEngine: STARTED. Performance Mode: 15FPS, 0.05 Scale (Ultra-Fast).");
    // Run loop at 60Hz, but throttle inside _onTick
    _timer = Timer.periodic(const Duration(milliseconds: 16), _onTick);
  }

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    _processor.stop();
    _sender.stop();
    overloadWarning.value = false;
  }

  void _onTick(Timer timer) async {
    if (_manifest == null || _repaintBoundaryKey == null) return;
    
    if (_isProcessing) {
       if (!overloadWarning.value) overloadWarning.value = true;
       return;
    }
    
    if (overloadWarning.value) overloadWarning.value = false;
    

    // Throttling: Cap at 15 FPS (66ms) - Give UI thread breathing room!
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameTime < 66) return;
    _lastFrameTime = now;
    
    _isProcessing = true;
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Capture Frame
      final double scale = 0.05; // 20x Downscale for Max Speed
      final image = await _captureFrame(scale);
      
      if (image != null) {
          final tCapture = stopwatch.elapsedMilliseconds;
          
          final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final tByteData = stopwatch.elapsedMilliseconds - tCapture;
          
          if (byteData != null) {
              final transferable = TransferableTypedData.fromList([byteData.buffer.asUint8List()]);
              _processor.processFrame(transferable, image.width, image.width * 4, 0, 0);
              
              if (stopwatch.elapsedMilliseconds > 20) {
                 print("PixelEngine: Cap=${tCapture}ms Bytes=${tByteData}ms Total=${stopwatch.elapsedMilliseconds}ms");
              }
          }
          image.dispose();
      }
    } catch (e) {
       print("PixelEngine Error: $e");
    } finally {
       _isProcessing = false;
       stopwatch.stop();
    }
  }

  Future<ui.Image?> _captureFrame(double scale) async {
    final context = _repaintBoundaryKey!.currentContext;
    if (context == null) return null;
    
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    return await boundary.toImage(pixelRatio: scale); 
  }

  Future<void> _sampleAndSendFast(ui.Image image, int cropX, int cropY) async {
    final sw = Stopwatch()..start();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return;
    final tRead = sw.elapsedMilliseconds;
    
    final bytes = byteData.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    final int stride = width * 4;
    
    // PROBE END
    
    if (_pixelInstructions == null) return;
    
    // Offload to Persistent Isolate (Zero Copy)
    final transferable = TransferableTypedData.fromList([bytes]);
    _processor.processFrame(transferable, width, stride, cropX, cropY);
    
    final tLoop = sw.elapsedMilliseconds - tRead;
    

    sw.stop();
  }

  void _rebuildPixelMap([double scale = 0.2]) {
    _pixelMap.clear();
    if (_manifest == null) return;
    
    // 1. Calculate Bounds
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    
    // 2. Build Instructions
    List<int> instructions = [];
    _dmxBuffers.clear();
    _bufferIps.clear();
    _bufferUniverses.clear();
    
    // Map Identifier string "IP:Univ" -> Buffer Index
    Map<String, int> bufferMap = {};
    List<BufferConfig> bufferConfigs = [];
    
    const double kGridSize = 16.0; // Stride MUST match Setup/Video Tab visuals
    
    for (var fixture in _manifest!.fixtures) {
       for (var pixel in fixture.pixels) {
          // Apply Stride
          final px = pixel.x * kGridSize;
          final py = pixel.y * kGridSize;
           
          // Apply Rotation (Degrees to Radians)
          // standard 2D rotation: x' = x cos - y sin, y' = x sin + y cos
          final rad = fixture.rotation * (pi / 180.0);
          final cosT = cos(rad);
          final sinT = sin(rad);
           
          // Rotate around Fixture Origin (Top-Left)
          // Since px, py are offsets from origin, we just rotate them
          final rx = (px * cosT) - (py * sinT);
          final ry = (px * sinT) + (py * cosT);

          double gx = fixture.x + rx;
          double gy = fixture.y + ry;
          
          if (gx < minX) minX = gx;
          if (gx > maxX) maxX = gx;
          if (gy < minY) minY = gy;
          if (gy > maxY) maxY = gy;
          
          // Scaled Coords (Integer for lookup)
          int sx = (gx * scale).round();
          int sy = (gy * scale).round();
          
          // Resolve Buffer
          String key = "${fixture.ip}:${pixel.dmxInfo.universe}";
          int bufIdx;
          if (bufferMap.containsKey(key)) {
             bufIdx = bufferMap[key]!;
          } else {
             bufIdx = _dmxBuffers.length;
             bufferMap[key] = bufIdx;
             
             // WE DO NOT ALLOCATE BUFFER HERE ANYMORE.
             // We just track the config.
             
             _dmxBuffers.add(Uint8List(0)); // Dummy placeholder
             _bufferIps.add(fixture.ip);
             _bufferUniverses.add(pixel.dmxInfo.universe);
             
             bufferConfigs.add(BufferConfig(fixture.ip, pixel.dmxInfo.universe));
          }
          
          // Channel (1-based -> 0-based)
          int chan = pixel.dmxInfo.channel - 1;
          if (chan < 0 || chan > 509) continue; // Safety
          
          instructions.add(sx);      // 0: X
          instructions.add(sy);      // 1: Y
          instructions.add(bufIdx);  // 2: Buffer
          instructions.add(chan);    // 3: Channel
       }
    }
    
    if (minX == double.infinity) {
       _renderBounds = Rect.zero;
       _pixelInstructions = Int32List(0);
    } else {
       final pad = 10.0;
       _renderBounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
       
       _pixelInstructions = Int32List.fromList(instructions);
       
       // Push Config to Isolate
       _processor.updateManifest(_pixelInstructions!, bufferConfigs);
    }
  }

}
