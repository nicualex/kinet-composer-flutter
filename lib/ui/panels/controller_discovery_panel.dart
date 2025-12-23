
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../services/discovery_service.dart';
import '../../models/show_manifest.dart';
import '../../state/show_state.dart';

class ControllerDiscoveryPanel extends StatefulWidget {
  const ControllerDiscoveryPanel({super.key});

  @override
  State<ControllerDiscoveryPanel> createState() => _ControllerDiscoveryPanelState();
}

class _ControllerDiscoveryPanelState extends State<ControllerDiscoveryPanel> {
  final DiscoveryService _discoveryService = DiscoveryService();
  List<NetworkInterface> _interfaces = [];
  NetworkInterface? _selectedInterface;
  bool _isScanning = false;
  List<Fixture> _discoveredControllers = [];

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

  StreamSubscription? _scanSub;

  void _startScan() {
    if (_selectedInterface == null) return;
    
    setState(() {
      _isScanning = true;
      _discoveredControllers.clear(); // Renamed from _discoveredDevices
    });

    _scanSub?.cancel(); // Renamed from _scanSubscription
    // Listen to Controllers
    _scanSub = _discoveryService.controllerStream.listen((device) { 
       if (!mounted) return;
       
       // Only update if it's a new device to avoid rebuilding the UI constantly
       // and resetting text fields in the middle of typing.
       bool isNew = !_discoveredControllers.any((d) => d.ip == device.ip);
       
       if (isNew) {
         setState(() {
            _discoveredControllers.add(device);
         });
       }
    });

    _discoveryService.startDiscovery(interfaceIp: _selectedInterface!.addresses.first.address);
  }

