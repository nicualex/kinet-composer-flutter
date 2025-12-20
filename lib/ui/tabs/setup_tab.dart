import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kinet_composer/state/show_state.dart';
import 'package:kinet_composer/models/show_manifest.dart';
import 'package:kinet_composer/services/discovery_service.dart';
import 'package:flutter/gestures.dart'; // For PointerScrollEvent
import 'dart:math';


class SetupTab extends StatefulWidget {
  const SetupTab({super.key});

  @override
  State<SetupTab> createState() => _SetupTabState();
}

class _SetupTabState extends State<SetupTab> with TickerProviderStateMixin {
  final DiscoveryService _discoveryService = DiscoveryService();
  bool _isScanning = false;
  // bool _isLayoutLocked = false; // MOVED TO SHOWSTATE
  List<NetworkInterface> _interfaces = [];
  NetworkInterface? _selectedInterface;
  StreamSubscription? _scanSub;
  List<Fixture> _discoveredDevices = []; // Local cache for scanning results
  
  // Sidebar State
  // int _sidebarTab = 0; // Removed

  final TransformationController _transformationController = TransformationController();
  
  bool _enablePan = true;
  
  // Drag State
  Offset? _dragStartPos;
  Offset? _lastLocalPos;
  Offset _dragAccumulator = Offset.zero;
  
  String? _selectedFixtureId;
  Fixture? _selectedDiscoveredFixture; // Track selection for discovered (unpatched) items
  
  // Layout Editors
  // Layout Editors (Removed per user request)

  bool _hasInitialFit = false;
  
  // Visual Constants (Reduced 20% -> 12px/4px)
  static const double kLedSize = 12.0;
  static const double kLedSpace = 4.0;
  static const double kStride = kLedSize + kLedSpace; // 16.0
  
  // Canvas Constraints
  // Device Tile = 10x10 pixels = 10 * 16.0 = 160.0 px
  // Max X = 20 tiles = 3200.0 px
  // Max Y = 10 tiles = 1600.0 px
  static const double kCanvasWidth = 3200.0;
  static const double kCanvasHeight = 1600.0;

  @override
  void initState() {
    super.initState();
    _loadInterfaces();
  }

  void _deduplicateFixtures(ShowState showState, List<Fixture> fixtures) {
      if (!mounted) return;
      debugPrint("Runnning Auto-Deduplication on ${fixtures.length} fixtures...");
      final List<Fixture> newFixtures = [];
      final Set<String> seenIds = {};
      
      bool changed = false;
      for (var f in fixtures) {
         if (seenIds.contains(f.id)) {
            // Collision!
            final newId = "${f.id}_${DateTime.now().microsecondsSinceEpoch}";
            newFixtures.add(f.copyWith(id: newId));
            seenIds.add(newId);
            changed = true;
            debugPrint("Fixed Duplicate ID: ${f.id} -> $newId");
         } else {
            newFixtures.add(f);
            seenIds.add(f.id);
         }
      }
      
      if (changed) {
         debugPrint("Applying Deduplicated Fixtures Update.");
         showState.updateFixtures(newFixtures);
         setState(() {
            _selectedFixtureId = null; 
         });
      }
  }

  Future<void> _loadInterfaces() async {
    try {
      final list = await NetworkInterface.list(includeLoopback: true, type: InternetAddressType.IPv4);
      if (mounted) {
        setState(() {
          _interfaces = list;
          if (_interfaces.isNotEmpty) _selectedInterface = _interfaces.first;
        });
      }
    } catch (e) {
      debugPrint("Error loading interfaces: $e");
    }
  }

  @override
  void dispose() {
    // Stop Scan (Manual cleanup to avoid setState in dispose)
    _discoveryService.stopDiscovery();
    _scanSub?.cancel();
    
    _transformationController.dispose();
    // Controllers removed
    super.dispose();
  }

