import 'package:flutter/material.dart';
import '../widgets/glass_container.dart';
import '../panels/controller_discovery_panel.dart';

class UtilitiesTab extends StatefulWidget {
  const UtilitiesTab({super.key});

  @override
  State<UtilitiesTab> createState() => _UtilitiesTabState();
}

class _UtilitiesTabState extends State<UtilitiesTab> {
  int _selectedIndex = 0; // 0: Device Discovery, 1: Layout Editor

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sidebar Navigation (Moved to Left)
        GlassContainer(
          padding: const EdgeInsets.all(20.0),
          tint: Colors.black, // Dark panel
          opacity: 0.95,       // Almost opaque for visibility
          borderRadius: const BorderRadius.only(topRight: Radius.circular(16), bottomRight: Radius.circular(16)),
          border: const Border(right: BorderSide(color: Colors.white12)),
          child: SizedBox(
            width: 320,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text("CONTROLLER", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
               const SizedBox(height: 20),

               // Navigation Buttons
               _buildNavButton(
                 index: 0,
                 icon: Icons.search,
                 label: "Controller Discovery",
                 description: "Scan KiNET v2 Controllers"
               ),
               const SizedBox(height: 12),
               _buildNavButton(
                 index: 1,
                 icon: Icons.grid_on,
                 label: "Layout Editor",
                 description: "Arrange discovered devices"
               ),
            ],
          ),
          ),
        ),

        // Main Content Area
        Expanded(
          child: Container(
             color: Colors.black,
             child: _selectedIndex == 0 
                ? const DeviceDiscoveryPanel() 
                : const Center(child: Text("LAYOUT EDITOR (Coming Soon)", style: TextStyle(color: Colors.white, fontSize: 30))),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton({required int index, required IconData icon, required String label, required String description}) {
      final isSelected = _selectedIndex == index;
      final color = isSelected ? const Color(0xFF90CAF9) : Colors.white10;
      
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.0),
              borderRadius: BorderRadius.circular(50), // Fully rounded
              border: Border.all(color: isSelected ? color.withValues(alpha: 0.5) : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? color : Colors.white70, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(description, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                    ],
                  ),
                ),
                if (isSelected) 
                   Icon(Icons.chevron_right, color: color, size: 20),
              ],
            ),
          ),
        ),
      );
  }
}
