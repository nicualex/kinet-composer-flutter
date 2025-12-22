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
import 'package:flutter/services.dart';
import 'dart:math';


import 'package:kinet_composer/ui/widgets/grid_background_painter.dart';

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
  List<Fixture> _discoveredControllers = []; // Local cache for scanning results
  
  // Sidebar State
  // int _sidebarTab = 0; // Removed

  final TransformationController _transformationController = TransformationController();
  
  bool _enablePan = true;
  
  // Drag State
  Offset? _dragStartPos;
  Offset? _lastLocalPos;
  Offset _dragAccumulator = Offset.zero;
  
  String? _selectedFixtureId;
  Fixture? _selectedDiscoveredController; // Track selection for discovered (unpatched) items
  BoxConstraints? _lastCanvasConstraints; // For Fit to Window button
  
  // Layout Editors
  // Layout Editors (Removed per user request)

  bool _pendingAutoFit = true;
  
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

  // Property Editor State
  bool _isEditingProperties = false;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ipCtrl = TextEditingController();
  final TextEditingController _dmxCtrl = TextEditingController();
  final TextEditingController _univCtrl = TextEditingController();
  final TextEditingController _rotCtrl = TextEditingController();

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
    _transformationController.dispose();
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _dmxCtrl.dispose();
    _univCtrl.dispose();
    _rotCtrl.dispose();
    super.dispose();
  }

  void _startScan(ShowState showState) async {
    if (_selectedInterface == null) return;
    
    String bindIp = _selectedInterface!.addresses.first.address;
    debugPrint("STARTING SCAN on $bindIp");
    
    // Auto-Unlock Grid on Scan
    showState.setGridLock(false);

    setState(() {
       _isScanning = true;
       _discoveredControllers.clear();
    });
    
    await _discoveryService.startDiscovery(interfaceIp: bindIp);
    
    // Listen to controller stream
    _scanSub?.cancel();
    _scanSub = _discoveryService.controllerStream.listen((device) {
       if (!mounted) return;
       setState(() {
             // Deduplicate based on IP
          if (!_discoveredControllers.any((d) => d.ip == device.ip)) {
             // Default Position: 
             final positionedDevice = device.copyWith(
                id: "${device.ip}-${DateTime.now().millisecondsSinceEpoch}", // Ensure Unique ID
                x: (_discoveredControllers.length * kStride * 2),
                y: 160.0, // Default Y in bounds
             );
             _discoveredControllers.add(positionedDevice);
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
       // Check if re-selecting the same fixture
       final bool sameSelection = patched 
          ? (_selectedFixtureId == f?.id) 
          : (_selectedDiscoveredController?.id == f?.id);

       if (f != null && sameSelection && _isEditingProperties) {
          // Do nothing - keep editing
          return;
       }

       if (patched) {
         _selectedFixtureId = f?.id;
         _selectedDiscoveredController = null;
       } else {
         _selectedFixtureId = null;
         _selectedDiscoveredController = f;
       }

       // Exit edit mode on any new selection or deselection
       _isEditingProperties = false;
       if (f != null) {
          _nameCtrl.text = f.name;
          _ipCtrl.text = f.ip;
          _dmxCtrl.text = f.dmxAddress.toString();
          _univCtrl.text = f.universe.toString();
          _rotCtrl.text = f.rotation.toString();
       }
    });
  }

  void _rotateFixture(Fixture f, ShowState state) {
     final newRot = (f.rotation + 90) % 360;
      setState(() {
         if (_selectedDiscoveredController != null && _selectedDiscoveredController!.id == f.id) {
            final index = _discoveredControllers.indexWhere((d) => d.id == f.id);
            if (index != -1) {
               final newF = f.copyWith(rotation: newRot);
               _discoveredControllers[index] = newF;
               _selectedDiscoveredController = newF; 
               _rotCtrl.text = newRot.toString();
            }
        } else {
           state.updateFixturePosition(f.id, f.x, f.y, newRot);
           _rotCtrl.text = newRot.toString();
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
        _selectFixture(f, patched: _discoveredControllers.indexWhere((d)=>d.id==f.id) == -1);
      });
  }

  Rect _getVisualBounds(Fixture f) {
      final double rads = f.rotation * 3.14159 / 180;
      final double w = f.width * kStride;
      final double h = f.height * kStride;
      
      // Calculate rotated bounding box size
      final double absCos = cos(rads).abs();
      final double absSin = sin(rads).abs();
      final double newW = (w * absCos + h * absSin).roundToDouble();
      final double newH = (w * absSin + h * absCos).roundToDouble();
      
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
             ..._discoveredControllers
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
     // Disable Scrub Selection if Editing Properties
     if (_isEditingProperties) return;

     // Find fixture under point
     for (final f in [...fixtures, ..._discoveredControllers]) {
        if (_getVisualBounds(f).contains(localPos)) {
           // Found!
           if (_selectedFixtureId != f.id && _selectedDiscoveredController?.id != f.id) {
               // Determine if patched or discovered
               bool isPatched = fixtures.any((fix) => fix.id == f.id);
               _selectFixture(f, patched: isPatched);
           }
           return;
        }
     }
     
     // Detect Miss (Hovering Empty Space)
     if (_selectedFixtureId != null || _selectedDiscoveredController != null) {
        _selectFixture(null);
     }
  }

  void _updateFixtureLocation(Fixture f, double x, double y, ShowState state) {
      if (_selectedDiscoveredController != null && _selectedDiscoveredController!.id == f.id) {
         final index = _discoveredControllers.indexWhere((d) => d.id == f.id);
         if (index != -1) {
            setState(() {
               final newF = f.copyWith(x: x, y: y);
               _discoveredControllers[index] = newF;
               _selectedDiscoveredController = newF;
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
         final index = _discoveredControllers.indexWhere((d) => d.id == f.id);
         if (index != -1) {
            final newF = f.copyWith(
               x: x ?? f.x,
               y: y ?? f.y,
               rotation: r ?? f.rotation
            );
            _discoveredControllers[index] = newF;
            _selectedDiscoveredController = newF;
        }
     });
  }

  void _fitToScreen(List<Fixture> fixtures, BoxConstraints constraints) {
      double minX, minY, maxX, maxY;
      
      if (fixtures.isEmpty) {
          // Empty Canvas: Fit the whole workspace
          minX = 0;
          minY = 0;
          maxX = kCanvasWidth;
          maxY = kCanvasHeight;
      } else {
          minX = double.infinity; minY = double.infinity;
          maxX = double.negativeInfinity; maxY = double.negativeInfinity;
          
          for (var f in fixtures) {
             if (f.x < minX) minX = f.x;
             if (f.y < minY) minY = f.y;
             if (f.x + (f.width*kStride) > maxX) maxX = f.x + (f.width*kStride); 
             if (f.y + (f.height*kStride) > maxY) maxY = f.y + (f.height*kStride);
          }
      }
      
      // Empty Canvas: Default to 1.0 Scale, Centered
      if (fixtures.isEmpty) {
          final double canvasW = kCanvasWidth;
          final double canvasH = kCanvasHeight;
          
          // Center the 3200x1600 canvas in the viewport
          final double dx = (constraints.maxWidth - canvasW) / 2.0;
          final double dy = (constraints.maxHeight - canvasH) / 2.0;
          
          final Matrix4 matrix = Matrix4.identity()
            ..translate(dx, dy)
            ..scale(1.0); // 100% Zoom Default
          
          _transformationController.value = matrix;
          return;
      }
      
      double w = maxX - minX;
      double h = maxY - minY;
      // Ensure w/h not zero to avoid division issues (though empty case handles this)
      if (w < 100) w = 100;
      if (h < 100) h = 100;

      double scaleX = constraints.maxWidth / (w + 200); // 100px padding
      double scaleY = constraints.maxHeight / (h + 200);
      double scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.01, 1.0); // Don't zoom in too much automatically
      
      final Matrix4 matrix = Matrix4.identity()
        ..translate(constraints.maxWidth/2, constraints.maxHeight/2)
        ..scale(scale)
        ..translate(-(minX + w/2), -(minY + h/2));
        
      _transformationController.value = matrix;
  }
  
  // Save/Load Patch Handlers (Now Grid Export/Import)
  Future<void> _exportGrid(BuildContext context, ShowState showState) async {
     final show = showState.currentShow;
     if (show == null || show.fixtures.isEmpty) return; // Should be disabled anyway
     
     String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Grid',
        fileName: 'grid_layout.json',
        allowedExtensions: ['json'],
        type: FileType.custom,
     );
     
     if (path != null) {
        try {
           // Encode List<Fixture>
           final json = jsonEncode(show.fixtures.map((e) => e.toJson()).toList());
           await File(path).writeAsString(json);
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Grid Exported Successfully")));
        } catch (e) {
           debugPrint("Error saving grid: $e");
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error exporting grid: $e"), backgroundColor: Colors.red));
        }
     }
  }

   Future<void> _importGrid(BuildContext context, ShowState showState) async {
      // 1. Check for existing data warning
      if (showState.currentShow?.fixtures.isNotEmpty == true) {
         final bool? confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
               backgroundColor: const Color(0xFF202020),
               title: const Text("Overwrite Show?", style: TextStyle(color: Colors.white)),
               content: const Text(
                  "Importing a grid will CLEAR the current show content (layers, effects) and replace the existing controllers.\n\nThis action cannot be undone.",
                  style: TextStyle(color: Colors.white70),
               ),
               actions: [
                  TextButton(
                     onPressed: () => Navigator.of(context).pop(false),
                     child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                  ),
                  FilledButton(
                     onPressed: () => Navigator.of(context).pop(true),
                     style: FilledButton.styleFrom(backgroundColor: Colors.red),
                     child: const Text("OVERWRITE"),
                  ),
               ],
            ),
         );

         if (confirm != true) return; // Cancelled
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles(
         type: FileType.custom,
         allowedExtensions: ['json', 'show'],
      );
      
      if (result != null && result.files.single.path != null) {
         try {
            final file = File(result.files.single.path!);
            final bytes = await file.readAsBytes();
            String content;
            
            // Check BOM for UTF-16LE (FF FE)
            if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
               final codes = <int>[];
               for (int i = 2; i < bytes.length - 1; i += 2) {
                  codes.add(bytes[i] | (bytes[i + 1] << 8));
               }
               content = String.fromCharCodes(codes);
            } else {
                try {
                  content = utf8.decode(bytes);
               } catch (_) {
                  content = String.fromCharCodes(bytes);
               }
            }

             final dynamic json = jsonDecode(content);
             List<Fixture> fixtures = [];

             if (json is List) {
                // Legacy: List of Fixtures
                debugPrint("LoadPatch: Detected List format.");
                fixtures = json.map((e) => _clampToCanvas(Fixture.fromJson(e))).toList();
             } else if (json is Map) {
                // Show Manifest
                debugPrint("LoadPatch: Detected Map format. Keys: ${json.keys.toList()}");
                if (json.containsKey('fixtures') && json['fixtures'] is List) {
                   fixtures = (json['fixtures'] as List)
                      .map((e) => _clampToCanvas(Fixture.fromJson(e)))
                      .toList();
                } else if (json.containsKey('controllers') && json['controllers'] is List) {
                   // Fallback for simulation files
                    debugPrint("LoadPatch: Using 'controllers' fallback.");
                    fixtures = (json['controllers'] as List)
                      .map((e) => _clampToCanvas(Fixture.fromJson(e)))
                      .toList();
                } else {
                   throw "Invalid Format: JSON Object must contain 'fixtures' or 'controllers' list. Found: ${json.keys.toList()}";
                }
             } else {
                debugPrint("LoadPatch: Unknown Type: ${json.runtimeType}");
                throw "Invalid Json Format (Not Map or List)";
             }
             
             // Sanitize IDs (Deduplicate)
             final idSet = <String>{};
             for (var i=0; i<fixtures.length; i++) {
                var f = fixtures[i];
                if (idSet.contains(f.id)) {
                   final newId = "${f.id}_${DateTime.now().microsecondsSinceEpoch}_$i";
                   fixtures[i] = f.copyWith(id: newId);
                   idSet.add(newId);
                } else {
                   idSet.add(f.id);
                }
             }

             // CRITICAL: Reset Show BEFORE loading Grid
             showState.newShow(); 
             
             // Load New Fixtures
             showState.updateFixtures(fixtures);
             
             // Auto-Lock Grid on Load
             showState.setGridLock(true);
             
             setState(() {
                _discoveredControllers.clear();
                _selectedFixtureId = null;
                _selectedDiscoveredController = null;
                _pendingAutoFit = true; // Trigger Auto-Fit
             });
             
             if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Grid Imported (${fixtures.length} devices) - Show Reset")));
         } catch (e) {
            debugPrint("Error loading patch: $e");
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading file: $e"), backgroundColor: Colors.red));
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

  Future<void> _confirmInitialize(BuildContext context, ShowState showState) async {
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
       
       // Proceed
       showState.updateFixtures([]);
       setState(() {
           _discoveredControllers.clear();
           _selectedFixtureId = null;
           _selectedDiscoveredController = null;
       }); // Clear local discovery too
       
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Show Initialized (Cleared).")));
  }

  void _enterEditMode(Fixture f) {
    setState(() {
      _isEditingProperties = true;
      _nameCtrl.text = f.name;
      _ipCtrl.text = f.ip;
      _dmxCtrl.text = f.dmxAddress.toString();
      _univCtrl.text = f.universe.toString();
      _rotCtrl.text = f.rotation.toString();
    });
  }

  void _exitEditMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isEditingProperties = false;
    });
  }

  void _saveProperties(ShowState showState) {
    final selectedFixture = _selectedFixtureId != null
        ? showState.currentShow?.fixtures.firstWhere((f) => f.id == _selectedFixtureId)
        : _selectedDiscoveredController;

    if (selectedFixture == null) return;

    final newName = _nameCtrl.text;
    final newIp = _ipCtrl.text;
    final newDmx = int.tryParse(_dmxCtrl.text) ?? selectedFixture.dmxAddress;
    final newUniv = int.tryParse(_univCtrl.text) ?? selectedFixture.universe;
    // Fix Type Error
    final newRot = double.tryParse(_rotCtrl.text) ?? selectedFixture.rotation;

    final updatedFixture = selectedFixture.copyWith(
      name: newName,
      ip: newIp,
      dmxAddress: newDmx,
      universe: newUniv,
      rotation: newRot,
    );

    setState(() {
      if (_selectedFixtureId != null) {
        showState.updateFixture(updatedFixture);
      } else if (_selectedDiscoveredController != null) {
        final index = _discoveredControllers.indexWhere((f) => f.id == updatedFixture.id);
        if (index != -1) {
          _discoveredControllers[index] = updatedFixture;
          _selectedDiscoveredController = updatedFixture;
        }
      }
      _isEditingProperties = false;
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fixture properties updated.")));
  }

  void _showContextMenu(Fixture f, ShowState showState, Offset globalPosition) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40), // smaller rect, if touch is on a line use a small rectangle
        Offset.zero & overlay.size, // Bigger rect, full screen
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'edit',
          child: const Text('Edit Properties'),
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) => _enterEditMode(f)),
        ),
        PopupMenuItem(
          value: 'rotate',
          child: const Text('Rotate 90°'),
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) => _rotateFixture(f, showState)),
        ),
        if (_selectedDiscoveredController?.id == f.id)
          PopupMenuItem(
            value: 'patch',
            child: const Text('Patch Controller'),
            onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) {
              showState.addFixture(f);
              setState(() {
                _discoveredControllers.removeWhere((d) => d.id == f.id);
                _selectedDiscoveredController = null;
                _selectedFixtureId = f.id;
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${f.name} patched successfully.")));
            }),
          ),
        if (_selectedFixtureId == f.id)
          PopupMenuItem(
            value: 'unpatch',
            child: const Text('Unpatch Controller'),
            onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) {
              showState.removeFixture(f.id);
              setState(() {
                _selectedFixtureId = null;
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${f.name} unpatched.")));
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _exitEditMode,
      },
      child: Focus(
        autofocus: true,
        child: Consumer<ShowState>(
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
        if (_selectedDiscoveredController != null) {
           selectedFixture = _selectedDiscoveredController;
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
                       // Header REMOVED as per user request
                       // Container(...) was here, now empty/gone
                       // The entire header block with "SETUP" text is removed.
                      
                      // Unified Content
                      Expanded(
                        child: _isEditingProperties 
                           ? _buildPropertyEditor(showState) 
                           : ListView(
                           padding: EdgeInsets.zero,
                           children: [
                              // 1. Discovery Controls (Top)
                              _buildNetworkControls(showState),
                              
                              const Divider(height: 1, color: Colors.white12),

                              // 2. Grid Management
                              _buildGridControls(context, showState, fixtures),

                              const Divider(height: 1, color: Colors.white12),
                              
                              const Divider(height: 1, color: Colors.white12),
                              
                              // 2. Selected Properties REMOVED per user request
                              
                              // 3. Device Stats (Bottom)
                              _buildDeviceStats(fixtures, showState),
                              
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
                      _lastCanvasConstraints = constraints;
                      if (_pendingAutoFit && fixtures.isNotEmpty) {
                         WidgetsBinding.instance.addPostFrameCallback((_) { _fitToScreen(fixtures, constraints); _pendingAutoFit = false; });
                      }
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
                           panEnabled: true, // Always allow panning
                           scaleEnabled: true,
                           child: Listener(
                                onPointerDown: (e) {
                                   if (showState.isGridLocked) _onScrub(e.localPosition, fixtures);
                                },
                                onPointerMove: (e) {
                                   if (showState.isGridLocked) _onScrub(e.localPosition, fixtures);
                                },
                                onPointerHover: (e) {
                                   _onScrub(e.localPosition, fixtures);
                                },
                                child: GestureDetector(
                                   onTap: () {
                                      // Always deselect/exit edit mode on background tap
                                      _selectFixture(null);
                                      FocusScope.of(context).unfocus();
                                      setState(() {
                                         _selectedFixtureId = null;
                                         _selectedDiscoveredController = null;
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
                                    ..._discoveredControllers.map((f) => _buildPositionedDiscovered(f, showState, key: ValueKey("disc_${f.id}"))),
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
    ),
      ),
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
                     label: Text(_isScanning ? "STOP SCANNING" : "SCAN FOR CONTROLLERS"),
                     style: FilledButton.styleFrom(
                        backgroundColor: _isScanning ? Colors.redAccent : const Color(0xFF64FFDA),
                        foregroundColor: _isScanning ? Colors.white : Colors.black,
                     ),
                   ),
                 ),
                 const SizedBox(height: 8),
                 // Grid Lock Toggle
                 Row(
                    children: [
                       const Text("GRID LOCK", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                       const SizedBox(width: 12), // Moved closer
                       Transform.scale(
                         scale: 0.8, // Smaller switch
                         child: Switch(
                            value: showState.isGridLocked,
                            onChanged: (v) {
                               showState.setGridLock(v);
                               if (v) {
                                  // Grid Bounds Logic ...
                                  final fixtures = showState.currentShow?.fixtures ?? [];
                                  if (fixtures.isNotEmpty) {
                                     double minX = double.infinity; double minY = double.infinity;
                                     double maxX = double.negativeInfinity; double maxY = double.negativeInfinity;
                                     for (final f in fixtures) {
                                        final bounds = _getVisualBounds(f);
                                        if (bounds.left < minX) minX = bounds.left;
                                        if (bounds.top < minY) minY = bounds.top;
                                        if (bounds.right > maxX) maxX = bounds.right;
                                        if (bounds.bottom > maxY) maxY = bounds.bottom;
                                     }
                                     if (minX != double.infinity) {
                                        showState.updateGridBounds(maxX - minX, maxY - minY);
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Grid Set: ${(maxX - minX).ceil()} x ${(maxY - minY).ceil()}")));
                                     }
                                  }
                               }
                            },
                            activeColor: const Color(0xFF64FFDA),
                         ),
                       ),
                       const SizedBox(width: 8),
                       // Fit Button
                       SizedBox(
                          width: 40, height: 40, // Increased touch target
                          child: IconButton(
                             padding: EdgeInsets.zero,
                             tooltip: "Fit View", // Updated Tooltip
                             icon: const Icon(Icons.fit_screen, size: 28, color: Colors.white70), // Increased size
                             onPressed: () {
                                final fixtures = showState.currentShow?.fixtures ?? [];
                                if (fixtures.isNotEmpty && _lastCanvasConstraints != null) {
                                   _fitToScreen(fixtures, _lastCanvasConstraints!);
                                }
                             },
                          ),
                       ),
                       const Spacer(), // Push everything to the left side of the container
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

  Widget _buildPropertyEditor(ShowState showState) {
     return ListView(
        padding: const EdgeInsets.all(16),
        children: [
           const Text("EDIT CONTROLLER", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
           const SizedBox(height: 24),
           
           // Name
           const Text("NAME", style: TextStyle(color: Colors.white38, fontSize: 10)),
           const SizedBox(height: 4),
           TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                 filled: true, fillColor: Colors.white10,
                 isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none)
              ),
           ),
           const SizedBox(height: 16),

           // IP
           const Text("IP ADDRESS", style: TextStyle(color: Colors.white38, fontSize: 10)),
           const SizedBox(height: 4),
           TextField(
              controller: _ipCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                 filled: true, fillColor: Colors.white10,
                 isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none)
              ),
           ),
           const SizedBox(height: 16),
           
           // DMX
           Row(
              children: [
                 Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       const Text("UNIVERSE", style: TextStyle(color: Colors.white38, fontSize: 10)),
                       const SizedBox(height: 4),
                       TextField(
                          controller: _univCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                             filled: true, fillColor: Colors.white10,
                             isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none)
                          ),
                       ),
                    ],
                 )),
                 const SizedBox(width: 12),
                 Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       const Text("DMX ADDR", style: TextStyle(color: Colors.white38, fontSize: 10)),
                       const SizedBox(height: 4),
                       TextField(
                          controller: _dmxCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                             filled: true, fillColor: Colors.white10,
                             isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none)
                          ),
                       ),
                    ],
                 )),
              ],
           ),
           const SizedBox(height: 16),

           // Rotation
           const Text("ROTATION", style: TextStyle(color: Colors.white38, fontSize: 10)),
           const SizedBox(height: 4),
           TextField(
              controller: _rotCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                 filled: true, fillColor: Colors.white10,
                 isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none)
              ),
           ),
           const SizedBox(height: 16),

           // Serial (ReadOnly)
           const Text("SERIAL NO.", style: TextStyle(color: Colors.white38, fontSize: 10)),
           const SizedBox(height: 4),
           Container(
              padding: const EdgeInsets.all(10),
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
              child: Text(_selectedFixtureId ?? _selectedDiscoveredController?.id ?? "N/A", style: const TextStyle(color: Colors.white38, fontSize: 11)),
           ),
           
           const SizedBox(height: 40),
           
           // Buttons
           Row(
              children: [
                 Expanded(
                    child: TextButton(
                       onPressed: _exitEditMode,
                       style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.white12))
                       ),
                       child: const Text("CANCEL"),
                    ),
                 ),
                 const SizedBox(width: 12),
                 Expanded(
                    child: FilledButton(
                       onPressed: () => _saveProperties(showState),
                       style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF64FFDA),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                       ),
                       child: const Text("UPDATE"),
                    ),
                 ),
              ],
           )
        ],
     );
  }

  Widget _buildGridControls(BuildContext context, ShowState showState, List<Fixture> fixtures) {
      final bool hasFixtures = fixtures.isNotEmpty;
      
      return Container(
         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
         child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const Text("GRID MANAGEMENT", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
               const SizedBox(height: 8),
               Row(
                  children: [
                     Expanded(
                        child: TextButton.icon(
                           onPressed: () => _importGrid(context, showState),
                           icon: const Icon(Icons.file_upload, size: 16, color: Colors.white70),
                           label: const Text("IMPORT", style: TextStyle(color: Colors.white)),
                           style: TextButton.styleFrom(
                              backgroundColor: Colors.white10,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                 borderRadius: BorderRadius.circular(8),
                                 side: const BorderSide(color: Colors.white24, width: 1),
                              ),
                           ),
                        ),
                     ),
                     const SizedBox(width: 8),
                     Expanded(
                        child: TextButton.icon(
                           onPressed: hasFixtures ? () => _exportGrid(context, showState) : null,
                           icon: Icon(Icons.file_download, size: 16, color: hasFixtures ? Colors.white70 : Colors.white24),
                           label: Text("EXPORT", style: TextStyle(color: hasFixtures ? Colors.white : Colors.white24)),
                           style: TextButton.styleFrom(
                              backgroundColor: Colors.white10,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                 borderRadius: BorderRadius.circular(8),
                                 side: const BorderSide(color: Colors.white24, width: 1),
                              ),
                              // Disabled automatically handles opacity usually, but we set explicit colors
                           ),
                        ),
                     ),
                  ],
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
               // Disable Hover Selection if Editing Properties
               if (_isEditingProperties) return; 
               
               if (_selectedFixtureId != f.id) {
                  _selectFixture(f, patched: true);
               }
            },
            child: GestureDetector(
               behavior: HitTestBehavior.opaque,
                onTap: () => _selectFixture(f, patched: true),
                onLongPress: () => _enterEditMode(f),
                onSecondaryTapUp: (details) => _showContextMenu(f, showState, details.globalPosition),
                // Disable Drag/Pan if Locked OR Editing Properties
                onPanStart: (showState.isGridLocked || _isEditingProperties) ? null : (d) => _onDragStart(f, d),
                onPanUpdate: (showState.isGridLocked || _isEditingProperties) ? null : (d) => _onDragUpdate(f, d, showState),
                onPanEnd: (showState.isGridLocked || _isEditingProperties) ? null : (d) => _onDragEnd(f, d, showState),
                onPanCancel: (showState.isGridLocked || _isEditingProperties) ? null : () => _onDragEnd(f, null, showState),
                child: _buildFixtureVisual(f, isSelected, showState.isGridLocked),
             ),
         ),
      );
  }
  Widget _buildPositionedDiscovered(Fixture f, ShowState showState, {Key? key}) {
      final isSelected = _selectedDiscoveredController?.id == f.id;
      return Positioned(
         key: key,
         left: f.x, top: f.y,
         child: MouseRegion(
            onEnter: (_) {
               if (_dragStartPos != null) return;
               // Disable Hover Selection if Editing Properties
               if (_isEditingProperties) return;

               if (_selectedDiscoveredController?.id != f.id) {
                  _selectFixture(f, patched: false);
               }
            },
            child: GestureDetector(
               behavior: HitTestBehavior.opaque,
                onTap: () => _selectFixture(f, patched: false),
                onLongPress: () => _enterEditMode(f),
                onSecondaryTapUp: (details) => _showContextMenu(f, showState, details.globalPosition),
                // Disable Drag/Pan if Locked OR Editing Properties
                onPanStart: (showState.isGridLocked || _isEditingProperties) ? null : (d) => _onDragStart(f, d),
                onPanUpdate: (showState.isGridLocked || _isEditingProperties) ? null : (d) => _onDragUpdate(f, d, showState),
                onPanEnd: (showState.isGridLocked || _isEditingProperties) ? null : (d) => _onDragEnd(f, d, showState),
                onPanCancel: (showState.isGridLocked || _isEditingProperties) ? null : () => _onDragEnd(f, null, showState),
                child: Opacity(
                   opacity: 0.7, 
                   child: _buildFixtureVisual(f, isSelected, showState.isGridLocked),
                ),
             ),
         ),
      );
  }

  Widget _buildDeviceStats(List<Fixture> fixtures, ShowState showState) {
      int count10x10 = 0;
      int count5x5 = 0;
      int countOther = 0;
      
      for (var f in fixtures) {
         if (f.width == 10 && f.height == 10) count10x10++;
         else if (f.width == 5 && f.height == 5) count5x5++;
         else countOther++;
      }

       return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
               // Auto-Fit Button

               const Divider(height: 1, color: Colors.white12),

              // Stats
              Padding(
                 padding: const EdgeInsets.all(16),
                 child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       const Text("CONTROLLERS COUNT", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                       const SizedBox(height: 8),
                       _buildStatRow("10x10 Tiles", count10x10),
                       const SizedBox(height: 4),
                       _buildStatRow("5x5 Tiles", count5x5),
                       const SizedBox(height: 4),
                       if (countOther > 0) _buildStatRow("Other Sizes", countOther),
                       const SizedBox(height: 12),
                       Text("Total: ${fixtures.length}", style: const TextStyle(color: Color(0xFF64FFDA), fontWeight: FontWeight.bold)),
                    ],
                 ),
              ),
          ],
       );
  }
  
  Widget _buildStatRow(String label, int count) {
     return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
           Text(count.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
     );
  }

  // _buildDeviceTile removed as list is removed.

  // Helper methods _buildSelectedHelper and _buildNumField removed

  Widget _buildFixtureVisual(Fixture f, bool isSelected, bool isLocked) {
     final int w = (f.width > 0) ? f.width : 1;
     final int h = (f.height > 0) ? f.height : 1;
     // Use doubled static constants
     final double totalW = w * _SetupTabState.kStride;
     final double totalH = h * _SetupTabState.kStride;

     if (f.x.isNaN || f.x.isInfinite || f.y.isNaN || f.y.isInfinite) {
        return const SizedBox();
     }

     final Color highlightColor = _isEditingProperties 
          ? Colors.yellowAccent // Edit Mode = Yellow
          : (isLocked ? Colors.redAccent : Colors.cyanAccent); // Locked = Red, Default = Cyan

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
                  color: isSelected ? highlightColor : Colors.white24, 
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
                     decoration: BoxDecoration(color: highlightColor, borderRadius: BorderRadius.circular(4)),
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