  void _startScan(ShowState showState) async {
    if (_selectedInterface == null) return;
    
    String bindIp = _selectedInterface!.addresses.first.address;
    debugPrint("STARTING SCAN on $bindIp");
    
    // Auto-Unlock Layout on Scan
    showState.setLayoutLock(false);

    setState(() {
       _isScanning = true;
       _discoveredDevices.clear();
    });
    
    await _discoveryService.startDiscovery(interfaceIp: bindIp);
    
    // Listen to device stream
    _scanSub?.cancel();
    _scanSub = _discoveryService.deviceStream.listen((device) {
       if (!mounted) return;
       setState(() {
             // Deduplicate based on IP
          if (!_discoveredDevices.any((d) => d.ip == device.ip)) {
             // Default Position: 
             final positionedDevice = device.copyWith(
                id: "${device.ip}-${DateTime.now().millisecondsSinceEpoch}", // Ensure Unique ID
                x: (_discoveredDevices.length * kStride * 2),
                y: 160.0, // Default Y in bounds
             );
             _discoveredDevices.add(positionedDevice);
             debugPrint("Discovered: ${positionedDevice.name} @ ${positionedDevice.ip}");
          }
       });
    });
  }

  void _stopScan() {
    _discoveryService.stopDiscovery();
    _scanSub?.cancel();
    if (mounted) setState(() => _isScanning = false);
  }

  void _selectFixture(Fixture? f, {bool patched = true}) {
    if (!mounted) return;
    setState(() {
       if (patched) {
         _selectedFixtureId = f?.id;
         _selectedDiscoveredFixture = null;
       } else {
         _selectedFixtureId = null;
         _selectedDiscoveredFixture = f;
       }

       if (f != null) {
          // Controllers removed
       }
    });
  }

  void _rotateFixture(Fixture f, ShowState state) {
     final newRot = (f.rotation + 90) % 360;
     setState(() {
        if (_selectedDiscoveredFixture != null && _selectedDiscoveredFixture!.id == f.id) {
           final index = _discoveredDevices.indexWhere((d) => d.id == f.id);
           if (index != -1) {
              final newF = f.copyWith(rotation: newRot);
              _discoveredDevices[index] = newF;
              _selectedDiscoveredFixture = newF; 
              // _rotCtrl.text = ... (removed)
           }
        } else {
           state.updateFixturePosition(f.id, f.x, f.y, newRot);
           // _rotCtrl.text = ... (removed)
        }
     });
  }

  void _onDragStart(Fixture f, DragStartDetails details) {
      if (!mounted) return;
      setState(() {
        _enablePan = false;
        _dragStartPos = Offset(f.x, f.y);
        _lastLocalPos = details.localPosition;
        _dragAccumulator = Offset.zero;
        _selectFixture(f, patched: _discoveredDevices.indexWhere((d)=>d.id==f.id) == -1);
      });
  }

  Rect _getVisualBounds(Fixture f) {
      final double rads = f.rotation * 3.14159 / 180;
      final double w = f.width * kStride;
      final double h = f.height * kStride;
      
      // Calculate rotated bounding box size
      final double absCos = cos(rads).abs();
      final double absSin = sin(rads).abs();
      final double newW = w * absCos + h * absSin;
      final double newH = w * absSin + h * absCos;
      
      // Center stays constant relative to unrotated Top-Left
      final double centerX = f.x + w / 2;
      final double centerY = f.y + h / 2;
      
      return Rect.fromCenter(center: Offset(centerX, centerY), width: newW, height: newH);
  }

  void _onDragEnd(Fixture f, dynamic details, ShowState state) {
      if (_dragStartPos != null) {
          // Final Snap on Drop
          // Grid = 80px (Half Device Size)
          const double snapGrid = kStride * 5; // 16.0 * 5 = 80.0

          final rawPos = _dragStartPos! + _dragAccumulator;
          double snappedX = (rawPos.dx / snapGrid).round() * snapGrid;
          double snappedY = (rawPos.dy / snapGrid).round() * snapGrid;
          
          // Check Bounds
          if (snappedX < 0) snappedX = 0;
          if (snappedY < 0) snappedY = 0;
          if (snappedX > kCanvasWidth - (f.width * kStride)) snappedX = kCanvasWidth - (f.width * kStride);
          if (snappedY > kCanvasHeight - (f.height * kStride)) snappedY = kCanvasHeight - (f.height * kStride);
          
          // Check Collision
          bool hasCollision = false;
          final proposedFixture = f.copyWith(x: snappedX, y: snappedY);
          final proposedRect = _getVisualBounds(proposedFixture);
          
          final allFixtures = <Fixture>[
             ...(state.currentShow?.fixtures ?? []),
             ..._discoveredDevices
          ];
          
          for (var other in allFixtures) {
             if (other.id == f.id) continue;
             if (_getVisualBounds(other).overlaps(proposedRect)) {
                hasCollision = true;
                break;
             }
          }

          if (hasCollision) {
             // Revert
             _updateFixtureLocation(f, _dragStartPos!.dx, _dragStartPos!.dy, state);
             if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Placement: Overlaps existing device"), duration: Duration(milliseconds: 500)));
          } else if (snappedX != f.x || snappedY != f.y) {
             _updateFixtureLocation(f, snappedX, snappedY, state);
          }
      }
      setState(() {
         _enablePan = true;
         _dragStartPos = null;
         _lastLocalPos = null;
      });
  }

