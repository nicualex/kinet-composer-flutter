import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kinet_composer/state/show_state.dart';
import 'package:kinet_composer/models/show_manifest.dart';

import 'package:flutter/gestures.dart'; // For PointerScrollEvent
import 'package:kinet_composer/ui/widgets/pixel_grid_painter.dart';

class SetupTab extends StatefulWidget {
  const SetupTab({super.key});

  @override
  State<SetupTab> createState() => _SetupTabState();
}

class _SetupTabState extends State<SetupTab> {
  // Selection state
  String? _selectedFixtureId;
  final TransformationController _transformationController = TransformationController();

  // Controllers for editing
  final TextEditingController _widthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();

  // Auto-fit state
  int _lastFixtureHash = 0;
  Size? _lastViewSize;

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _selectFixture(Fixture? f) {
    setState(() {
       _selectedFixtureId = f?.id;
       if (f != null) {
         _widthCtrl.text = f.width.toString();
         _heightCtrl.text = f.height.toString();
       }
    });
  }

  void _fitToScreen(List<Fixture> fixtures, BoxConstraints constraints) {
    if (fixtures.isEmpty) return;

    // 1. Calculate Content Bounds
    double maxX = 0;
    double maxY = 0;
    const double gridSize = 10.0; // Must match painter

    for (var f in fixtures) {
      double fw = f.width * gridSize;
      double fh = f.height * gridSize;
      // Assuming naive positioning at 0,0 for now, or use f.x/y if/when added
      if (fw > maxX) maxX = fw;
      if (fh > maxY) maxY = fh;
    }

    final double contentWidth = maxX;
    final double contentHeight = maxY;

    // 2. Viewport Dimensions
    final double viewWidth = constraints.maxWidth;
    final double viewHeight = constraints.maxHeight;

    // 3. Determine Scale (with padding)
    final double padding = 50.0;
    final double availableWidth = viewWidth - (padding * 2);
    final double availableHeight = viewHeight - (padding * 2);

    double scaleX = availableWidth / contentWidth;
    double scaleY = availableHeight / contentHeight;
    double scale = (scaleX < scaleY) ? scaleX : scaleY;
    
    // Clamp scale
    scale = scale.clamp(0.1, 5.0);

    // 4. Center Translation
    // Center of content (relative to 0,0) is w/2, h/2
    final double contentCenterX = contentWidth / 2;
    final double contentCenterY = contentHeight / 2;

    // Center of viewport
    final double viewportCenterX = viewWidth / 2;
    final double viewportCenterY = viewHeight / 2;

    // Matrix: T(vx, vy) * S(s) * T(-cx, -cy)  <-- Logic: Move content center to origin, scale, move to viewport center
    final Matrix4 matrix = Matrix4.identity()
      ..translate(viewportCenterX, viewportCenterY)
      ..scale(scale)
      ..translate(-contentCenterX, -contentCenterY);

    _transformationController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShowState>(
      // ... (keep start)
      builder: (context, showState, child) {
        final fixtures = showState.currentShow?.fixtures ?? [];
        
        if (_selectedFixtureId == null && fixtures.isNotEmpty) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
             _selectFixture(fixtures.first);
           });
        }
        
        final selectedFixture = fixtures.isEmpty ? null : fixtures.firstWhere(
           (f) => f.id == _selectedFixtureId, orElse: () => fixtures.first
        );

