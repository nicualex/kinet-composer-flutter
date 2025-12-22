import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// DMX Sender Service (Runs in Isolate)
/// Offloads network syscalls from UI thread.
class DmxSender {
  Isolate? _isolate;
  SendPort? _sendPort;
  
  bool get isReady => _sendPort != null;
  SendPort? get isolateSendPort => _sendPort;

  Future<void> start() async {
    if (_isolate != null) return;
    
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_dmxIsolateEntry, receivePort.sendPort);
    
    // Handshake: Wait for Isolate to send its SendPort
    _sendPort = await receivePort.first as SendPort;
    print("DMX Isolate Started.");
  }

  void stop() {
    _sendPort?.send("STOP");
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  /// Fire and Forget packet send
  void sendPacket(String ip, List<int> packet) {
    _sendPort?.send([ip, packet]);
  }
  
  /// Optimized for Zero-Alloc buffers
  /// [packet] should be a Uint8List ideally.
  void sendBytes(String ip, Uint8List packet) {
     _sendPort?.send(DmxMessage(ip, packet));
  }

  // ---- ISOLATE LOGIC ----
  static void _dmxIsolateEntry(SendPort mainSendPort) async {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort); // Send our address back
    
    RawDatagramSocket? socket;
    
    try {
       // Bind AnyIPv4
       socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
       socket.writeEventsEnabled = false; // Optimization?
       print("DMX Sender Isolate Socket Bound.");
    } catch (e) {
       print("DMX Isolate Failed to Bind: $e");
       return;
    }

    await for (final msg in port) {
       if (msg == "STOP") {
          break;
       }
       
       try {
         if (msg is DmxMessage) {
            final address = InternetAddress(msg.ip);
            socket.send(msg.data, address, 6038);
         } else if (msg is List) {
           // [String ip, List<int> data]
           final String ip = msg[0];
           final List<int> data = msg[1];
           socket.send(data, InternetAddress(ip), 6038);
         }
       } catch (e) {
          // Swallow network errors to keep loop fast?
          // print("Send Error: $e"); 
       }
    }
    
    socket.close();
    print("DMX Isolate Shutdown.");
  }
}

class DmxMessage {
  final String ip;
  final Uint8List data;
  DmxMessage(this.ip, this.data);
}