  void _onScrub(Offset localPos, List<Fixture> fixtures) {
     // Find fixture under point
     for (final f in [...fixtures, ..._discoveredDevices]) {
        if (_getVisualBounds(f).contains(localPos)) {
           // Found!
           if (_selectedFixtureId != f.id && _selectedDiscoveredFixture?.id != f.id) {
               // Determine if patched or discovered
               bool isPatched = fixtures.any((fix) => fix.id == f.id);
               _selectFixture(f, patched: isPatched);
           }
           return;
        }
     }
     
     // Detect Miss (Hovering Empty Space)
     if (_selectedFixtureId != null || _selectedDiscoveredFixture != null) {
        _selectFixture(null);
     }
  }

  void _updateFixtureLocation(Fixture f, double x, double y, ShowState state) {
      if (_selectedDiscoveredFixture != null && _selectedDiscoveredFixture!.id == f.id) {
         final index = _discoveredDevices.indexWhere((d) => d.id == f.id);
         if (index != -1) {
            setState(() {
               final newF = f.copyWith(x: x, y: y);
               _discoveredDevices[index] = newF;
               _selectedDiscoveredFixture = newF;
            });
         }
      } else {
         state.updateFixturePosition(f.id, x, y, f.rotation);
         // Controllers Update removed
      }
  }

  void _onDragUpdate(Fixture f, DragUpdateDetails details, ShowState state) {
      if (_dragStartPos == null || _lastLocalPos == null) return;
      
      // Calculate delta manually from localPosition to get scene coordinates
      final Offset currentLocal = details.localPosition;
      final Offset localDelta = currentLocal - _lastLocalPos!;
      _lastLocalPos = currentLocal;
      
      _dragAccumulator += localDelta; 
      
      final newRawPos = _dragStartPos! + _dragAccumulator;
      
      // Free Drag (No Snapping)
      final double newX = newRawPos.dx;
      final double newY = newRawPos.dy;
      
      _updateFixtureLocation(f, newX, newY, state);
  }

  void _updateDiscoveredProperty(Fixture f, {double? x, double? y, double? r}) {
     setState(() {
        final index = _discoveredDevices.indexWhere((d) => d.id == f.id);
        if (index != -1) {
            final newF = f.copyWith(
               x: x ?? f.x,
               y: y ?? f.y,
               rotation: r ?? f.rotation
            );
            _discoveredDevices[index] = newF;
            _selectedDiscoveredFixture = newF;
        }
     });
  }

  void _fitToScreen(List<Fixture> fixtures, BoxConstraints constraints) {
      if (fixtures.isEmpty) return;
      
      double minX = double.infinity, minY = double.infinity;
      double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      
      for (var f in fixtures) {
         if (f.x < minX) minX = f.x;
         if (f.y < minY) minY = f.y;
         if (f.x + (f.width*kStride) > maxX) maxX = f.x + (f.width*kStride); 
         if (f.y + (f.height*kStride) > maxY) maxY = f.y + (f.height*kStride);
      }
      
      double w = maxX - minX;
      double h = maxY - minY;
      double scaleX = constraints.maxWidth / (w + 200);
      double scaleY = constraints.maxHeight / (h + 200);
      double scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.01, 2.0);
      
      final Matrix4 matrix = Matrix4.identity()
        ..translate(constraints.maxWidth/2, constraints.maxHeight/2)
        ..scale(scale)
        ..translate(-(minX + w/2), -(minY + h/2));
        
