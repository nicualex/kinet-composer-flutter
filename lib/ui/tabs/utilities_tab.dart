import 'package:flutter/material.dart';
import 'package:kinet_composer/ui/tabs/project_tab.dart';
import 'package:kinet_composer/ui/tabs/setup_tab.dart';

class UtilitiesTab extends StatefulWidget {
  const UtilitiesTab({super.key});

  @override
  State<UtilitiesTab> createState() => _UtilitiesTabState();
}

class _UtilitiesTabState extends State<UtilitiesTab> {
  int _selectedIndex = 0; // 0: Network, 1: Setup

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main Content Area
        Expanded(
          child: Container(
             color: Colors.black87,
             child: _selectedIndex == 0 
                ? const ProjectTab() 
                : const SetupTab(),
          ),
        ),

        // Sidebar Navigation
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: const Border(left: BorderSide(color: Colors.white12)),
            boxShadow: [
               BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(-2, 0))
            ]
          ),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text("UTILITIES", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
               const SizedBox(height: 20),

               // Navigation Buttons
               _buildNavButton(
                 index: 0,
                 icon: Icons.cloud_upload,
                 label: "Network & Upload",
                 description: "Scan players & upload shows"
               ),
               const SizedBox(height: 12),
               _buildNavButton(
                 index: 1,
                 icon: Icons.grid_on,
                 label: "Matrix Setup",
                 description: "Configure pixel grid"
               ),
            ],
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
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.1) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? color.withOpacity(0.5) : Colors.white12),
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
                      Text(description, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
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
