import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:kinet_composer/ui/tabs/setup_tab.dart';
import 'package:kinet_composer/ui/tabs/video_tab.dart';
import 'package:kinet_composer/state/show_state.dart';

Future<void> _confirmInitialize(BuildContext context, ShowState showState) async {
     // Check if we need confirmation (fixtures exist)
     final hasData = showState.currentShow?.fixtures.isNotEmpty ?? false;
     
     if (hasData) {
        final confirm = await showDialog<bool>(
           context: context,
           builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF333333),
              title: const Text("Initialize Show?", style: TextStyle(color: Colors.white)),
              content: const Text(
                 "This will clear the current show.\n\nAre you sure?",
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
     showState.newShow(); 
     // Note: We can't easily clear _discoveredControllers in SetupTab from here without a global event bus or key.
     // But ShowState cleanup is the critical part.
     if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Show Initialized.")));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A1A2E), // Deep Dark Blue/Purple
              Color(0xFF16213E), // Dark Blue
              Color(0xFF0F3460), // Lighter Navy
            ],
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent, // Let gradient show through
          appBar: AppBar(
             backgroundColor: const Color(0xFF111111),
             elevation: 0,
             toolbarHeight: kToolbarHeight, 
             title: Consumer<ShowState>(
                builder: (context, showState, child) {
                   return Row(
                      children: [
                         // 1. Logo + Title
                         Row(
                           mainAxisSize: MainAxisSize.min,
                           crossAxisAlignment: CrossAxisAlignment.center,
                           children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.asset("assets/ck logo gray.jpg", height: 20, width: 20, fit: BoxFit.cover),
                                ),
                              ),
                              Text("LT COMPOSER", style: TextStyle(
                                fontFamily: 'Roboto', 
                                color: const Color(0xFFEEEEEE), 
                                fontSize: 13, 
                                fontWeight: FontWeight.w300, 
                                letterSpacing: 3.0
                              )),
                              // Removed Duplicate Show Name
                              const SizedBox(width: 24),
                           ],
                         ),

                         // 2. Global Action Buttons (Moved to Left)
                         IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.redAccent),
                            tooltip: "Initialize New Show",
                            onPressed: () => _confirmInitialize(context, showState),
                         ),
                         IconButton(
                            icon: const Icon(Icons.file_open, color: Colors.white70),
                            tooltip: "Load Show",
                            onPressed: () => showState.loadShow(),
                         ),
                         IconButton(
                            icon: const Icon(Icons.save_alt, color: Colors.white70),
                            tooltip: "Save Show",
                            onPressed: () => showState.saveShow(forceDialog: true),
                         ),
                         
                         const SizedBox(width: 24),

                         // 3. Tabs (Moved to Left)
                         SizedBox(
                           width: 300, // Fixed width for tabs to keep them compact on left
                           child: const TabBar(
                               isScrollable: false,
                               dividerColor: Colors.transparent,
                               indicatorSize: TabBarIndicatorSize.label,
                               indicatorColor: Colors.cyanAccent,
                               labelColor: Colors.cyanAccent,
                               unselectedLabelColor: Colors.white54,
                               tabs: [
                                 Tab(text: 'SETUP'), 
                                 Tab(text: 'COMPOSER'),
                               ],
                             ),
                         ),

                         // 4. Center Show Name (Expanded pushes it to center relative to remaining space, but true center needs strict alignment)
                         // To get vaguely center, we use Expanded on both sides? No, just Expanded here.
                         Expanded(
                           child: Center(
                             child: Text(
                                showState.currentShow?.name ?? "New Show", 
                                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)
                              ),
                           ),
                         ),
                         
                         // Spacer to balance the Right Actions (Window Buttons) if we want TRUE center, 
                         // but Window Buttons are in `actions` property, so they are outside this Row.
                         // This Row is the `title`.
                         // So [Left Stuff] [Expanded->Center->Text] [Right Edge of Title] [Actions]
                         // This will center the text within the remaining available space of the title widget.
                         // Since Left Stuff is wide, "Center" will be shifted right.
                         // Ideally we want absolute center. But `NavigationToolbar` is complex.
                         // `Center` in `Expanded` is good enough for now.
                      ],
                   );
                }
             ),
             centerTitle: false, // We handle layout manually
             flexibleSpace: MoveWindow(),
             actions: [
                MinimizeWindowButton(colors: WindowButtonColors(iconNormal: Colors.white)),
                MaximizeWindowButton(colors: WindowButtonColors(iconNormal: Colors.white)),
                CloseWindowButton(colors: WindowButtonColors(iconNormal: Colors.white, mouseOver: Colors.redAccent)),
             ], 
             bottom: null, 
          ),
          body: const TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [
              SetupTab(),
              VideoTab(),
            ],
          ),
        ),
      ),
    );
  }
}