      _transformationController.value = matrix;
  }
  
  // Save/Load Patch Handlers
  Future<void> _savePatch(BuildContext context, ShowState showState) async {
     final show = showState.currentShow;
     if (show == null) return;
     
     String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Patch',
        fileName: 'patch.json',
        allowedExtensions: ['json'],
        type: FileType.custom,
     );
     
     if (path != null) {
        try {
           final json = jsonEncode(show.fixtures.map((e) => e.toJson()).toList());
           await File(path).writeAsString(json);
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patch Saved")));
        } catch (e) {
           debugPrint("Error saving patch: $e");
        }
     }
  }

  Future<void> _loadPatch(BuildContext context, ShowState showState) async {
     FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
     );
     
     if (result != null && result.files.single.path != null) {
        try {
           final content = await File(result.files.single.path!).readAsString();
            final List<dynamic> json = jsonDecode(content);
            List<Fixture> fixtures = json.map((e) => _clampToCanvas(Fixture.fromJson(e))).toList();
            
            // Sanitize IDs (Deduplicate)
            final seenIds = <String>{};
            final sanitized = <Fixture>[];
            for (var f in fixtures) {
               if (seenIds.contains(f.id)) {
                  // Generate new ID
                  final newId = "${f.id}_${DateTime.now().microsecondsSinceEpoch}_${sanitized.length}";
                  f = f.copyWith(id: newId);
               }
               seenIds.add(f.id);
               sanitized.add(f);
            }
            fixtures = sanitized;

            showState.updateFixtures(fixtures);
            
            // Auto-Lock Layout on Load
            showState.setLayoutLock(true);
            
            setState(() {
               _discoveredDevices.clear();
               _selectedFixtureId = null;
               _selectedDiscoveredFixture = null;
            });
            
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patch Loaded & Old State Cleared")));
        } catch (e) {
           debugPrint("Error loading patch: $e");
        }
     }
  }

  Fixture _clampToCanvas(Fixture f) {
      double x = f.x;
      double y = f.y;
      
      // Basic Bounds
      if (x < 0) x = 0;
      if (y < 0) y = 0;
      if (x > kCanvasWidth - (f.width * kStride)) x = kCanvasWidth - (f.width * kStride);
      if (y > kCanvasHeight - (f.height * kStride)) y = kCanvasHeight - (f.height * kStride);
      
      if (x != f.x || y != f.y) {
         return f.copyWith(x: x, y: y);
      }
      return f;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShowState>(
      builder: (context, showState, child) {
        final fixtures = showState.currentShow?.fixtures ?? [];
        
        // Auto-Healing: Check for Duplicate IDs
        final ids = <String>{};
        bool hasDupe = false;
        for (var f in fixtures) {
           if (ids.contains(f.id)) { hasDupe = true; break; }
           ids.add(f.id);
        }
        if (hasDupe) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
              _deduplicateFixtures(showState, fixtures);
           });
        }

        // Auto-Healing: Check for Out-of-Bounds
        bool hasOOB = false;
        for (var f in fixtures) {
            final clamped = _clampToCanvas(f);
            if (clamped.x != f.x || clamped.y != f.y) { hasOOB = true; break; }
        }
        if (hasOOB) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
               final newFixtures = fixtures.map((f) => _clampToCanvas(f)).toList();
               showState.updateFixtures(newFixtures);
               debugPrint("Auto-healed out-of-bounds fixtures");
            });
        }

        debugPrint("SetupTab Rebuild: ${fixtures.length} fixtures found in state.");
        
        // Auto-select first if none selected logic removed per user request
        // if (_selectedFixtureId == null && _selectedDiscoveredFixture == null && fixtures.isNotEmpty) { ... }
        
        Fixture? selectedFixture;
        if (_selectedDiscoveredFixture != null) {
           selectedFixture = _selectedDiscoveredFixture;
        } else if (_selectedFixtureId != null) {
           selectedFixture = fixtures.isEmpty ? null : fixtures.firstWhere((f) => f.id == _selectedFixtureId, orElse: () => fixtures.first);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. SIDEBAR (Black & Square)
            Container(
              width: 320,
              color: Colors.black,
              child: Container(
                decoration: const BoxDecoration(
                   border: Border(right: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                   crossAxisAlignment: CrossAxisAlignment.stretch,
                   children: [
                       // Header
                      Container(
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                         decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.white12)),
                            color: Colors.white10,
                         ),
                         child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               const Text("SETUP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                               Row(
                                  children: [
                                     IconButton(
                                        icon: const Icon(Icons.save_alt, size: 18, color: Colors.white70),
                                        tooltip: "Save Patch",
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        onPressed: () => _savePatch(context, showState),
                                     ),
                                     const SizedBox(width: 12),
                                     IconButton(
                                        icon: const Icon(Icons.file_open, size: 18, color: Colors.white70),
                                        tooltip: "Load Patch",
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        onPressed: () => _loadPatch(context, showState),
                                     ),
                                  ],
                               )
                            ],
                         ),
                      ),
                      
                      // Unified Content
                      Expanded(
                        child: ListView(
                           padding: EdgeInsets.zero,
                           children: [
                              // 1. Discovery Controls (Top)
                              _buildNetworkControls(showState),
                              
                              const Divider(height: 1, color: Colors.white12),
                              
                              // 2. Selected Properties REMOVED per user request
                              
                              // 3. Device Lists (Bottom)
                              _buildDeviceLists(fixtures, showState),
                              
                              const SizedBox(height: 40),
                           ],
                        ),
                      ),
                   ],
                ),
              ),
            ),

            // 2. CANVAS
            Expanded(
              child: Container(
                color: const Color(0xFF1E1E1E), 
                child: LayoutBuilder(
                   builder: (context, constraints) {
                      // if (!_hasInitialFit && fixtures.isNotEmpty) {
                      //    WidgetsBinding.instance.addPostFrameCallback((_) { _fitToScreen(fixtures, constraints); _hasInitialFit = true; });
                      // }
                      return Listener(
                         behavior: HitTestBehavior.opaque,
                         onPointerSignal: (event) {
                            if (event is PointerScrollEvent) {
                               // Handle Zoom
                               final newScale = _transformationController.value.getMaxScaleOnAxis() - (event.scrollDelta.dy * 0.001);
                               final clamped = newScale.clamp(0.1, 5.0);
                               
                               // Zoom towards pointer? For now simple scale.
                               final Matrix4 matrix = _transformationController.value.clone();
                               matrix.scale(clamped / matrix.getMaxScaleOnAxis());
                               _transformationController.value = matrix;
                            }
                         },
                         child: InteractiveViewer(
                           transformationController: _transformationController,
                           boundaryMargin: const EdgeInsets.all(double.infinity), // Allow panning freely
                           minScale: 0.1,
                           maxScale: 5.0,
                           constrained: false, // Infinite canvas (but we limit content)
                           panEnabled: !showState.isLayoutLocked, // Disable canvas pan when locked to allow scrub? OR keep pan and use 2 fingers? 
                           // If panEnabled=false, 1-finger drag might be available for Listener.
                           scaleEnabled: true,
                           child: Listener(
                                onPointerDown: (e) {
                                   if (showState.isLayoutLocked) _onScrub(e.localPosition, fixtures);
                                },
                                onPointerMove: (e) {
                                   if (showState.isLayoutLocked) _onScrub(e.localPosition, fixtures);
                                },
                                onPointerHover: (e) {
                                   _onScrub(e.localPosition, fixtures);
                                },
                                child: GestureDetector(
                                   onTap: () {
                                      setState(() {
                                         _selectedFixtureId = null;
                                         _selectedDiscoveredFixture = null;
                                      });
                                   },
                                   child: Container(
                                      width: kCanvasWidth,
                                      height: kCanvasHeight,
                                      decoration: const BoxDecoration(
                                         color: Color(0xFF121212),
                                         boxShadow: [BoxShadow(color: Colors.black, blurRadius: 20, spreadRadius: 5)],
                                      ),
                                      child: Stack(
                                         clipBehavior: Clip.none,
                                         children: [ // ...
                                         // 1. Grid Background
                                         Positioned.fill(
                                            child: CustomPaint(
                                               painter: GridBackgroundPainter(),
                                               size: Size(kCanvasWidth, kCanvasHeight),
                                            ),
                                         ),
                                         
                                         // 2. Unselected Fixtures
                                         ...fixtures.where((f) => f.id != _selectedFixtureId).map((f) => _buildPositionedFixture(f, showState, false, key: ValueKey("patched_${f.id}"))),
     
                                         // 3. Selected Fixture (On Top)
                                    if (selectedFixture != null && _selectedFixtureId != null)
                                       _buildPositionedFixture(selectedFixture, showState, true, key: ValueKey("patched_${selectedFixture.id}")),
                                       
                                    // 4. Discovered (Transient)
                                    ..._discoveredDevices.map((f) => _buildPositionedDiscovered(f, showState, key: ValueKey("disc_${f.id}"))),
                                 ],
                              )),
                           ),
                         ),
                       ));
                    },
                ),
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildNetworkControls(ShowState showState) {
       if (_selectedInterface != null && !_interfaces.contains(_selectedInterface)) {
           _selectedInterface = _interfaces.isNotEmpty ? _interfaces.first : null;
       }
       return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
                const Text("NETWORK INTERFACE", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white10)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<NetworkInterface>(
                      value: _selectedInterface,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF333333),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                      items: _interfaces.map((iface) => DropdownMenuItem(value: iface, child: Text(iface.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) => setState(() => _selectedInterface = val),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () { 
                       debugPrint("Scan Button Pressed. ${_isScanning ? "Stopping" : "Starting"}");
                       _isScanning ? _stopScan() : _startScan(showState); 
                    },
                     icon: Icon(_isScanning ? Icons.stop : Icons.radar, size: 16),
                     label: Text(_isScanning ? "STOP SCANNING" : "SCAN FOR DEVICES"),
                     style: FilledButton.styleFrom(
                        backgroundColor: _isScanning ? Colors.redAccent : const Color(0xFF64FFDA),
                        foregroundColor: _isScanning ? Colors.white : Colors.black,
                     ),
                   ),
                 ),
                 const SizedBox(height: 8),
                 // Layout Lock Toggle
                 Row(
                    children: [
                       const Text("LAYOUT LOCK", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                       const Spacer(),
                       Switch(
                          value: showState.isLayoutLocked,
                          onChanged: (v) {
                             showState.setLayoutLock(v);
                             
                             if (v) {
                                // Calculate Bounding Box of Layout
                                final fixtures = showState.currentShow?.fixtures ?? [];
                                if (fixtures.isNotEmpty) {
                                   double minX = double.infinity;
                                   double minY = double.infinity;
                                   double maxX = double.negativeInfinity;
                                   double maxY = double.negativeInfinity;
                                   
                                   for (final f in fixtures) {
                                      final bounds = _getVisualBounds(f);
                                      if (bounds.left < minX) minX = bounds.left;
                                      if (bounds.top < minY) minY = bounds.top;
                                      if (bounds.right > maxX) maxX = bounds.right;
                                      if (bounds.bottom > maxY) maxY = bounds.bottom;
                                   }
                                   
                                   if (minX != double.infinity) {
                                      final w = maxX - minX;
                                      final h = maxY - minY;
                                      // Optional: Add padding? User said "rectangle that includes all tiles", implying exact fit.
                                      debugPrint("Layout Layout Locked: W=$w, H=$h");
                                      showState.updateLayoutBounds(w, h);
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Layout Set: ${w.ceil()} x ${h.ceil()}")));
                                   }
                                }
                             }
                          },
                          activeColor: const Color(0xFF64FFDA),
                       )
                    ],
                 ),
                if (_isScanning)
                   Padding(
                     padding: const EdgeInsets.only(top: 8),
                     child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: const Color(0xFF64FFDA), minHeight: 2),
                   ),
             ],
          ),
       );
  }

  Widget _buildPositionedFixture(Fixture f, ShowState showState, bool isSelected, {Key? key}) {
      return Positioned(
         key: key,
         left: f.x, top: f.y,
         child: MouseRegion(
            onEnter: (_) {
               if (_dragStartPos != null) return;
               if (_selectedFixtureId != f.id) {
                  _selectFixture(f, patched: true);
               }
            },
            child: GestureDetector(
               behavior: HitTestBehavior.opaque,
               onTap: () => _selectFixture(f, patched: true),
               onLongPress: showState.isLayoutLocked ? null : () => _rotateFixture(f, showState),
               onPanStart: showState.isLayoutLocked ? null : (d) => _onDragStart(f, d),
               onPanUpdate: showState.isLayoutLocked ? null : (d) => _onDragUpdate(f, d, showState),
               onPanEnd: showState.isLayoutLocked ? null : (d) => _onDragEnd(f, d, showState),
               onPanCancel: showState.isLayoutLocked ? null : () => _onDragEnd(f, null, showState),
               child: _buildFixtureVisual(f, isSelected),
            ),
         ),
      );
  }
  Widget _buildPositionedDiscovered(Fixture f, ShowState showState, {Key? key}) {
      final isSelected = _selectedDiscoveredFixture?.id == f.id;
      return Positioned(
         key: key,
         left: f.x, top: f.y,
         child: MouseRegion(
            onEnter: (_) {
               if (_dragStartPos != null) return;
               if (_selectedDiscoveredFixture?.id != f.id) {
                  _selectFixture(f, patched: false);
               }
            },
            child: GestureDetector(
               behavior: HitTestBehavior.opaque,
               onTap: () => _selectFixture(f, patched: false),
               onLongPress: showState.isLayoutLocked ? null : () => _rotateFixture(f, showState),
               onPanStart: showState.isLayoutLocked ? null : (d) => _onDragStart(f, d),
               onPanUpdate: showState.isLayoutLocked ? null : (d) => _onDragUpdate(f, d, showState),
               onPanEnd: showState.isLayoutLocked ? null : (d) => _onDragEnd(f, d, showState),
               onPanCancel: showState.isLayoutLocked ? null : () => _onDragEnd(f, null, showState),
               child: Opacity(
                  opacity: 0.7, 
                  child: _buildFixtureVisual(f, isSelected),
               ),
            ),
         ),
      );
  }

  Widget _buildDeviceLists(List<Fixture> fixtures, ShowState showState) {
       return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              // Discovered Devices (Only if any)
              if (_discoveredDevices.isNotEmpty) ...[
                 Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text("DISCOVERED (${_discoveredDevices.length})", style: const TextStyle(color: Color(0xFF64FFDA), fontSize: 11, fontWeight: FontWeight.bold)),
                 ),
                 ..._discoveredDevices.map((f) => _buildDeviceTile(f, showState, false)),
                 const Divider(height: 1, color: Colors.white10),
              ],
              
              // List Patched
              Padding(
                 padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                 child: Text("PATCHED FIXTURES (${fixtures.length})", style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              
              ...fixtures.map((f) => _buildDeviceTile(f, showState, true)).toList(),
          ],
       );
  }

  Widget _buildDeviceTile(Fixture f, ShowState showState, bool patched) {
      final isSel = patched ? (f.id == _selectedFixtureId) : (_selectedDiscoveredFixture?.id == f.id);
      return Container(
         decoration: BoxDecoration(
           color: isSel ? const Color(0xFF64FFDA).withOpacity(0.15) : Colors.transparent,
           border: isSel ? const Border(left: BorderSide(color: Color(0xFF64FFDA), width: 3)) : null,
         ),
         child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 13, right: 16), // Adjusted for border
            selected: isSel,
            // selectedTileColor: Removed in favor of Container decoration
            title: Text(f.name, style: TextStyle(color: isSel ? const Color(0xFF64FFDA) : Colors.white, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
            subtitle: Text("${f.width}x${f.height} • ${f.ip}", style: TextStyle(color: isSel ? Colors.white70 : Colors.grey, fontSize: 11)),
            onTap: () => _selectFixture(f, patched: patched),
            trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
               IconButton(
                  icon: const Icon(Icons.lightbulb_outline, size: 14, color: Colors.white30),
                  onPressed: () => _discoveryService.sendIdentify(f.ip),
                  tooltip: "Identify",
                  constraints: const BoxConstraints(), 
                  padding: EdgeInsets.zero
               ),
               if (!patched) ...[
                  const SizedBox(width: 8),
                  IconButton(
                     icon: const Icon(Icons.add_circle, color: Color(0xFF64FFDA), size: 16),
                     constraints: const BoxConstraints(),
                     padding: EdgeInsets.zero,
                     onPressed: () {
                        // Add to ShowState
                        final newFixtures = List<Fixture>.from(showState.currentShow?.fixtures ?? [])..add(f);
                        showState.updateFixtures(newFixtures);
                        setState(() {
                           _discoveredDevices.remove(f);
                           _selectFixture(f, patched: true);
                        });
                     },
                  ),
               ]
            ],
         ),
      ),
    );
  }

  // Helper methods _buildSelectedHelper and _buildNumField removed

  Widget _buildFixtureVisual(Fixture f, bool isSelected) {
     final int w = (f.width > 0) ? f.width : 1;
     final int h = (f.height > 0) ? f.height : 1;
     // Use doubled static constants
     final double totalW = w * _SetupTabState.kStride;
     final double totalH = h * _SetupTabState.kStride;

     if (f.x.isNaN || f.x.isInfinite || f.y.isNaN || f.y.isInfinite) {
        return const SizedBox();
     }

     return Stack(
       clipBehavior: Clip.none,
       children: [
         // 1. The Tile (Grid Aligned - Defines Size)
         Transform.rotate(
           angle: f.rotation * 3.14159 / 180,
           child: Container(
             width: totalW,
             height: totalH,
             decoration: BoxDecoration(
               border: Border.all(
                  color: isSelected ? const Color(0xFF64FFDA) : Colors.white24, 
                  width: isSelected ? 2 : 1
               ),
               color: Colors.black54,
             ),
             child: CustomPaint(
               size: Size(totalW, totalH),
               painter: FixtureVisualPainter(width: w, height: h),
             ),
           ),
         ),
         
         // 2. The Label (Floating Above, Absolute Positioned)
         if (isSelected) 
            Positioned(
               left: 0,
               bottom: totalH, // Align bottom of label to top of tile
               child: IgnorePointer(
                  child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                     margin: const EdgeInsets.only(bottom: 4),
                     decoration: BoxDecoration(color: const Color(0xFF64FFDA), borderRadius: BorderRadius.circular(4)),
                     child: Text(f.name, style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
               ),
            ),
       ],
     );
  }
}