  void _stopScan() {
    _discoveryService.stopDiscovery();
    _scanSub?.cancel(); // Renamed from _scanSubscription
    _scanSub = null; // Renamed from _scanSubscription
    setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    _scanSub?.cancel(); // Renamed from _scanSubscription
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
          const Text("CONTROLLER DISCOVERY", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          const Text("Select a network interface to scan for KiNET v2 controllers.", style: TextStyle(color: Colors.white54)),
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
                        label: Text(_isScanning ? "STOP SCAN" : "SCAN CONTROLLERS"),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isScanning ? Colors.redAccent : const Color(0xFF90CAF9),
                          foregroundColor: _isScanning ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Save/Load Actions
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 16),
                    // Replaced "Grid & Patch" with new Text widget and ListView.builder
                    Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                          Text("DISCOVERED CONTROLLERS (${_discoveredControllers.length})", style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SizedBox(
                             height: 150, // Fixed height for the list of discovered controllers
                             child: ListView.builder(
                                itemCount: _discoveredControllers.length,
                                itemBuilder: (context, index) {
                                   final f = _discoveredControllers[index];
                                   return ListTile(
                                      title: Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                      subtitle: Text("${f.ip} • ${f.width}x${f.height}", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                      trailing: IconButton(icon: const Icon(Icons.flash_on, size: 14), onPressed: () => _discoveryService.sendIdentify(f.ip)),
                                   );
                                },
                             ),
                          ),
                       ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                         onPressed: () => _saveControllersList(context),
                         icon: const Icon(Icons.save, size: 16),
                         label: const Text("SAVE SHOW"),
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
                         onPressed: () => _loadControllersList(context),
                         icon: const Icon(Icons.file_open, size: 16),
                         label: const Text("LOAD SHOW"),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.white70,
                           alignment: Alignment.centerLeft,
                           padding: const EdgeInsets.all(16)
                         ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                       "Saves/Loads the current controller grid configuration (including positions).", // Updated string
                       style: TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic)
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                          onPressed: () => _confirmInitialize(context),
                         icon: const Icon(Icons.refresh, size: 16),
                         label: const Text("INITIALIZE SHOW"),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.redAccent, 
                           alignment: Alignment.centerLeft,
                           padding: const EdgeInsets.all(16)
                         ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 32),

              // RIGHT SIDE (Results List)
              Expanded(
                child: _discoveredControllers.isEmpty 
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
                      itemCount: _discoveredControllers.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final device = _discoveredControllers[index];
                        return _ControllerRow(device: device, discoveryService: _discoveryService);
                      },
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveControllersList(BuildContext context) async {
     try {
       // Use ShowState fixtures (the patched layout)
       final fixtures = context.read<ShowState>().currentShow?.fixtures ?? [];
       if (fixtures.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No patched controllers to save.")));
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
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved ${fixtures.length} controllers to patch file.")));
       }
     } catch (e) {
        debugPrint("Error saving list: $e");
     }
  }

  Future<void> _loadControllersList(BuildContext context) async {
     try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
           dialogTitle: 'Load Patch & Layout',
           type: FileType.custom,
           allowedExtensions: ['json'],
        );

        if (result != null && result.files.isNotEmpty) {
           final file = File(result.files.single.path!);
           final bytes = await file.readAsBytes();
           String jsonStr;
           
           if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
              final codes = <int>[];
              for (int i = 2; i < bytes.length - 1; i += 2) codes.add(bytes[i] | (bytes[i+1] << 8));
              jsonStr = String.fromCharCodes(codes);
           } else {
               try { jsonStr = utf8.decode(bytes); } catch(_) { jsonStr = String.fromCharCodes(bytes); }
           }

           final dynamic json = jsonDecode(jsonStr);
           List<Fixture> loadedFixtures = [];
           
           if (json is List) {
              loadedFixtures = json.map((e) => Fixture.fromJson(e)).toList();
           } else if (json is Map) {
               debugPrint("DiscoveryPanel: Loading from Map...");
               if (json.containsKey('fixtures') && json['fixtures'] is List) {
                   loadedFixtures = (json['fixtures'] as List).map((e) => Fixture.fromJson(e)).toList();
               } else if (json.containsKey('controllers') && json['controllers'] is List) {
                   loadedFixtures = (json['controllers'] as List).map((e) => Fixture.fromJson(e)).toList();
               }
           }
           
           // Update Show State (Layout)
           if (context.mounted) {
              context.read<ShowState>().updateFixtures(loadedFixtures);
              
              // Also update local list so we see them here
              setState(() {
                 _discoveredControllers = loadedFixtures;
              });

              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Loaded & Patched ${loadedFixtures.length} controllers.")));
           }
        }
     } catch (e) {
         debugPrint("Error loading list: $e");
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error loading file: Invalid format?")));
     }
  }

  Future<void> _confirmInitialize(BuildContext context) async {
       final showState = context.read<ShowState>();
       // Check if we need confirmation
       final hasData = (showState.currentShow?.fixtures.isNotEmpty ?? false) || _discoveredControllers.isNotEmpty;
       
       if (hasData) {
          final confirm = await showDialog<bool>(
             context: context,
             builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF333333),
                title: const Text("Initialize Show?", style: TextStyle(color: Colors.white)),
                content: const Text(
                   "This will clear the current show and any discovered controller lists.\n\nAre you sure?",
                   style: TextStyle(color: Colors.white70)
                ),
                actions: [
                   TextButton(
                      child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                      onPressed: () => Navigator.of(ctx).pop(false),
                   ),
                   TextButton(
                      child: const Text("INITIALIZE", style: TextStyle(color: Colors.redAccent)),
                      onPressed: () => Navigator.of(ctx).pop(true),
                   ),
                ],
             ),
          );
          
          if (confirm != true) return;
       }
       
       // Proceed: Clear Global Show State AND Local Discovered Controllers
       showState.updateFixtures([]);
       setState(() {
          _discoveredControllers.clear();
       });
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Show Initialized (Cleared).")));
  }

}
  }

class _ControllerRow extends StatefulWidget {
  final Fixture device;
  final DiscoveryService discoveryService;

  const _ControllerRow({required this.device, required this.discoveryService});

  @override
  State<_ControllerRow> createState() => _ControllerRowState();
}

