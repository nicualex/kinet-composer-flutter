import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kinet_composer/models/show_manifest.dart';

class DiscoveryService {
  RawDatagramSocket? _socket;
  // Stream to expose newly discovered controllers
  final _controllerStreamController = StreamController<Fixture>.broadcast();
  Stream<Fixture> get controllerStream => _controllerStreamController.stream;

  String? _localIp;

  Future<void> startDiscovery({String? interfaceIp}) async {
    stopDiscovery(); 
    _localIp = interfaceIp;

    if (interfaceIp == null) {
       debugPrint("Discovery Error: No interface IP provided.");
       return;
    }

    try {
      // Bind specifically to the selected Interface IP to ensure routing works correctly.
      // We use reuseAddress: true to minimize conflicts.
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(InternetAddress(interfaceIp), 6038, reuseAddress: true);
        debugPrint('Discovery Socket bound to $interfaceIp:6038');
      } catch (e) {
        debugPrint("Could not bind to $interfaceIp:6038 ($e). Falling back to AnyIPv4.");
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 6038, reuseAddress: true);
        debugPrint('Discovery Socket bound to AnyIPv4:6038');
      }

      socket.broadcastEnabled = true;
      
      socket.listen((e) {
         if (e == RawSocketEvent.read) {
           final datagram = socket.receive();
           if (datagram != null) {
              _handleMessage(datagram);
           }
         }
      });
      
      _socket = socket;

