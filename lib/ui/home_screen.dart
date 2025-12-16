import 'package:flutter/material.dart';
import 'package:kinet_composer/ui/tabs/utilities_tab.dart';
import 'package:kinet_composer/ui/tabs/shows_tab.dart';

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
             backgroundColor: Colors.transparent,
             elevation: 0,
             toolbarHeight: 0, // Effectively hides the title area
             bottom: const TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorColor: Colors.cyanAccent,
              labelColor: Colors.cyanAccent,
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(icon: Icon(Icons.settings), text: 'Utilities'),
                Tab(icon: Icon(Icons.slideshow), text: 'Shows'),
              ],
            ),
          ),
          body: const TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [
              UtilitiesTab(),
              ShowsTab(),
            ],
          ),
        ),
      ),
    );
  }
}
