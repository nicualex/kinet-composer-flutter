import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dmx_sender.dart';

/// Pixel Processor Service (Runs in Persistent Isolate)
/// Handles the "Sample -> Packetize -> Send" pipeline off-thread.
class PixelProcessor {
  Isolate? _isolate;
  SendPort? _sendPort;
  
  // Handshake to ensure Isolate is ready
  final Completer<void> _readyCompleter = Completer();
  Future<void> get ready => _readyCompleter.future;

  // Track processing time
  int _lastDuration = 0;
  int get lastDuration => _lastDuration;

  Future<void> start(SendPort dmxSendPort) async {
    if (_isolate != null) return;
    
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_processorEntry, receivePort.sendPort);
    
    // Handshake
    _sendPort = await receivePort.first as SendPort;
    
    // Pass the DMX Sender Port to the Processor
    _sendPort!.send(DmxInitMessage(dmxSendPort));
    
    _readyCompleter.complete();
    print("Pixel Processor Isolate Started.");
  }

  void stop() {
    _sendPort?.send("STOP");
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  /// Update the Mapping Manifest
  /// This is expensive, but only happens when patching changes.
  void updateManifest(Int32List instructions, List<BufferConfig> buffers) {
    _sendPort?.send(ManifestUpdateMessage(instructions, buffers));
  }

  /// Process a frame
  /// Fast path!
  /// Uses TransferableTypedData to avoid copying bytes from Main -> Isolate
  void processFrame(TransferableTypedData transferable, int width, int stride, int cropX, int cropY) {
    _sendPort?.send(FrameMessage(transferable, width, stride, cropX, cropY));
  }

  // ---- ISOLATE LOGIC ----
  static void _processorEntry(SendPort mainSendPort) async {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort); 
    
    SendPort? dmxPort;
    Int32List? instructions;
    
    // Internal State
    // We hold the "Working Buffers" here to avoid allocation per frame
    List<Uint8List> dmxBuffers = [];
    List<String> bufferIps = [];
    // We pre-build the headers, so we just need to poke the RGB data
    
    await for (final msg in port) {
       if (msg == "STOP") break;
       
       if (msg is DmxInitMessage) {
          dmxPort = msg.dmxPort;
       } 
       else if (msg is ManifestUpdateMessage) {
          instructions = msg.instructions;
          
          // Re-allocate buffers based on config
          dmxBuffers.clear();
          bufferIps.clear();
          
          for (var cfg in msg.buffers) {
             final buf = Uint8List(530); // 18 header + 512 data
             
             // Pre-fill KiNET v2 Header
             // Magic (4)
             buf[0] = 0x04; buf[1] = 0x01; buf[2] = 0xdc; buf[3] = 0x4a;
             // Ver 2 (2)
             buf[4] = 0x02; buf[5] = 0x00;
             // Type PortOut (2)
             buf[6] = 0x08; buf[7] = 0x01;
             // Seq (4) - 0
             // Univ (4) - LE
             int u = cfg.universe;
             buf[12] = u & 0xFF;
             buf[13] = (u >> 8) & 0xFF;
             buf[14] = (u >> 16) & 0xFF;
             buf[15] = (u >> 24) & 0xFF;
             // Port (1) - 1
             buf[16] = 0x01;
             // Pad (1)
             // buf[17] = 0x00;
             
             dmxBuffers.add(buf);
             bufferIps.add(cfg.ip);
          }
       }
       else if (msg is FrameMessage) {
          if (dmxPort == null || instructions == null) continue;
          
          // Materialize bytes (Move semantics)
          final bytes = msg.transferable.materialize().asUint8List();
          
          final width = msg.width;
          final stride = msg.stride;
          final cropX = msg.cropX;
          final cropY = msg.cropY;
           // We don't need height, just robust bounds checks
          
          final int len = instructions.length;
          final int instrLen = len; 
          // Assuming instructions is flat
          
          for (int i = 0; i < instrLen; i += 4) {
             int lx = instructions[i] - cropX;
             int ly = instructions[i+1] - cropY;
             
             // Fast bounds check? logic is complex here because we don't have height passed
             // But we have bytes.length
             int offset = (ly * stride) + (lx * 4);
             
             if (offset >= 0 && offset + 3 < bytes.length) {
                 int bufIdx = instructions[i+2];
                 int chanIdx = instructions[i+3];
                 
                 final buf = dmxBuffers[bufIdx];
                 int writePos = 18 + chanIdx;
                 
                  // No branching if possible
                 buf[writePos] = bytes[offset];
                 buf[writePos+1] = bytes[offset+1];
                 buf[writePos+2] = bytes[offset+2];
             }
          }
          
          // Flush to Network Isolate
          for (int i = 0; i < dmxBuffers.length; i++) {
              dmxPort.send([bufferIps[i], dmxBuffers[i]]);
          }
       }
    }
    print("Pixel Processor Shut Down.");
  }
}

class DmxInitMessage {
  final SendPort dmxPort;
  DmxInitMessage(this.dmxPort);
}

class ManifestUpdateMessage {
  final Int32List instructions;
  final List<BufferConfig> buffers;
  ManifestUpdateMessage(this.instructions, this.buffers);
}

class BufferConfig {
  final String ip;
  final int universe;
  BufferConfig(this.ip, this.universe);
}

class FrameMessage {
  final TransferableTypedData transferable;
  final int width;
  final int stride;
  final int cropX;
  final int cropY;
  FrameMessage(this.transferable, this.width, this.stride, this.cropX, this.cropY);
}
