import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kinet_composer/state/show_state.dart';
import 'package:kinet_composer/services/discovery_service.dart';
import 'package:kinet_composer/services/file_uploader.dart';
import 'package:kinet_composer/models/show_manifest.dart';

class ProjectTab extends StatefulWidget {
  const ProjectTab({super.key});

  @override
  State<ProjectTab> createState() => _ProjectTabState();
}

class _ProjectTabState extends State<ProjectTab> {
  final List<Fixture> _discoveredControllers = [];
  bool _isDiscovering = false;
  StreamSubscription<Fixture>? _discoverySubscription;

  @override
  void initState() {
    super.initState();
    // Start listening to discovery stream
    final discovery = context.read<DiscoveryService>();
    _discoverySubscription = discovery.controllerStream.listen((device) {
      if (!mounted) return;
      setState(() {
        // Dedup by IP
        final index = _discoveredControllers.indexWhere((d) => d.ip == device.ip);
        if (index != -1) {
          _discoveredControllers[index] = device;
        } else {
          _discoveredControllers.add(device);
        }
      });
    });
  }
  
  @override
  void dispose() {
    _discoverySubscription?.cancel();
    super.dispose();
  }

  void _toggleDiscovery() {
    final discovery = context.read<DiscoveryService>();
    setState(() {
      _isDiscovering = !_isDiscovering;
      if (_isDiscovering) {
        discovery.startDiscovery();
      } else {
        discovery.stopDiscovery();
      }
    });
  }

  Future<void> _uploadShow(String ip) async {
    final showState = context.read<ShowState>();
    final messenger = ScaffoldMessenger.of(context);
    
    if (showState.currentShow == null) return;
    
    // 1. Ensure saved
    if (showState.currentFile == null || showState.isModified) {
       final shouldSave = await showDialog<bool>(
         context: context, 
         builder: (ctx) => AlertDialog(
           title: const Text('Save Show?'),
           content: const Text('You must save the show before uploading.'),
           actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
             ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save & Upload')),
           ],
         ),
       );

       if (shouldSave == true) {
         await showState.saveShow();
         if (showState.currentFile == null) return; // Cancelled save
       } else {
         return;
       }
    }

    // 2. Upload
    try {
      messenger.showSnackBar(const SnackBar(content: Text('Uploading...')));
      final success = await FileUploader().uploadShow(showState.currentFile!, ip);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(success ? 'Upload Complete!' : 'Upload Failed'),
        backgroundColor: success ? Colors.green : Colors.red,
      ));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final showState = context.watch<ShowState>();
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Management

          

          
          // Discovery & Deployment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Discovered Controllers', style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: _toggleDiscovery,
                icon: Icon(_isDiscovering ? Icons.stop : Icons.refresh),
                label: Text(_isDiscovering ? 'Stop Scan' : 'Scan Controllers'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDiscovering ? Colors.red.withAlpha(50) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _discoveredControllers.length,
              itemBuilder: (context, index) {
                final device = _discoveredControllers[index];
                return ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(device.name),
                  subtitle: Text('${device.ip} (Kinet V${device.protocol})'),
                  onTap: () async {
                     final confirm = await showDialog<bool>(
                       context: context,
                       builder: (c) => AlertDialog(
                         title: Text("Import '${device.name}'?"),
                         content: Text("Do you want to use this controller's configuration?\n\nDimensions: ${device.width} x ${device.height}\nIP: ${device.ip}"),
                         actions: [
                           TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
                           ElevatedButton(
                             onPressed: () => Navigator.pop(c, true), 
                             child: const Text("Use Controller")
                           ),
                         ],
                       ),
                     );

                     if (confirm == true && context.mounted) {
                        showState.importFixture(device);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Imported ${device.name} settings"))
                        );
                     }
                  },
                  trailing: ElevatedButton(
                    onPressed: (showState.currentShow != null && showState.currentShow!.mediaFile.isNotEmpty)
                        ? () => _uploadShow(device.ip)
                        : null,
                    child: const Text('Upload Show'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
