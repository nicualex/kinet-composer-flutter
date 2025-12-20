
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../services/discovery_service.dart';
import '../../models/show_manifest.dart';
import '../../state/show_state.dart';

class DeviceDiscoveryPanel extends StatefulWidget {
  const DeviceDiscoveryPanel({super.key});

  @override
  State<DeviceDiscoveryPanel> createState() => _DeviceDiscoveryPanelState();
}

class _DeviceDiscoveryPanelState extends State<DeviceDiscoveryPanel> {
  final DiscoveryService _discoveryService = DiscoveryService();
  List<NetworkInterface> _interfaces = [];
  NetworkInterface? _selectedInterface;
  bool _isScanning = false;
  List<Fixture> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _loadInterfaces();
  }

  Future<void> _loadInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      setState(() {
        _interfaces = interfaces;
        if (interfaces.isNotEmpty) {
           _selectedInterface = interfaces.first;
        }
      });
    } catch (e) {
      debugPrint("Error loading interfaces: $e");
    }
  }

  StreamSubscription? _scanSubscription;

  void _startScan() {
    if (_selectedInterface == null) return;
    
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    _scanSubscription?.cancel();
    _scanSubscription = _discoveryService.deviceStream.listen((device) {
       // Only add unique IPs
       if (!_discoveredDevices.any((d) => d.ip == device.ip)) {
          setState(() {
            _discoveredDevices.add(device);
          });
       }
    });

    _discoveryService.startDiscovery(interfaceIp: _selectedInterface!.addresses.first.address);
  }

  void _stopScan() {
    _discoveryService.stopDiscovery();
    _scanSubscription?.cancel();
    _scanSubscription = null;
    setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _discoveryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("DEVICE DISCOVERY", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          const Text("Select a network interface to scan for KiNET v2 devices.", style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT SIDEBAR (Controls)
              SizedBox(
                width: 250,
                child: Column(
                  children: [
                    // Interface Selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12)
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<NetworkInterface>(
                          value: _selectedInterface,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF2C2C2C),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                          items: _interfaces.map((iface) {
                             String ip = iface.addresses.isNotEmpty ? iface.addresses.first.address : "No IP";
                             return DropdownMenuItem(
                               value: iface,
                               child: Text("${iface.name}\n$ip", style: const TextStyle(height: 1.2)),
                             );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedInterface = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Scan Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isScanning ? _stopScan : _startScan,
                        icon: Icon(_isScanning ? Icons.stop : Icons.search),
                        label: Text(_isScanning ? "STOP SCAN" : "SCAN DEVICES"),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isScanning ? Colors.redAccent : const Color(0xFF64FFDA),
                          foregroundColor: _isScanning ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Save/Load Actions
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 16),
                    const Text("Layout & Patch", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                         onPressed: () => _saveDevicesList(context),
                         icon: const Icon(Icons.save, size: 16),
                         label: const Text("SAVE PATCH"),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.white70, 
                           alignment: Alignment.centerLeft,
                           padding: const EdgeInsets.all(16)
                         ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                         onPressed: () => _loadDevicesList(context),
                         icon: const Icon(Icons.file_open, size: 16),
                         label: const Text("LOAD PATCH"),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.white70,
                           alignment: Alignment.centerLeft,
                           padding: const EdgeInsets.all(16)
                         ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                       "Saves/Loads the current device layout configuration (including positions).", 
                       style: TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic)
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 32),

              // RIGHT SIDE (Results List)
              Expanded(
                child: _discoveredDevices.isEmpty 
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.radar, size: 64, color: Colors.white10),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning ? "Scanning for KiNET devices..." : "Ready to scan.\nMake sure devices are powered and connected.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white24),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: _discoveredDevices.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final device = _discoveredDevices[index];
                        return _buildDeviceRow(device, index);
                      },
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveDevicesList(BuildContext context) async {
     try {
       // Use ShowState fixtures (the patched layout)
       final fixtures = context.read<ShowState>().currentShow?.fixtures ?? [];
       if (fixtures.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No patched devices to save.")));
          return;
       }

       String? outputFile = await FilePicker.platform.saveFile(
         dialogTitle: 'Save Patch & Layout',
         fileName: 'kinet_patch.json',
         allowedExtensions: ['json'],
         type: FileType.custom,
       );

       if (outputFile != null) {
          final jsonStr = jsonEncode(fixtures.map((e) => e.toJson()).toList());
          await File(outputFile).writeAsString(jsonStr);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved ${fixtures.length} devices to patch file.")));
       }
     } catch (e) {
        debugPrint("Error saving list: $e");
     }
  }

  Future<void> _loadDevicesList(BuildContext context) async {
     try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
           dialogTitle: 'Load Patch & Layout',
           type: FileType.custom,
           allowedExtensions: ['json'],
        );

        if (result != null && result.files.isNotEmpty) {
           final file = File(result.files.single.path!);
           final jsonStr = await file.readAsString();
           final List<dynamic> list = jsonDecode(jsonStr);
           final loadedFixtures = list.map((e) => Fixture.fromJson(e)).toList();
           
           // Update Show State (Layout)
           if (context.mounted) {
              context.read<ShowState>().updateFixtures(loadedFixtures);
              
              // Also update local list so we see them here
              setState(() {
                 _discoveredDevices = loadedFixtures;
              });

              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Loaded & Patched ${loadedFixtures.length} devices.")));
           }
        }
     } catch (e) {
         debugPrint("Error loading list: $e");
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error loading file: Invalid format?")));
     }
  }

  Widget _buildDeviceRow(Fixture device, int index) {
     // Extract Name vs Serial for display if formatted
     String displaySerial = device.id;
     String displayName = device.name;
     if (displayName.contains("(${device.id})")) {
        displayName = displayName.replaceAll("(${device.id})", "").trim();
     }

     TextEditingController nameController = TextEditingController(text: displayName);

     return Container(
       decoration: BoxDecoration(
         color: Colors.white.withValues(alpha: 0.05),
         borderRadius: BorderRadius.circular(8),
       ),
       child: ListTile(
         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
         leading: CircleAvatar(
           backgroundColor: Colors.white10,
           child: Icon(Icons.grid_4x4, color: Colors.cyanAccent),
         ),
         title: Row(
           children: [
             Expanded(
               child: TextField(
                 controller: nameController,
                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                 decoration: const InputDecoration(
                   border: InputBorder.none,
                   hintText: "Device Name",
                   hintStyle: TextStyle(color: Colors.white24),
                   isDense: true,
                   suffixIcon: Icon(Icons.edit, size: 14, color: Colors.white24),
                 ),
                 onSubmitted: (val) {
                    _discoveryService.setDeviceName(device.ip, val);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sending name '$val' to ${device.ip}...")));
                 },
               ),
             ),
           ],
         ),
         subtitle: Padding(
           padding: const EdgeInsets.only(top: 4.0),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text("Serial: $displaySerial", style: const TextStyle(color: Colors.white70, fontFamily: 'Monospace', fontSize: 12)),
               const SizedBox(height: 4),
               Row(
                 children: [
                   const Icon(Icons.wifi, size: 12, color: Colors.white54),
                   const SizedBox(width: 4),
                   Text(device.ip, style: const TextStyle(color: Colors.white54)),
                   const SizedBox(width: 16),
                   const Icon(Icons.lightbulb_outline, size: 12, color: Colors.white54),
                   const SizedBox(width: 4),
                   Text("${device.width * device.height} Fixtures", style: const TextStyle(color: Colors.white54)),
                 ],
               ),
             ],
           ),
         ),
         trailing: Row(
           mainAxisSize: MainAxisSize.min,
           children: [
             // Identify Button
             IconButton(
               icon: const Icon(Icons.lightbulb),
               color: Colors.blueAccent,
               tooltip: "Identify (Turn Blue)",
               onPressed: () {
                  _discoveryService.sendIdentify(device.ip);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Identifying ${device.name}..."), duration: const Duration(milliseconds: 500)));
               },
             ),
             const SizedBox(width: 8),
             // Save Name Button
             IconButton(
               icon: const Icon(Icons.save),
               color: Colors.greenAccent,
               tooltip: "Save Name to Device",
               onPressed: () {
                  final newName = nameController.text;
                  _discoveryService.setDeviceName(device.ip, newName);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sending name '$newName' to ${device.ip}...")));
               },
             ),
           ],
         ),
       ),
     );
  }
}
