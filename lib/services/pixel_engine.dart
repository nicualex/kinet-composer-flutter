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
    
    // 30 FPS = ~33ms
    _timer = Timer.periodic(const Duration(milliseconds: 33), _onTick);
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
    
    _isProcessing = true;
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Capture Frame (High Performance Scale)
      final double scale = 0.2; // 5x Downscale = 25x less data
      final image = await _captureFrame(scale);
      
      // 2. Crop & Sample
      if (image != null) {
        // Rebuild map if needed
        if (_pixelInstructions == null) _rebuildPixelMap(scale);
        
        Rect cropRect = Rect.fromLTRB(
           _renderBounds.left * scale, 
           _renderBounds.top * scale, 
           _renderBounds.right * scale, 
           _renderBounds.bottom * scale
        );
        
        final imageRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
        cropRect = cropRect.intersect(imageRect);

        ui.Image samplingImage = image;
        bool disposedOriginal = false;

        if (cropRect.width > 0 && cropRect.height > 0) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder, cropRect); 
            canvas.translate(-cropRect.left, -cropRect.top);
            canvas.drawImage(image, Offset.zero, Paint());
            final picture = recorder.endRecording();
            samplingImage = await picture.toImage(cropRect.width.toInt(), cropRect.height.toInt());
            
            image.dispose();
            disposedOriginal = true;
        } else {
            image.dispose();
            return;
        }

        await _sampleAndSendFast(samplingImage, cropRect.topLeft.dx.toInt(), cropRect.topLeft.dy.toInt());
        samplingImage.dispose();
        if (!disposedOriginal) image.dispose();
      }
    } catch (e) {
       print("PixelEngine Error: $e");
    } finally {
      _isProcessing = false;
      if (stopwatch.elapsedMilliseconds > 20) {
         print("PixelEngine Slow Frame: ${stopwatch.elapsedMilliseconds}ms");
      }
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
    
    if (_pixelInstructions == null) return;
    
    // Offload to Persistent Isolate (Zero Copy)
    final transferable = TransferableTypedData.fromList([bytes]);
    _processor.processFrame(transferable, width, stride, cropX, cropY);
    
    final tLoop = sw.elapsedMilliseconds - tRead;
    
    // Performance Log
    if (sw.elapsedMilliseconds > 25) {
       print("PixelEngine: Read=${tRead}ms Loop=${tLoop}ms (Async Pushed)");
    }
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
    
    for (var fixture in _manifest!.fixtures) {
       for (var pixel in fixture.pixels) {
          double gx = fixture.x + pixel.x;
          double gy = fixture.y + pixel.y;
          
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
             
             // Allocate 530 bytes (18 Header + 512 Data)
             final buf = Uint8List(530);
             
             // Pre-fill KiNET v2 Header (18 bytes)
             // Magic (4)
             buf[0] = 0x04; buf[1] = 0x01; buf[2] = 0xdc; buf[3] = 0x4a;
             // Ver 2 (2)
             buf[4] = 0x02; buf[5] = 0x00;
             // Type PortOut (2)
             buf[6] = 0x08; buf[7] = 0x01;
             // Seq (4) - 0
             // Univ (4) - LE
             int u = pixel.dmxInfo.universe;
             buf[12] = u & 0xFF;
             buf[13] = (u >> 8) & 0xFF;
             buf[14] = (u >> 16) & 0xFF;
             buf[15] = (u >> 24) & 0xFF;
             // Port (1) - 1
             buf[16] = 0x01;
             // Pad (1)
             // bufferMap[key] = bufIdx;
             
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

