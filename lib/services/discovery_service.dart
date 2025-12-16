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
        debugPrint("Socket Event: $event"); // Log every event
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleMessage(datagram);
          } else {
             debugPrint("Socket Data was NULL");
          }
        }
      });

      await _sendDiscoveryPacket();
    } catch (e) {
      debugPrint("Error binding discovery socket 6970: $e");
      // Fallback to random port?
      try {
        _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _socket!.broadcastEnabled = true;
        debugPrint('Fallback Socket bound to ${_socket!.address.address}:${_socket!.port}');

        _socket!.listen((RawSocketEvent event) {
            debugPrint("Fallback Socket Event: $event");
            if (event == RawSocketEvent.read) {
              final datagram = _socket!.receive();
              if (datagram != null) {
                _handleMessage(datagram);
              }
            }
          });
        await _sendDiscoveryPacket();
      } catch (e2) {
         debugPrint("Error binding random socket: $e2");
      }
    }
  }

  Future<void> _sendDiscoveryPacket() async {
    if (_socket == null) return;
    final data = utf8.encode('KINCOM_DISCOVER');
    
    // 1. Send to Global Broadcast (255.255.255.255) - Works on some routers
    try {
      _socket!.send(data, InternetAddress('255.255.255.255'), 6969);
      debugPrint("Sent Global Broadcast KINCOM_DISCOVER");
    } catch (e) {
      debugPrint("Error sending global broadcast: $e");
    }

    // 2. Iterate Interfaces and send to subnet broadcast
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
             // Basic subnet broadcast assumption (x.x.x.255) is often enough for home nets
             // But correct way involves subnet mask which isn't easily exposed in Dart standard lib without calculation assumption
             // We'll try the .255 approach for the last octet as a heuristic fallback if standard Broadcast fails
             
             final ipParts = address.address.split('.');
             if (ipParts.length == 4) {
                ipParts[3] = '255';
                final broadcast = ipParts.join('.');
                try {
                  _socket!.send(data, InternetAddress(broadcast), 6969);
                  debugPrint("Sent Broadcast to $broadcast on ${interface.name}");
                } catch (e) {
                   // ignore
                }
             }
          }
        }
      }
    } catch (e) {
      debugPrint("Error iterating interfaces: $e");
    }
  }

  void _handleMessage(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      debugPrint("RAW UDP from ${datagram.address.address}: '$message'");

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
            width: (json['width'] is int) ? json['width'] : int.tryParse(json['width'].toString()) ?? 0,
            height: (json['height'] is int) ? json['height'] : int.tryParse(json['height'].toString()) ?? 0,
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
