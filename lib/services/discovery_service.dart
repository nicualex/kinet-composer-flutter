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
    
    // Variant 1: KiNET v2 (16 bytes) - Standard
    List<int> pktV2 = [0x04, 0x01, 0xdc, 0x4a, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]; 
    
    // Variant 2: KiNET v3 (Ethernet I/O) - From Spec
    // Magic: 0x04AD1344 (LE: 44 13 AD 04)
    // Ver: 0x0002 (LE: 02 00)
    // Type: 0x0001 (LE: 01 00)
    // Seq: 0
    List<int> pktV3 = [
       0x44, 0x13, 0xad, 0x04, // Magic
       0x02, 0x00,             // Ver 2
       0x01, 0x00,             // Type 1 (Discovery)
       0x00, 0x00, 0x00, 0x00, // Seq
       0x00, 0x00, 0x00, 0x00, // Padding/Reserved
       0x00, 0x00, 0x00, 0x00
    ];

    Set<String> targets = {};
    targets.add('255.255.255.255');
    
    final parts = targetIp.split('.');
    if (parts.length == 4) {
       targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
       targets.add('${parts[0]}.${parts[1]}.255.255');
       targets.add('${parts[0]}.255.255.255');
    }

    debugPrint("Discovery Targets: $targets");

    for (int i = 0; i < 3; i++) {
        for (var ip in targets) {
              try {
                final addr = InternetAddress(ip);
                _socket!.send(pktV2, addr, 6038);
                _socket!.send(pktV3, addr, 6038);
              } catch (e) {
                 debugPrint("Send Error: $e");
              }
        }
        await Future.delayed(const Duration(milliseconds: 300));
    }
  }
  
  void _handleMessage(Datagram datagram) {
    if (_localIp != null && datagram.address.address == _localIp) return;
    
    final data = datagram.data;
    if (data.length < 16) return;
    
    // Check Magic
    // v2: 04 01 dc 4a
    bool isV2 = (data[0] == 0x04 && data[1] == 0x01 && data[2] == 0xdc && data[3] == 0x4a);
    // v3: 44 13 ad 04 (0x04AD1344 LE)
    bool isV3 = (data[0] == 0x44 && data[1] == 0x13 && data[2] == 0xad && data[3] == 0x04);

    if (isV3) {
       _handleV3Packet(datagram);
       return;
    }

    if (isV2) {
       _handleV2Packet(datagram);
       return;
    }

    // JSON Fallback
    try {
      final message = utf8.decode(datagram.data);
      if (message.startsWith('{')) {
        final Map<String, dynamic> json = jsonDecode(message);
        if (json['type'] == 'kinet-player') {
          _controllerStreamController.add(Fixture(
            id: json['id'] ?? datagram.address.address,
            name: json['name'] ?? 'Unknown Device',
            ip: datagram.address.address,
            macAddress: "",
            firmwareVersion: "",
            port: 6038,
            protocol: 'KinetV1',
            width: (json['width'] is int) ? json['width'] : int.tryParse(json['width'].toString()) ?? 0,
            height: (json['height'] is int) ? json['height'] : int.tryParse(json['height'].toString()) ?? 0,
            pixels: [],
          ));
        }
      }
    } catch (_) {}
  }

  void _handleV3Packet(Datagram d) async {
       final data = d.data;
       int universe = 0;
       if (data.length >= 74) {
          universe = data[70] | (data[71] << 8) | (data[72] << 16) | (data[73] << 24);
       }
       
       String serial = "Unknown";
       if (data.length >= 70) {
           serial = data.sublist(66, 70).map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
       } else {
           serial = d.address.address;
       }

       String deviceName = "Unknown Device";
       int nameStart = 74;
       try {
         int nullTerm = data.indexOf(0, nameStart);
         if (nullTerm != -1) {
            deviceName = String.fromCharCodes(data.sublist(nameStart, nullTerm));
         }
       } catch (e) {}
       
       // MAC Address (Offset 58, 6 bytes)
       String mac = "00:00:00:00:00:00";
       if (data.length >= 64) {
          mac = data.sublist(58, 64).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
       }
       // Fallback ARP
       if (mac == "00:00:00:00:00:00") {
         mac = await _resolveMacFromIp(d.address.address);
       }
      
       String fwVer = "N/A"; // Parse if known

       final fixture = Fixture(
          id: "${serial}_${d.address.address}",
          name: deviceName,
          ip: d.address.address,
          macAddress: mac,
          firmwareVersion: fwVer,
          port: 6038,
          protocol: "KiNETv3",
          width: 100, height: 100, pixels: [],
          universe: universe, 
          dmxAddress: 1 
       );
       _controllerStreamController.add(fixture);
   }

   void _handleV2Packet(Datagram d) async {
      final data = d.data;
      String serial = "UnknownSerial";
      
      // DEBUG: RAW DUMP
      debugPrint("V2 RAW: ${data.map((e)=>e.toRadixString(16).padLeft(2,'0')).join(' ')}");

      if (data.length >= 32) {
         String part1 = data.sublist(28, 30).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
         String part2 = data.sublist(24, 28).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
         serial = "$part1:$part2";
      } else if (data.length >= 20) {
          serial = data.sublist(16, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
      } else {
         serial = d.address.address;
      }
      
      int universe = 0;
      if (data.length >= 36) {
          universe = data[32] | (data[33] << 8) | (data[34] << 16) | (data[35] << 24);
      }

       String deviceName = "KiNET Device";
       try {
         String payloadAscii = String.fromCharCodes(data.map((c) => (c >= 32 && c <= 126) ? c : 0));
         final likelyStrings = payloadAscii.split(String.fromCharCode(0)).where((s) => s.length > 2).toList();
         if (likelyStrings.isNotEmpty) deviceName = likelyStrings.last;
       } catch (_) {}
      
      // Resolve MAC
      String mac = await _resolveMacFromIp(d.address.address);
      
      String fwVer = "N/A";
      
      // 1. Try ASCII "SFT-" or "A:" parsing (Common in KiNET v2/PDS)
      try {
         String cleanAscii = String.fromCharCodes(data.map((c) => (c >= 32 && c <= 126) ? c : 0)); // Replace non-printables with null
         List<String> tokens = cleanAscii.split(String.fromCharCode(0)).where((t) => t.trim().isNotEmpty).toList();
         
         String? sft;
         String? verMajor;
         String? verMinor;

         for (String t in tokens) {
             if (t.contains("SFT-")) {
                 final match = RegExp(r"(SFT-[\w-]+)").firstMatch(t);
                 if (match != null) sft = match.group(1);
                 else {
                    sft = t.trim().replaceAll(RegExp(r'^[^a-zA-Z0-9]+'), ''); // Strip leading junk like #:
                 }
             }
             
             if (t.contains("A:")) {
                 // FORMAT: A:9
                 final match = RegExp(r"A:(\d+)").firstMatch(t);
                 if (match != null) verMajor = match.group(1);
             }
             
             if (t.contains("B:")) {
                 // FORMAT: B:4
                 final match = RegExp(r"B:(\d+)").firstMatch(t);
                 if (match != null) verMinor = match.group(1);
             }
         }
         
         if (sft != null) {
            fwVer = sft;
            if (verMajor != null && verMinor != null) {
               fwVer += " $verMajor.$verMinor"; // SFT-xxxx 9.4
            } else if (verMajor != null) {
               fwVer += " $verMajor";
            }
         }
      } catch (_) {}

      // 2. Binary fallback (Heuristic)
      if (fwVer == "N/A" && mac != "00:00:00:00:00:00") {
         try {
             List<int> macBytes = mac.split(':').map((e) => int.parse(e, radix: 16)).toList();
             // Find sequence
             int matchIndex = -1;
             for (int i=0; i <= data.length - macBytes.length; i++) {
                 bool match = true;
                 for (int j=0; j<macBytes.length; j++) {
                    if (data[i+j] != macBytes[j]) { match = false; break; }
                 }
                 if (match) { matchIndex = i; break; }
             }
             
             if (matchIndex != -1 && matchIndex + 6 + 2 <= data.length) {
                // FW Version is likely the next 2 bytes (LE)
                int minor = data[matchIndex + 6];
                int major = data[matchIndex + 7];
                fwVer = "$major.$minor";
                debugPrint("Parsed FW from Offset ${matchIndex+6}: $fwVer");
             }
         } catch (_) {}
      }

      final fixture = Fixture(
         id: serial, // Refactored to use Serial Only (was ${serial}_${d.address.address})
         name: deviceName,
         ip: d.address.address,
         macAddress: mac,
         firmwareVersion: fwVer,
         port: 6038,
         protocol: "KiNETv2",
         width: 10, height: 10,  // Checked: 10x10 Default
         pixels: [],
         universe: universe, 
         dmxAddress: 1 
      );
      _controllerStreamController.add(fixture);
   }
   
   // Cache ARP results
   final Map<String, String> _arpCache = {};
   
   Future<String> _resolveMacFromIp(String ip) async {
      if (_arpCache.containsKey(ip)) return _arpCache[ip]!;
      try {
         final result = await Process.run('arp', ['-a']);
         if (result.exitCode == 0) {
            final output = result.stdout.toString();
            final lines = output.split('\n');
            for (var line in lines) {
               if (line.contains(ip)) {
                  final regex = RegExp(r'([0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}');
                  final match = regex.firstMatch(line);
                  if (match != null) {
                     String mac = match.group(0)!.replaceAll('-', ':').toUpperCase();
                     _arpCache[ip] = mac;
                     return mac;
                  }
               }
            }
         }
      } catch (e) {
         debugPrint("ARP Fail: $e");
      }
      return "00:00:00:00:00:00";
   }

  // CONFIGURATION COMMANDS (KiNET v3 / Ethernet I/O)
  // Header: Ver 0x0001 (LE), Type (variable) ...
  // Payload Magic: 0xEFBEADDE (LE: DE AD BE EF) at 0x36 (54)?
  // Standard Header (offset 0):
  // Magic (4) 44 13 AD 04 ?? No, config might differ. 
  // Spec says "KiNET Header with Version 0x0001".
  // Let's assume standard KiNET v2 Header structure but with Ver=1.
  
  List<int> _buildConfigPacket(int type, List<int> payload) {
      // Header (24 bytes? or 16?)
      // We'll try the structure from the discovery reply but as a command.
      // Magic: 0x04AD1344 (LE)
      // Ver: 0x0001 (LE)
      // Type: type (LE)
      // Seq: 0
      
      List<int> header = [
         0x44, 0x13, 0xad, 0x04, // Magic
         0x01, 0x00,             // Ver 1
         type & 0xFF, (type >> 8) & 0xFF, // Type
         0x00, 0x00, 0x00, 0x00, // Seq
         0x00, 0x00, 0x00, 0x00, // Padding
         0x00, 0x00, 0x00, 0x00
      ];
      return [...header, ...payload];
  }

  Future<void> setControllerName(String ip, String newName, String mac) async {
      await _sendConfig(ip, 0x0006, newName.codeUnits, mac);
  }

  Future<void> setIpAddress(String currentIp, String newIp, String mac, {String? sourceIp}) async {
      debugPrint("setIpAddress Called: $currentIp -> $newIp ($mac) via ${sourceIp ?? 'ANY'}");
      
      final parts = newIp.split('.').map((e) => int.parse(e)).toList();
      if (parts.length != 4) {
         debugPrint("Invalid IP Format: $newIp");
         return;
      }
      
      // MAC String to Bytes
      List<int> macBytes = mac.split(':').map((e) => int.parse(e, radix: 16)).toList();
      if (macBytes.length != 6) {
         debugPrint("Invalid MAC for IP Update: $mac");
         return;
      }

      // Construct Packet based on User Capture
      // Data: 0401dc4a 0100 0300 f1000000 efbeadde [MAC 6] 0000 [IP 4]
      List<int> packet = [
         0x04, 0x01, 0xdc, 0x4a, // Magic (0x4ADC0104 LE)
         0x01, 0x00,             // Version 1
         0x03, 0x00,             // OpCode 3 (Set IP)
         0xf1, 0x00, 0x00, 0x00, // Sequence (Fixed 0xF1 / 241 or random?) Using F1 to matches capture
         0xef, 0xbe, 0xad, 0xde, // Auth Magic (0xDEADBEEF LE)
         ...macBytes,            // Target MAC
         0x00, 0x00,             // Padding
         ...parts                // New IP
      ];
      
      try {
         final bindAddress = sourceIp != null ? InternetAddress(sourceIp) : InternetAddress.anyIPv4;
         debugPrint("Binding Socket to: ${bindAddress.address}");
         
         RawDatagramSocket.bind(bindAddress, 0).then((socket) {
             socket.broadcastEnabled = true;
             final sent = socket.send(packet, InternetAddress("255.255.255.255"), 6038);
             debugPrint("Packet Sent: $sent bytes to 255.255.255.255:6038");
             socket.close();
         }).catchError((e) {
             debugPrint("Socket Bind Error: $e");
         });
      } catch (e) {
         debugPrint("Error sending packet: $e");
      }
  }

  Future<void> setRotation(String ip, int rotationIndex, String mac, {String? sourceIp}) async {
      // Rotation Index: 0=0, 1=90, 2=180, 3=270
      // Sending as Token 73
      debugPrint("Setting Rotation for $ip to Index $rotationIndex (Token 73)");

      // Structure based on Capture:
      // Magic (4) + Ver (2) + Type (2) + Seq (4) + Token (4) + Value (4) = 20 Bytes
      
      List<int> packet = [
         0x04, 0x01, 0xdc, 0x4a, // Magic (KiNET v2)
         0x01, 0x00,             // Ver 1.0 (LE)
         0x03, 0x01,             // Type 0x0103 (LE) -> Set Property?
         0x00, 0x00, 0x00, 0x00, // Sequence (0)
         0x49, 0x00, 0x00, 0x00, // Token 73 (0x49) (LE)
         rotationIndex & 0xFF, (rotationIndex >> 8) & 0xFF, (rotationIndex >> 16) & 0xFF, (rotationIndex >> 24) & 0xFF // Value
      ];

      try {
         final bindAddress = sourceIp != null ? InternetAddress(sourceIp) : InternetAddress.anyIPv4;
         final socket = await RawDatagramSocket.bind(bindAddress, 0);
         socket.broadcastEnabled = true;
         
         debugPrint("Sending Rotation Packet (20 bytes) to $ip:6038");
         socket.send(packet, InternetAddress(ip), 6038);
         socket.close();
      } catch (e) {
          debugPrint("Error sending Rotation packet: $e");
      }
  }

  // Continuous DMX Sender for Feedback
  void sendDmxFrameV2(String ip, List<int> colors) {
       // KiNET v2 Packet (0x0108) - Port Out
       // Magic (4) + Ver (2) + Type (2) + Seq (4) + Univ (4) + Port (1) + Pad (1) + Flags (2) + Len (2) + StartCode (2)
       // User Spec: Universe=0xFFFFFFFF, Port=1, StartCode=0x0000
       
       int dataLen = colors.length;
       
       List<int> header = [
          0x04, 0x01, 0xdc, 0x4a, // Magic
          0x01, 0x00,             // Ver
          0x08, 0x01,             // Type 0x0108
          0x00, 0x00, 0x00, 0x00, // Seq
          0xff, 0xff, 0xff, 0xff, // Universe (0xFFFFFFFF)
          0x01,                   // Port 1
          0x00,                   // Pad
          0x00, 0x00,             // Flags
          dataLen & 0xFF, (dataLen >> 8) & 0xFF, // Length (Little Endian?)
          0x00, 0x00              // Start Code 0x0000
       ];
       
       List<int> packet = [...header, ...colors];
       
       try {
          // Fire and forget - binding to Any for speed and simplicity
          // Ideally reuse a socket, but for Setup tab this is fine.
          RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
             socket.broadcastEnabled = true;
             socket.send(packet, InternetAddress(ip), 6038);
             socket.close();
          });
       } catch (e) {
          // debugPrint("Error sending DMX packet: $e");
       }
  }

  Future<int?> getRotation(String ip, {String? sourceIp}) async {
      debugPrint("Getting Rotation for $ip (Token 73) - Binary 0x0105");

      // Binary Get Property
      // Magic (4) + Ver (2) + Type (2) + Seq (4) + Token (4) + Padding (4) = 20 Bytes
      List<int> packet = [
         0x04, 0x01, 0xdc, 0x4a, // Magic
         0x01, 0x00,             // Ver 1
         0x05, 0x01,             // Type 0x0105 (Get Property)
         0x00, 0x00, 0x00, 0x00, // Seq
         0x49, 0x00, 0x00, 0x00, // Token 73
         0x00, 0x00, 0x00, 0x00  // Padding
      ];

      int? result;

      try {
          final bindAddress = sourceIp != null ? InternetAddress(sourceIp) : InternetAddress.anyIPv4;
          final socket = await RawDatagramSocket.bind(bindAddress, 0);
          socket.broadcastEnabled = true;

          final completer = Completer<int?>();

          // Listen for reply 0x0106
          socket.listen((e) {
             if (e == RawSocketEvent.read) {
                final d = socket.receive();
                if (d != null && d.address.address == ip) {
                   final data = d.data;
                   // Check for 0x0106 Type (Indices 6,7) => 06 01
                   if (data.length >= 20 && data[6] == 0x06 && data[7] == 0x01) {
                        // Check Token (Indices 12-15) => 0x49 (73)
                        if (data[12] == 0x49) {
                             // Value is next 4 bytes (Indices 16-19)
                            final val = data[16] | (data[17] << 8); // Just grab first byte effectively for 0-3
                            debugPrint("Rotation Reply 0x0106! Val: $val");
                            if (!completer.isCompleted) completer.complete(val);
                        }
                   }
                }
             }
          });

          socket.send(packet, InternetAddress(ip), 6038);
          
          // Wait max 1 seconds
          result = await completer.future.timeout(const Duration(milliseconds: 1000), onTimeout: () => null);
          socket.close();
      } catch (e) {
          debugPrint("Error sending Get Rotation: $e");
      }
      return result;
  }

  Future<void> setUniverse(String ip, int newUniverse, String mac) async {
     // 4 bytes LE
     List<int> univBytes = [
        newUniverse & 0xFF,
        (newUniverse >> 8) & 0xFF,
        (newUniverse >> 16) & 0xFF,
        (newUniverse >> 24) & 0xFF
     ];
     await _sendConfig(ip, 0x0005, univBytes, mac);
  }
  
  Future<void> setDmxStartAddress(String ip, int universe, int startAddress, String mac) async {
      // OpCode 0x0103
      // Payload: [Universe Index (4b)] [Start Addr - 1 (4b)]
      // User dump showed 69 -> 44(68) so using 0-based.
      
      int addrZeroBased = (startAddress > 0) ? startAddress - 1 : 0;
      
      List<int> data = [
          // Arg 1: Universe/Port (4 bytes LE)
          universe & 0xFF, (universe >> 8) & 0xFF, (universe >> 16) & 0xFF, (universe >> 24) & 0xFF,
          // Arg 2: Start Address (4 bytes LE)
          addrZeroBased & 0xFF, (addrZeroBased >> 8) & 0xFF, (addrZeroBased >> 16) & 0xFF, (addrZeroBased >> 24) & 0xFF
      ];
      
      // Note: Header 0x0301 means Type 0x0103 (LE)
      // _sendConfig handles the header construction
      debugPrint("Preparing to send DMX Start Address change to $ip (Univ: $universe, Addr: $startAddress, RawAddr: $addrZeroBased)");
      await _sendConfig(ip, 0x0103, data, mac);
  }

  Future<void> _sendConfig(String ip, int type, List<int> data, String macStr) async {
     RawDatagramSocket? sender = _socket;
     bool isEphemeral = false;

     if (sender == null) {
        try {
           // Bind to the specific interface if known, otherwise any.
           var bindAddr = InternetAddress.anyIPv4;
           if (_localIp != null) {
              try { bindAddr = InternetAddress(_localIp!); } catch (_) {}
           }
           sender = await RawDatagramSocket.bind(bindAddr, 0);
           isEphemeral = true;
           debugPrint("Created ephemeral socket for Config Send (Bound to ${bindAddr.address})");
        } catch (e) {
           debugPrint("Failed to create ephemeral socket: $e");
           return;
        }
     }
     
     // REVERSE ENGINEERED PACKET STRUCTURE (From Wireshark)
     // Magic: 04 01 dc 4a (KiNET v2)
     // Ver: 01 00 (v1.0)
     // Type: 06 00 (Set Name)
     // Seq?: ca 00 00 00 (Saw 0xCA in dump, maybe random or sequence. Trying 0 first, or 0xCA if fails)
     // Payload Magic: ef be ad de (DEADBEEF LE)
     // Data: Name...
     
     List<int> header = [
        0x04, 0x01, 0xdc, 0x4a, // Magic V2
        0x01, 0x00,             // Ver 1
        type & 0xFF, (type >> 8) & 0xFF, // Type
        0, 0, 0, 0,             // Seq (Try 0)
        0xef, 0xbe, 0xad, 0xde  // Payload Magic (LE: EF BE AD DE)
     ];
     
     // For IP/Universe configs, the data payload usually follows directly.
     // Padding might be required. Dump was ~528 bytes.
     List<int> packet = [...header, ...data];
     
     // Pad to 528 bytes total? (Header 16 + Data) -> Pad rest
     // Dump: Data len 528? 
     // Let's pad to at least 528 bytes to be safe.
     if (packet.length < 528) {
        packet.addAll(List.filled(528 - packet.length, 0));
     }

     debugPrint("Sending RE-Config ($type) to $ip: ${packet.sublist(0, 24).map((e)=>e.toRadixString(16).padLeft(2,'0')).join(' ')}...");
     
     try {
        sender.send(packet, InternetAddress(ip), 6038);
     } catch (e) {
        debugPrint("Send Error: $e");
     } finally {
        if (isEphemeral) {
           sender.close();
           debugPrint("Closed ephemeral socket");
        }
     }
  }

  void stopDiscovery() {
    _socket?.close();
    _socket = null;
  }
  
  Future<void> sendIdentify(String ip, {int r = 0, int g = 0, int b = 255}) async {
     if (_socket == null) return;
     await _sendIdentifyBurst(_socket!, ip, r, g, b);
  }

  Future<void> _sendIdentifyBurst(RawDatagramSocket socket, String ip, int r, int g, int b) async {
      final payload = _generateColorPayload(r, g, b);
      debugPrint("Sending Identify (Blue) to $ip...");
      await _sendKinetV2Dmx(socket, ip, 1, payload);
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
     await _sendKinetV2Dmx(_socket!, targetIp, universe, dmxData);
  }

  Future<void> _sendKinetV1Dmx(RawDatagramSocket socket, String targetIp, int universe, List<int> dmxData) async {
     List<int> packet = [
       0x04, 0x01, 0xdc, 0x4a, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, universe & 0xFF, 0x00, 0x00, 0x00
     ];
     packet.addAll(dmxData);
     try { socket.send(packet, InternetAddress(targetIp), 6038); } catch (_) {}
  }

  Future<void> _sendKinetV2Dmx(RawDatagramSocket socket, String targetIp, int universe, List<int> dmxData) async {
     List<int> packet = [
       0x04, 0x01, 0xdc, 0x4a, 0x02, 0x00, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00, 
       universe & 0xFF, (universe >> 8) & 0xFF, (universe >> 16) & 0xFF, (universe >> 24) & 0xFF, 0x01, 0x00
     ];
     packet.addAll(dmxData);
     try { socket.send(packet, InternetAddress(targetIp), 6038); } catch (_) {}
  }

  void dispose() {
    stopDiscovery();
    _controllerStreamController.close();
  }
}