        return Row(
          children: [
            // GRID AREA
            Expanded(
              child: Container(
                color: const Color(0xFF1E1E1E), 
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    
                    // Trigger Fit if fixtures changed OR Viewport changed
                    bool shouldFit = false;

                    // 1. Fixture Data Change
                    int currentHash = fixtures.length;
                    for(var f in fixtures) { currentHash += f.width; currentHash += f.height; }
                    
                    if (currentHash != _lastFixtureHash) {
                       _lastFixtureHash = currentHash;
                       shouldFit = true;
                    }

                    // 2. Viewport Size Change (Window Resize)
                    final currentSize = constraints.biggest;
                    if (_lastViewSize != currentSize) {
                       _lastViewSize = currentSize;
                       shouldFit = true;
                    }

                    if (shouldFit) {
                       WidgetsBinding.instance.addPostFrameCallback((_) {
                          _fitToScreen(fixtures, constraints);
                       });
                    }

                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                           // Zoom factor
                           final double scaleChange = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
                           
                           // Zoom around center of viewport
                           final Size viewportSize = constraints.biggest;
                           final Offset center = Offset(viewportSize.width / 2, viewportSize.height / 2);
                           
                           final Matrix4 currentMatrix = _transformationController.value;
                           
                           // Translate center to origin, scale, translate back
                           final Matrix4 zoomMatrix = Matrix4.identity()
                              ..translate(center.dx, center.dy)
                              ..scale(scaleChange)
                              ..translate(-center.dx, -center.dy);
                           
                           // Apply to current
                           final Matrix4 newMatrix = zoomMatrix * currentMatrix;
                           _transformationController.value = newMatrix;
                        }
                      },
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        boundaryMargin: const EdgeInsets.all(5000), 
                        minScale: 0.01,
                        maxScale: 20.0,
                        constrained: false,
                        child: SizedBox( // Canvas area
                           width: 10000, 
                           height: 10000,
                           child: CustomPaint(
                             painter: PixelGridPainter(fixtures: fixtures, gridSize: 10.0),
                           ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // PROPERTIES PANEL
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: const Border(
                  left: BorderSide(color: Colors.white24),
                ),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text("Setup & Patch",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 20),

                   const Text("Fixtures", style: TextStyle(color: Colors.white70)),
                   const SizedBox(height: 5),
                   // Simple List for now (selectable)
                   Container(
                     height: 150,
                     decoration: BoxDecoration(
                       border: Border.all(color: Colors.white24),
                       borderRadius: BorderRadius.circular(4),
                     ),
                     child: ListView.builder(
                       itemCount: fixtures.length,
                       itemBuilder: (ctx, i) {
                         final f = fixtures[i];
                         final isSelected = f.id == _selectedFixtureId;
                         return ListTile(
                           title: Text(f.name, style: const TextStyle(color: Colors.white)),
                           subtitle: Text("${f.width}x${f.height}", style: const TextStyle(color: Colors.grey)),
                           selected: isSelected,
                           selectedTileColor: Colors.blue.withOpacity(0.2),
                           onTap: () => _selectFixture(f),
                         );
                       },
                     ),
                   ),

                   const Divider(color: Colors.white24, height: 30),

                   if (selectedFixture != null) ...[
                      Row(
                         children: [
                            Expanded(child: Text("Properties: ${selectedFixture.name}", 
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                            IconButton(
                              icon: const Icon(Icons.center_focus_strong, color: Colors.white70),
                              tooltip: "Reset View",
                              onPressed: () {
                                 // Trigger re-fit manually
                                 setState(() { _lastFixtureHash = 0; });
                              },
                            )
                         ]
                      ),
                      const SizedBox(height: 15),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _widthCtrl,
                              decoration: const InputDecoration(
                                labelText: "Width (X)",
                                border: OutlineInputBorder(),
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              ),
                              style: const TextStyle(color: Colors.white),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _heightCtrl,
                              decoration: const InputDecoration(
                                labelText: "Height (Y)",
                                border: OutlineInputBorder(),
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              ),
                              style: const TextStyle(color: Colors.white),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                             final w = int.tryParse(_widthCtrl.text) ?? selectedFixture.width;
                             final h = int.tryParse(_heightCtrl.text) ?? selectedFixture.height;
                             showState.updateFixtureDimensions(selectedFixture.id, w, h);
                             
                             ScaffoldMessenger.of(context).showSnackBar(
                               const SnackBar(content: Text("Fixture Updated"), duration: Duration(milliseconds: 500))
                             );
                          },
                          icon: const Icon(Icons.update),
                          label: const Text("Update Grid"),
                        ),
                      ),
                   ] else 
                      const Text("Select a fixture to edit.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}