      await _sendDiscoveryPacket(targetIp: interfaceIp);
    } catch (e) {
      debugPrint("Error initializing discovery socket: $e");
    }
  }

  Future<void> _sendDiscoveryPacket({String? targetIp}) async {
    if (_socket == null || targetIp == null) return;
    
    // Variant 1: KiNET v2 (16 bytes) - Little Endian
    List<int> pktV2 = [0x04, 0x01, 0xdc, 0x4a, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]; 
    
    Set<String> targets = {};
    targets.add('255.255.255.255');
    
    final parts = targetIp.split('.');
    if (parts.length == 4) {
       targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
       targets.add('${parts[0]}.${parts[1]}.255.255');
       targets.add('${parts[0]}.255.255.255');
    }

    debugPrint("Discovery Targets: $targets");

    for (int i = 0; i < 5; i++) {
        for (var ip in targets) {
              try {
                // debugPrint("Sending ${pktV2.length} bytes to $ip:6038");
                _socket!.send(pktV2, InternetAddress(ip), 6038);
              } catch (e) {
                 debugPrint("Send Error: $e");
              }
        }
        await Future.delayed(const Duration(milliseconds: 300));
    }
  }
  
  void _handleMessage(Datagram datagram) {
    // Filter Self
    if (_localIp != null && datagram.address.address == _localIp) return; // Silent ignore for self
    
    // Filter Cross-Network Traffic
    if (_localIp != null) {
       final localParts = _localIp!.split('.');
       final remoteParts = datagram.address.address.split('.');
       if (localParts.isNotEmpty && remoteParts.isNotEmpty) {
           if (localParts[0] != remoteParts[0]) {
               debugPrint("Ignored Cross-Network packet from ${datagram.address.address} (Local: $_localIp)");
               return;
           }
       }
    }

    debugPrint("Packet from ${datagram.address.address} (${datagram.data.length} bytes). Hex: ${datagram.data.take(8).map((e)=>e.toRadixString(16).padLeft(2,'0')).join(' ')}");
    
    // Check for KiNET v2 Magic: 04 01 dc 4a
    final data = datagram.data;
    bool isKinet = false;
    if (data.length >= 4) {
      if (data[0] == 0x04 && data[1] == 0x01 && data[2] == 0xdc && data[3] == 0x4a) {
        isKinet = true;
      }
    }

    if (isKinet) {
      debugPrint("Received KiNET v2 Packet from ${datagram.address.address}");
      
      // Parse Payload
      // Header is 16 bytes. Payload starts at 16.
      // Serial Num usually at 16-19.
      String serial = "UnknownSerial";
      if (data.length >= 20) {
         serial = data.sublist(16, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      } else {
         serial = datagram.address.address;
      }

      // Try to find a Name string in the payload
      // Scan for printable ASCII chars sequence > 3 length
      String detectedName = "KiNET Device";
      try {
         // Naive search: Look for longest printable string
         String payloadAscii = String.fromCharCodes(data.map((c) => (c >= 32 && c <= 126) ? c : 0));
         // Split by nulls or non-printables
         final likelyStrings = payloadAscii.split(String.fromCharCode(0)).where((s) => s.length > 2).toList();
         if (likelyStrings.isNotEmpty) {
            // Pick longest or first reasonable one.
            // KiNET names often start later in the packet.
            detectedName = likelyStrings.last; // Often the user-set name is at the end
         }
      } catch (e) {
         debugPrint("Error parsing name: $e");
      }

      final fixture = Fixture(
        id: serial, 
        name: "$detectedName ($serial)", 
        ip: datagram.address.address,
        port: 6038, 
        protocol: 'KiNET v2',
        width: 10,  
        height: 10,
        pixels: [],
      );
      // Emit Controller
      _controllerStreamController.add(Fixture(
        id: serial,
        name: "$detectedName ($serial)",
        ip: datagram.address.address,
        port: 6038,
        protocol: 'KiNET v2',
        width: 10,
        height: 10,
        pixels: [],
      ));
      return;
    }

    // Legacy/JSON Handling
    try {
      final message = utf8.decode(datagram.data);
      debugPrint("RAW UDP from ${datagram.address.address}: '$message'");

      if (message.startsWith('{')) {
        final Map<String, dynamic> json = jsonDecode(message);
        if (json['type'] == 'kinet-player') {
          final fixture = Fixture(
            id: json['id'] ?? datagram.address.address,
            name: json['name'] ?? 'Unknown Device',
            ip: datagram.address.address,
            port: 6038,
            protocol: 'KinetV1',
            width: (json['width'] is int) ? json['width'] : int.tryParse(json['width'].toString()) ?? 0,
            height: (json['height'] is int) ? json['height'] : int.tryParse(json['height'].toString()) ?? 0,
            pixels: [],
          );
          _controllerStreamController.add(fixture);
        }
      }
    } catch (e) {
      debugPrint("Ignored non-UTF8/non-KiNET packet from ${datagram.address.address} (${datagram.data.length} bytes)");
    }
  }

  void stopDiscovery() {
    _socket?.close();
    _socket = null;
  }
  
  Future<void> sendIdentify(String ip, {int r = 0, int g = 0, int b = 255}) async {
     // Ensure we have a valid socket. If discovery is stopped, create a temp one.
     if (_socket == null) {
        try {
           final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
           await _sendIdentifyBurst(socket, ip, r, g, b);
           socket.close();
        } catch (e) {
           debugPrint("Error creating temp socket for identify: $e");
        }
        return; 
     }

     await _sendIdentifyBurst(_socket!, ip, r, g, b);
  }

  Future<void> _sendIdentifyBurst(RawDatagramSocket socket, String ip, int r, int g, int b) async {
      final payload = _generateColorPayload(r, g, b);
      debugPrint("Sending Identify (Blue) to $ip (v1 & v2)...");
      
      // Send v2 (Type 0x0108) - Likely what these devices need
      await _sendKinetV2Dmx(socket, ip, 1, payload);
      
      // Send v1 (Type 0x0101) - Fallback
      await _sendKinetV1Dmx(socket, ip, 1, payload);
  }

  List<int> _generateColorPayload(int r, int g, int b) {
     return List.generate(512, (index) {
        int chan = index % 3;
        if (chan == 0) return r;
        if (chan == 1) return g;
        return b;
     });
  }

  Future<void> sendDmx(String targetIp, int universe, List<int> dmxData) async {
     if (_socket == null) return;
     // Default to v2 for now based on discovery results
     await _sendKinetV2Dmx(_socket!, targetIp, universe, dmxData);
  }

  Future<void> _sendKinetV1Dmx(RawDatagramSocket socket, String targetIp, int universe, List<int> dmxData) async {
     // KiNET v1 DMX Packet
     List<int> packet = [
       0x04, 0x01, 0xdc, 0x4a, // Magic
       0x01, 0x00,             // Ver 1
       0x01, 0x01,             // Type DMX (0x0101)
       0x00, 0x00, 0x00, 0x00, // Seq
       universe & 0xFF,        // Univ
       0x00,                   // Reserved
       0x00, 0x00              // Reserved
     ];
     packet.addAll(dmxData);
     
     try {
       socket.send(packet, InternetAddress(targetIp), 6038);
     } catch (e) {
       debugPrint("Error sending v1 DMX: $e");
     }
  }

  Future<void> _sendKinetV2Dmx(RawDatagramSocket socket, String targetIp, int universe, List<int> dmxData) async {
     // KiNET v2 Port Out (Type 0x0108)
     // Header: Magic(4), Ver(2), Type(2), Seq(4), Univ(4), Port(1), Pad(1), Flags(2), TIMER(2)??
     // Structure varies, but common 'Port Out' is:
     // Magic (4)
     // Ver (2) = 0x0200
     // Type (2) = 0x0801 (LE for 0x0108)
     // Seq (4)
     // Universe (4) - LE
     // Port (1)
     // Pad (1)
     // DMX (512)
     
     List<int> packet = [
       0x04, 0x01, 0xdc, 0x4a,      // Magic
       0x02, 0x00,                  // Ver 2 (LE)
       0x08, 0x01,                  // Type 0x0108 (LE)
       0x00, 0x00, 0x00, 0x00,      // Seq
       universe & 0xFF, 0x00, 0x00, 0x00, // Univ (4 bytes LE)
       0x01,                        // Port (1)
       0x00                         // Pad
     ];
     // Note: v2 header might be larger (24 bytes?) depending on implementation. 
     // Standard v2 PortOut often has Flags(2) + Timer(2) before data?
     // Let's try this standard 20-byte header first.
     
     packet.addAll(dmxData);
     
     try {
       socket.send(packet, InternetAddress(targetIp), 6038);
     } catch (e) {
       debugPrint("Error sending v2 DMX: $e");
     }
  }

  Future<void> setControllerName(String ip, String newName) async {
     if (_socket == null) return;
     
     debugPrint("Sending SetName command to $ip: '$newName'");
     
     // TODO: Implement KiNET 'Set Name' Packet
     // Is it a variation of the DMX packet or a specific Management OpCode?
     // Without the specific OpCode (e.g. 0x000X), sending random packets is risky.
     // For now, we update the local stream if needed or just trust the next discovery scan to pick it up.
     
     /*
     List<int> nameBytes = utf8.encode(newName);
     List<int> packet = [
       0x04, 0x01, 0xdc, 0x4a, // Magic
       0x01, 0x00,             // Ver
       0x??, 0x??,             // Set Name OpCode??
       ...
     ];
     _socket!.send(packet, InternetAddress(ip), 6038);
     */
  }

  void dispose() {
    stopDiscovery();
    _controllerStreamController.close();
  }
}
