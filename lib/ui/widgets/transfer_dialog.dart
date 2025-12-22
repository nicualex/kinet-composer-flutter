import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kinet_composer/models/show_manifest.dart';
import 'package:kinet_composer/services/discovery_service.dart';
import 'package:kinet_composer/services/file_uploader.dart';
import 'package:kinet_composer/state/show_state.dart';

class TransferDialog extends StatefulWidget {
  final File thumbnail;

  const TransferDialog({Key? key, required this.thumbnail}) : super(key: key);

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final Map<String, double> _transferProgress = {}; // IP -> Progress/Status
  final Map<String, String> _transferStatus = {}; // IP -> "Sending...", "Done", "Error"
  
  // Use a local list to accumulate discovered devices
  final List<Fixture> _discoveredPlayers = [];
  StreamSubscription<Fixture>? _scanSub; // Added StreamSubscription

  @override
  void initState() {
    super.initState();
    final discovery = context.read<DiscoveryService>();
    // Start Discovery
    discovery.startDiscovery();
    _scanSub = discovery.controllerStream.listen((player) {
       if (!mounted) return;
       if (!_discoveredPlayers.any((p) => p.ip == player.ip)) {
        setState(() {
          _discoveredPlayers.add(player);
        });
      }
    });
  }

  @override
  void dispose() {
    context.read<DiscoveryService>().stopDiscovery();
    super.dispose();
  }

  Future<void> _transferTo(Fixture player) async {
    setState(() {
      _transferStatus[player.ip] = "Bundling...";
    });

    try {
      // 1. Create Bundle
      final showState = context.read<ShowState>();
      final bundleFile = await showState.createShowBundle(widget.thumbnail);
      
      setState(() {
         _transferStatus[player.ip] = "Sending...";
      });

      // 2. Upload
      final uploader = FileUploader();
      final success = await uploader.uploadShow(
        bundleFile, 
        player.ip, 
        showName: showState.currentShow?.name ?? "Show"
      );

      if (mounted) {
        setState(() {
          _transferStatus[player.ip] = success ? "Success" : "Failed";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transferStatus[player.ip] = "Error: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Transfer to Player"),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Preview
            Center(
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  image: DecorationImage(
                    image: FileImage(widget.thumbnail),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Discovered Players:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            // Player List
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black12,
                border: Border.all(color: Colors.white10),
              ),
              child: _discoveredPlayers.isEmpty 
                  ? const Center(child: Text("Scanning for players...", style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: _discoveredPlayers.length,
                      itemBuilder: (context, index) {
                        final player = _discoveredPlayers[index];
                        final status = _transferStatus[player.ip];
                        
                        return ListTile(
                          leading: const Icon(Icons.monitor, color: Colors.blueAccent),
                          title: Text(player.name),
                          subtitle: Text(player.ip),
                          trailing: SizedBox(
                            width: 120,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (status == null)
                                  ElevatedButton(
                                    onPressed: () => _transferTo(player),
                                    child: const Text("Send"),
                                  )
                                else if (status == "Success")
                                  const Icon(Icons.check_circle, color: Colors.green)
                                else
                                  Expanded(child: Text(status, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