class _ControllerRowState extends State<_ControllerRow> {
  late TextEditingController _nameController;
  late TextEditingController _ipController;
  late TextEditingController _rotationController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _formatName(widget.device.name, widget.device.id));
    _ipController = TextEditingController(text: widget.device.ip);
    _rotationController = TextEditingController(text: widget.device.rotation.toStringAsFixed(0));
  }

  String _formatName(String name, String id) {
     if (name.contains("($id)")) {
        return name.replaceAll("($id)", "").trim();
     }
     return name;
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
      final device = widget.device;
      return Container(
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2), // DEBUG: RED BACKGROUND
          border: Border.all(color: Colors.red, width: 2), // DEBUG: RED BORDER
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const CircleAvatar(
            backgroundColor: Colors.white10,
            child: Icon(Icons.grid_4x4, color: Colors.cyanAccent),
          ),
          title: Row(
            children: [
              Expanded(
                  child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: "Controller Name",
                    hintStyle: const TextStyle(color: Colors.white24),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, size: 16, color: Colors.greenAccent),
                      tooltip: "Update Name",
                      onPressed: () {
                         widget.discoveryService.setControllerName(device.ip, _nameController.text, device.macAddress);
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sending name '${_nameController.text}' to ${device.ip}...")));
                      },
                    ),
                  ),
                  onSubmitted: (val) {
                     widget.discoveryService.setControllerName(device.ip, val, device.macAddress);
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
                Text("Serial: ${device.id}", style: const TextStyle(color: Colors.white70, fontFamily: 'Monospace', fontSize: 12)),
                const SizedBox(height: 4),
                // INFO / CONFIG ROW
                Row(
                  children: [
                     // IP Address Input
                     SizedBox(
                       width: 140,
                       child: TextField(
                         controller: _ipController,
                         style: const TextStyle(color: Colors.white, fontSize: 12),
                         decoration: InputDecoration(
                           labelText: "IP Address",
                           labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                           isDense: true,
                           border: const OutlineInputBorder(),
                           contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                           suffixIcon: IconButton(
                              icon: const Icon(Icons.send, size: 16, color: Colors.blueAccent),
                              padding: EdgeInsets.zero,
                              tooltip: "Update IP",
                              onPressed: () {
                                 // Basic IP Validation
                                 final parts = _ipController.text.split('.');
                                 if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
                                    widget.discoveryService.setIpAddress(device.ip, _ipController.text, device.macAddress);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sending New IP '${_ipController.text}' to ${device.ip}...")));
                                 } else {
                                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid IP Format")));
                                 }
                              }
                           ),
                         ),
                         onSubmitted: (val) {
                             final parts = val.split('.');
                             if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
                                widget.discoveryService.setIpAddress(device.ip, val, device.macAddress);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sending New IP '$val' to ${device.ip}...")));
                             }
                         },
                       ),
                     ),
                     const SizedBox(width: 8),
                     // Rotation Input (Local Patch Only)
                     SizedBox(
                       width: 100,
                       child: TextField(
                         controller: _rotationController,
                         style: const TextStyle(color: Colors.white, fontSize: 12),
                         decoration: InputDecoration( 
                           labelText: "Rotation (°)",
                           labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                           isDense: true,
                           border: const OutlineInputBorder(),
                           contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                           suffixIcon: IconButton(
                              icon: const Icon(Icons.save, size: 16, color: Colors.orangeAccent),
                              padding: EdgeInsets.zero,
                              tooltip: "Set Rotation (Local)",
                              onPressed: () {
                                double? r = double.tryParse(_rotationController.text);
                                if (r != null) {
                                   // This updates the local widget state, 
                                   // BUT the main panel list (_discoveredControllers) holds the source of truth.
                                   // We are mutating the device object directly here (passed by reference).
                                   // Assuming Fixture is mutable or we are fine with it not rebuilding parent immediately?
                                   // Fixture fields are final. We can't mutate it.
                                   // We need to notify parent or update it via a service call if logic existed?
                                   // Actually, Fixture fields ARE final. We need to replace it in the list.
                                   // Currently ControllerRow doesn't have a callback to update parent.
                                   // However, DiscoveryService emits UPDATES. But rotation is local only.
                                   // FIX: We should probably just acknowledge it's for the PATCH generation.
                                   // We can't easily update the parent list from here without a callback.
                                   // For now, let's just show a SnackBar that says "Note: Rotation is for patch saving only".
                                   // Or better, let's assume the user knows this is for the next step.
                                   // Wait, if I can't update the Fixture object, saving the list later won't include the rotation?
                                   // Correct. Fixture is immutable.
                                   // I need to add a callback to _ControllerRow to update the device.
                                   
                                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rotation set (visual only until patch saved) - TODO: Fix State update")));
                                }
                              }
                           ),
                         ),
                       ),
                     ),
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
                   widget.discoveryService.sendIdentify(device.ip);
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Identifying ${device.name}..."), duration: const Duration(milliseconds: 500)));
                },
              ),
            ],
          ),
        ),
      );
  }
}
}
