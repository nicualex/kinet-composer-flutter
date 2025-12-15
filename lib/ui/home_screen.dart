import 'package:flutter/material.dart';
import 'package:kinet_composer/ui/tabs/project_tab.dart';
import 'package:kinet_composer/ui/tabs/setup_tab.dart';
import 'package:kinet_composer/ui/tabs/video_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kinet Composer'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.slideshow), text: 'Shows'), // Renamed from Project
              Tab(icon: Icon(Icons.grid_on), text: 'Setup'),
              Tab(icon: Icon(Icons.movie_creation), text: 'Videos / Effects'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            ProjectTab(),
            SetupTab(),
            VideoTab(),
          ],
        ),
      ),
    );
  }
}
