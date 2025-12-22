import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  late final Player _player;
  late final VideoController _controller;
  
  bool _canEnter = false; // Set to true when video ends? Or immediate? User: "Mandatory to play". 
  // Let's make it so you can enter anytime, but it plays by default. 
  // Or force watch? "Mandatory to play" implies auto-start. 
  // I will show "Enter App" immediately but assume user watches.
  // Actually, "Mandatory to play for the first startup" usually means "You see it". Not necessarily locked.
  
  bool _dontShowAgain = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    
    _player.open(Media('asset:///assets/intro.mp4'));
    _player.setVolume(100);
    
    // Auto-enter or show button on finish?
    _player.stream.completed.listen((completed) {
      if (completed) {
         setState(() {
            _canEnter = true; 
         });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _enterApp() async {
     if (_dontShowAgain) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('show_intro', false);
     }
     
     if (mounted) {
       Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen())
       );
     }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
         children: [
            // Video Layer
            Positioned.fill(
               child: Video(controller: _controller, fit: BoxFit.cover, controls: NoVideoControls),
            ),
            
            // Overlay Controls
            Positioned(
               bottom: 50,
               right: 50,
               child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                     // Enter Button
                     ElevatedButton.icon(
                        onPressed: _enterApp, 
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text("ENTER COMPOSER"),
                        style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.cyanAccent,
                           foregroundColor: Colors.black,
                           padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                           textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                        ),
                     ),

                     const SizedBox(height: 16),

                     // Checkbox
                     Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Checkbox(
                              value: _dontShowAgain,
                              activeColor: Colors.cyanAccent,
                              onChanged: (val) {
                                 setState(() => _dontShowAgain = val ?? false);
                              },
                           ),
                           const Text("Don't show again", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold,  shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                        ],
                     ),
                  ],
               ),
            ),
         ],
      ),
    );
  }
}
