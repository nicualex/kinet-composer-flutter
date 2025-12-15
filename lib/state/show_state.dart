import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart'; 
import 'package:path/path.dart' as p;
import '../models/show_manifest.dart';

class ShowState extends ChangeNotifier {
  ShowManifest? _currentShow;
  File? _currentFile;
  bool _isModified = false;

  ShowState() {
     _initNewShow();
  }

  void _initNewShow() {
    // Generate default 100x100 Matrix
    List<Pixel> pixels = [];
    for (int y = 0; y < 100; y++) {
      for (int x = 0; x < 100; x++) {
        pixels.add(Pixel(
          id: "$x:$y", 
          x: x, 
          y: y, 
          fixtureId: "matrix-1", 
          dmxInfo: DmxInfo(universe: 1, channel: 1) // Placeholder DMX
        ));
      }
    }

    _currentShow = ShowManifest(
      version: 1,
      name: 'New Show',
      mediaFile: '',
      fixtures: [
         Fixture(
            id: "matrix-1",
            name: "Matrix",
            ip: "192.168.1.100",
            port: 6038,
            protocol: "KiNET v2",
            width: 100,
            height: 100,
            pixels: pixels
         )
      ],
      settings: PlaybackSettings(loop: true, autoPlay: true),
    );
    _currentFile = null;
    _isModified = true; // Or false? Usually a new blank show is considered modified until saved, or "unsaved".
                        // Let's keep it true so it prompts to save?
                        // Actually, a fresh empty show might not need saving if empty.
                        // But user request implies standard behaviour.
  }

  ShowManifest? get currentShow => _currentShow;
  File? get currentFile => _currentFile;
  bool get isModified => _isModified;
  String? get fileName => _currentFile?.path.split(Platform.pathSeparator).last;

  void newShow() {
    _initNewShow();
    notifyListeners();
  }

  Future<void> loadShow() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kshow', 'json'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        _currentShow = ShowManifest.fromJson(json);
        _currentFile = file;
        _isModified = false;
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading show: $e');
        // Ideally rethrow or set error state
      }
    }
  }

  Future<void> saveShow() async {
    if (_currentShow == null) return;

    if (_currentFile == null) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Show',
        fileName: 'myshow.kshow',
        type: FileType.custom,
        allowedExtensions: ['kshow'],
      );

      if (path != null) {
        _currentFile = File(path);
      } else {
        return; // Cancelled
      }
    }

    if(_currentFile != null) {
       final json = _currentShow!.toJson();
       final content = const JsonEncoder.withIndent('  ').convert(json);
       await _currentFile!.writeAsString(content);
       _isModified = false;
       notifyListeners();
    }
  }

  void updateName(String name) {
    if (_currentShow != null) {
      _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: name,
        mediaFile: _currentShow!.mediaFile,
        mediaTransform: _currentShow!.mediaTransform,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  void updateMedia(String path) {
    if (_currentShow != null) {
      // Reset transform when loading new media
      final defaultTransform = MediaTransform(
        scaleX: 1.0, 
        scaleY: 1.0, 
        translateX: 0.0, 
        translateY: 0.0, 
        rotation: 0.0
      );
      
      _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: _currentShow!.name,
        mediaFile: path,
        mediaTransform: defaultTransform,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  void updateTransform(MediaTransform? transform) {
     if (_currentShow != null) {
      _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: _currentShow!.name,
        mediaFile: _currentShow!.mediaFile,
        mediaTransform: transform,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  void importFixture(Fixture fixture) {
    if (_currentShow != null) {
      _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: _currentShow!.name,
        mediaFile: _currentShow!.mediaFile,
        mediaTransform: _currentShow!.mediaTransform,
        fixtures: [fixture], // Replace existing fixtures with the imported one
        settings: _currentShow!.settings,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  void updateFixtureDimensions(String fixtureId, int width, int height) {
    if (_currentShow == null) return;

    final index = _currentShow!.fixtures.indexWhere((f) => f.id == fixtureId);
    if (index == -1) return;

    final oldFixture = _currentShow!.fixtures[index];
    
    // Regenerate pixels
    List<Pixel> newPixels = [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Preserve old pixel DMX if it existed at this coord? 
        // Or just reset? Simpler to reset for now or try to match.
        // Let's simple regenerate with default mapping behavior (row major).
        
        newPixels.add(Pixel(
          id: "$x:$y",
          x: x,
          y: y,
          fixtureId: fixtureId,
          dmxInfo: DmxInfo(universe: 1, channel: 1) // TODO: Auto-patch logic
        ));
      }
    }

    final newFixture = Fixture(
      id: oldFixture.id,
      name: oldFixture.name,
      ip: oldFixture.ip,
      port: oldFixture.port,
      protocol: oldFixture.protocol,
      width: width,
      height: height,
      pixels: newPixels
    );

    List<Fixture> newFixtures = List.from(_currentShow!.fixtures);
    newFixtures[index] = newFixture;

    _currentShow = ShowManifest(
      version: _currentShow!.version,
      name: _currentShow!.name,
      mediaFile: _currentShow!.mediaFile,
      mediaTransform: _currentShow!.mediaTransform,
      fixtures: newFixtures,
      settings: _currentShow!.settings,
    );
    _isModified = true;
    notifyListeners();
  }

  // --- BUNDLING FOR TRANSFER ---
  Future<File> createShowBundle(File thumbnail) async {
      if (_currentShow == null) throw Exception("No show loaded");

      try {
        final encoder = ZipFileEncoder();
        final tempDir = await getTemporaryDirectory();
        final bundlePath = '${tempDir.path}/bundle_${DateTime.now().millisecondsSinceEpoch}.kshow';
        
        encoder.create(bundlePath);
        
        // 1. Add Thumbnail
        encoder.addFile(thumbnail, 'thumbnail.png');
        
        // 2. Add Media File
        if (_currentShow!.mediaFile.isNotEmpty) {
           final mediaPath = _currentShow!.mediaFile;
           final mediaFile = File(mediaPath);
           if (await mediaFile.exists()) {
              encoder.addFile(mediaFile, 'media${p.extension(mediaPath)}');
              
              // Update Manifest to point to relative path "media.ext"
              // But we don't want to change the *current* state.
              // So create a copy of manifest.
              final exportManifest = ShowManifest(
                version: _currentShow!.version,
                name: _currentShow!.name,
                mediaFile: 'media${p.extension(mediaPath)}', // Relative path in zip
                mediaTransform: _currentShow!.mediaTransform,
                fixtures: _currentShow!.fixtures,
                settings: _currentShow!.settings
              );
              
              // 3. Add Manifest
              final jsonStr = jsonEncode(exportManifest.toJson());
              // Save temp manifest
              final manifestFile = File('${tempDir.path}/manifest.json');
              await manifestFile.writeAsString(jsonStr);
              encoder.addFile(manifestFile);
           }
        }
        
        encoder.close();
        return File(bundlePath);
      } catch (e) {
        debugPrint("Bundling error: $e");
        rethrow;
      }
  }
}
