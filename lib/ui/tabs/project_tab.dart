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
  final List<Fixture> _discoveredDevices = [];
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    // Start listening to discovery stream
    final discovery = context.read<DiscoveryService>();
    discovery.deviceStream.listen((device) {
      setState(() {
        // Dedup by IP
        final index = _discoveredDevices.indexWhere((d) => d.ip == device.ip);
        if (index != -1) {
          _discoveredDevices[index] = device;
        } else {
          _discoveredDevices.add(device);
        }
      });
    });
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                       Text('Project: ${showState.currentShow?.name ?? "None"}', 
                           style: Theme.of(context).textTheme.headlineSmall),
                       const SizedBox(width: 10),
                       IconButton(
                         icon: const Icon(Icons.edit, size: 20),
                         onPressed: () async {
                            final nameController = TextEditingController(text: showState.currentShow?.name);
                            final newName = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text("Rename Project"),
                                content: TextField(
                                  controller: nameController,
                                  decoration: const InputDecoration(labelText: "Project Name"),
                                  autofocus: true,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Cancel"),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context, nameController.text);
                                    },
                                    child: const Text("Save"),
                                  ),
                                ],
                              ),
                            );
                            
                            if (newName != null && newName.isNotEmpty) {
                              showState.updateName(newName);
                            }
                         },
                       ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('File: ${showState.fileName ?? "Unsaved"} ${showState.isModified ? "(Modified)" : ""}'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => showState.newShow(),
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => showState.loadShow(),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => showState.saveShow(),
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Discovery & Deployment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Discovered Players', style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: _toggleDiscovery,
                icon: Icon(_isDiscovering ? Icons.stop : Icons.refresh),
                label: Text(_isDiscovering ? 'Stop Scan' : 'Scan Devices'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDiscovering ? Colors.red.withAlpha(50) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = _discoveredDevices[index];
                return ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(device.name),
                  subtitle: Text('${device.ip} (Kinet V${device.protocol})'),
                  trailing: ElevatedButton(
                    onPressed: () => _uploadShow(device.ip),
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