class FixtureVisualPainter extends CustomPainter {
  final int width;
  final int height;
  
  FixtureVisualPainter({required this.width, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    // 12px size + 4px space = 16px stride
    const double pxSize = 12.0;
    const double pxSpace = 4.0;
    final Paint paint = Paint()..color = Colors.grey[400]!;

    // LOD Optimization
    if (width * height > 1000) {
       canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..style = PaintingStyle.stroke..color = Colors.white24);
       canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), Paint()..color = Colors.white10);
       canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), Paint()..color = Colors.white10);
       return;
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
         double left = x * (pxSize + pxSpace);
         double top = y * (pxSize + pxSpace);
         
         // Orientation Marker (Pin 1)
         if (x == 0 && y == 0) {
            canvas.drawRect(Rect.fromLTWH(left, top, pxSize, pxSize), Paint()..color = Colors.grey[800]!);
         } else {
            canvas.drawRect(Rect.fromLTWH(left, top, pxSize, pxSize), paint);
         }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FixtureVisualPainter old) {
    return old.width != width || old.height != height;
  }
}

class GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintMain = Paint()..color = Colors.white.withValues(alpha: 0.1)..strokeWidth = 1.0;
    final paintSub = Paint()..color = Colors.white.withValues(alpha: 0.03)..strokeWidth = 0.5;

    // Sub Lines (16px = 1 Pixel Stride)
    const double subStep = 16.0;
    const double mainStep = 80.0; // 5x5 sub-blocks? User said "half of 10x10". 10x10 is 160px. Half is 80px.
    // 80/16 = 5. So Major Grid is every 5 pixels. 5x5 = 25 pixels.
    // 10x10 device (160px) covers 2 Major Grids (80px * 2). Correct.

    // Sub Lines
    for (double x = 0; x < size.width; x += subStep) {
      if (x % mainStep != 0) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintSub);
    }
    for (double y = 0; y <= size.height; y += subStep) {
      if (y % mainStep != 0) canvas.drawLine(Offset(0, y), Offset(size.width, y), paintSub);
    }
    
    // Main Lines
    for (double x = 0; x <= size.width; x += mainStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintMain);
    }
    for (double y = 0; y <= size.height; y += mainStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintMain);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
