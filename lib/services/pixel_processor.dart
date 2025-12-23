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
    
    if (!_readyCompleter.isCompleted) {
       _readyCompleter.complete();
    }
    print("Pixel Processor Isolate Started.");
  }

  void stop() {
    _sendPort?.send("STOP");
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  void updateManifest(Int32List instructions, List<BufferConfig> buffers) {
    _sendPort?.send(ManifestUpdateMessage(instructions, buffers));
  }

  void processFrame(TransferableTypedData transferable, int width, int stride, int cropX, int cropY) {
    _sendPort?.send(FrameMessage(transferable, width, stride, cropX, cropY));
  }

  // ---- ISOLATE LOGIC ----
  static void _processorEntry(SendPort mainSendPort) async {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort); 
    
    SendPort? dmxPort;
    Int32List? instructions;
    
    List<Uint8List> dmxBuffers = [];
    List<String> bufferIps = [];
    
    int frameCount = 0;
    
    await for (final msg in port) {
       if (msg is DmxInitMessage) {
          dmxPort = msg.dmxPort;
       }
       else if (msg == "STOP") {
          break;
       }
       else if (msg is ManifestUpdateMessage) {
          instructions = msg.instructions;
          print("PP: Manifest Updated. Instructions: ${instructions.length ~/ 4} pixels.");
          
          dmxBuffers.clear();
          bufferIps.clear();
          
          for (var cfg in msg.buffers) {
             final buf = Uint8List(530); 
             // Header
             buf[0] = 0x04; buf[1] = 0x01; buf[2] = 0xdc; buf[3] = 0x4a; // Magic
             buf[4] = 0x02; buf[5] = 0x00; // Ver 2
             buf[6] = 0x08; buf[7] = 0x01; // PortOut
             buf[12] = 0xFF; buf[13] = 0xFF; buf[14] = 0xFF; buf[15] = 0xFF; // Univ
             buf[16] = 0x01; // Port
             buf[20] = 0x00; buf[21] = 0x02; // Length 512
             
             dmxBuffers.add(buf);
             bufferIps.add(cfg.ip);
          }
       }
       else if (msg is FrameMessage) {
          if (dmxPort == null || instructions == null) continue;
          
          frameCount++;
          final bytes = msg.transferable.materialize().asUint8List();
          final width = msg.width;
          final stride = msg.stride;
          final cropX = msg.cropX;
          final cropY = msg.cropY;
          
          // Debug 1x per sec (~30 frames)
          bool debug = frameCount % 30 == 0;
          if (debug) {
             print("PP FRAME: Size=${bytes.length} W=$width Stride=$stride Crop($cropX, $cropY) Instr=${instructions.length ~/ 4}");
          }
          
          int executed = 0;
          int skipped = 0;
          
          final int instrLen = instructions.length;
          for (int i = 0; i < instrLen; i += 4) {
             int lx = instructions[i] - cropX;
             int ly = instructions[i+1] - cropY;
             
             int offset = (ly * stride) + (lx * 4);
             
             if (offset >= 0 && offset + 3 < bytes.length) {
                 int bufIdx = instructions[i+2];
                 int chanIdx = instructions[i+3];
                 
                 final buf = dmxBuffers[bufIdx];
                 int writePos = 24 + chanIdx;
                 
                 if (writePos + 2 < buf.length) {
                    // Start of Payload is 24.
                    buf[writePos] = bytes[offset];
                    buf[writePos+1] = bytes[offset+1];
                    buf[writePos+2] = bytes[offset+2];
                    executed++;
                 }
             } else {
                 skipped++;
                 if (skipped < 5 && debug) { // Log first few skips
                     print("PP OOB: lx:$lx ly:$ly Stride:$stride Len:${bytes.length} Offset:$offset");
                 }
             }
          }
          
          if (debug) print("PP STATS: Exec:$executed Skipped:$skipped");
          
          // Flush
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
