import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kinet_composer/models/show_manifest.dart';

class DiscoveryService {
  RawDatagramSocket? _socket;
  final StreamController<Fixture> _deviceStreamController = StreamController.broadcast();

  Stream<Fixture> get deviceStream => _deviceStreamController.stream;

  Future<void> startDiscovery() async {
    stopDiscovery(); // Ensure clean state

    try {
      // Bind to 6970 or 0 (random) if busy. Electron tried 6970.
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 6970);
      _socket!.broadcastEnabled = true;

      debugPrint('Discovery Socket bound to ${_socket!.address.address}:${_socket!.port}');

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleMessage(datagram);
          }
        }
      });

      _sendDiscoveryPacket();
    } catch (e) {
      debugPrint("Error binding discovery socket: $e");
      // Fallback to random port?
      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _socket!.broadcastEnabled = true;
         _socket!.listen((RawSocketEvent event) {
            if (event == RawSocketEvent.read) {
              final datagram = _socket!.receive();
              if (datagram != null) {
                _handleMessage(datagram);
              }
            }
          });
        _sendDiscoveryPacket();
      } catch (e2) {
         debugPrint("Error binding random socket: $e2");
      }
    }
  }

  void _sendDiscoveryPacket() {
    if (_socket == null) return;
    final data = utf8.encode('KINCOM_DISCOVER');
    
    // Broadcast to 255.255.255.255 port 6969
    try {
      _socket!.send(data, InternetAddress('255.255.255.255'), 6969);
      debugPrint("Sent Global Broadcast KINCOM_DISCOVER");
    } catch (e) {
      debugPrint("Error sending global broadcast: $e");
    }

    // TODO: Determine network specific broadcast addresses if global fails or isn't routed.
    // For now, global broadcast is often sufficient on local LANs.
  }

  void _handleMessage(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      debugPrint("UDP Message from ${datagram.address.address}: $message");

      if (message.startsWith('{')) {
        final Map<String, dynamic> json = jsonDecode(message);
        if (json['type'] == 'kinet-player') {
          // Construct Fixture from discovery data
          // Expecting minimal info: { id, name, type, width, height... }
          // We can map this to a Fixture object.
          
          final fixture = Fixture(
            id: json['id'] ?? datagram.address.address, // Fallback ID
            name: json['name'] ?? 'Unknown Device',
            ip: datagram.address.address,
            port: 6038, // Default KiNET port
            protocol: 'KinetV1', // Default
            width: json['width'] ?? 0,
            height: json['height'] ?? 0,
            pixels: [], // Discovery doesn't usually send full pixel map
          );
          
          _deviceStreamController.add(fixture);
        }
      }
    } catch (e) {
      debugPrint("Error parsing discovery message: $e");
    }
  }

  void stopDiscovery() {
    _socket?.close();
    _socket = null;
  }
  
  void dispose() {
    stopDiscovery();
    _deviceStreamController.close();
  }
}
