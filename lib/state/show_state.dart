import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart'; 
import 'package:path/path.dart' as p;
import '../models/show_manifest.dart';
import '../models/layer_config.dart';
import '../models/media_transform.dart';
import '../services/effect_service.dart';

class ShowState extends ChangeNotifier {
  ShowManifest? _currentShow;
  File? _currentFile;
  bool _isModified = false;

  ShowState() {
     _initNewShow();
  }

  // Helper to generate pixels for any grid
  List<Pixel> _generatePixels(int width, int height, String fixtureId) {
    List<Pixel> pixels = [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        pixels.add(Pixel(
          id: "$x:$y", 
          x: x, 
          y: y, 
          fixtureId: fixtureId, 
          dmxInfo: DmxInfo(universe: 1, channel: 1) // Default or Auto-patch placeholder
        ));
      }
    }
    return pixels;
  }

  void _initNewShow() {
    // Generate default 100x100 Matrix
    final pixels = _generatePixels(100, 100, "matrix-1");

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
    _isModified = true; 
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

    await saveShowAs(_currentFile!.path);
  }

  Future<void> saveShowAs(String path) async {
     if (_currentShow == null) return;
     
     final file = File(path);
     final json = _currentShow!.toJson();
     final content = const JsonEncoder.withIndent('  ').convert(json);
     await file.writeAsString(content);
     
     _currentFile = file;
     _isModified = false;
     notifyListeners();
  }

  void updateLayer({
    required bool isForeground,
    LayerType? type,
    String? path,
    EffectType? effect,
    Map<String, double>? params,
    double? opacity,

    bool? isVisible,
    MediaTransform? transform,
  }) {
    if (_currentShow == null) return;

    final currentLayer = isForeground ? _currentShow!.foregroundLayer : _currentShow!.backgroundLayer;

    final newLayer = currentLayer.copyWith(
      type: type,
      path: path,
      effect: effect,
      effectParams: params,
      opacity: opacity,
      isVisible: isVisible,
      transform: transform,
    );

    // Sync legacy mediaFile if updating background video
    String newMediaFile = _currentShow!.mediaFile;
    if (!isForeground && path != null) {
      newMediaFile = path;
    }

    _currentShow = ShowManifest(
      version: _currentShow!.version,
      name: _currentShow!.name,
      mediaFile: newMediaFile,
      fixtures: _currentShow!.fixtures,
      settings: _currentShow!.settings,
      backgroundLayer: isForeground ? _currentShow!.backgroundLayer : newLayer,
      foregroundLayer: isForeground ? newLayer : _currentShow!.foregroundLayer,
    );
    _isModified = true;
    notifyListeners();
  }

  void updateName(String name) {
    if (_currentShow != null) {
      _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: name,
        mediaFile: _currentShow!.mediaFile,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
        backgroundLayer: _currentShow!.backgroundLayer,
        foregroundLayer: _currentShow!.foregroundLayer,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  // updateTransform is removed. Use updateLayer(transform: ...) instead.

  // Legacy support or quick access for Background Video
  void updateMedia(String path) {
     updateLayer(isForeground: false, type: LayerType.video, path: path);
  }



  void setMediaAndTransform(String mediaPath, MediaTransform? transform) {
    if (_currentShow != null) {
       _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: _currentShow!.name,
        mediaFile: mediaPath,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  void importFixture(Fixture fixture) {
    if (_currentShow != null) {
      // GENERATE PIXELS FOR IMPORTED FIXTURE IF EMPTY
      // Discovery service often returns fixtures without full pixel maps
      List<Pixel> pixels = fixture.pixels;
      if (pixels.isEmpty && fixture.width > 0 && fixture.height > 0) {
         pixels = _generatePixels(fixture.width, fixture.height, fixture.id);
      }

      final importedFixture = Fixture(
        id: fixture.id,
        name: fixture.name,
        ip: fixture.ip,
        port: fixture.port,
        protocol: fixture.protocol,
        width: fixture.width,
        height: fixture.height,
        pixels: pixels
      );

      _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: _currentShow!.name,
        mediaFile: _currentShow!.mediaFile,
        fixtures: [importedFixture], // Replace existing fixtures with the imported one
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
    List<Pixel> newPixels = _generatePixels(width, height, fixtureId);

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
        
        // 2. Add Media Files (Background)
        if (_currentShow!.backgroundLayer.type == LayerType.video && 
            _currentShow!.backgroundLayer.path != null && 
            _currentShow!.backgroundLayer.path!.isNotEmpty) {
           
           final mediaPath = _currentShow!.backgroundLayer.path!;
           final mediaFile = File(mediaPath);
           if (await mediaFile.exists()) {
              final ext = p.extension(mediaPath);
              final filename = 'background$ext';
              encoder.addFile(mediaFile, filename);
           }
        }

        // 3. Add Media Files (Foreground)
        if (_currentShow!.foregroundLayer.type == LayerType.video && 
            _currentShow!.foregroundLayer.path != null && 
            _currentShow!.foregroundLayer.path!.isNotEmpty) {
           
           final mediaPath = _currentShow!.foregroundLayer.path!;
           final mediaFile = File(mediaPath);
           if (await mediaFile.exists()) {
              final ext = p.extension(mediaPath);
              final filename = 'foreground$ext';
              encoder.addFile(mediaFile, filename);
           }
        }
        
        // 4. Create Export Manifest (Updates paths to relative)
        final exportManifest = ShowManifest(
          version: _currentShow!.version,
          name: _currentShow!.name,
          mediaFile: _currentShow!.backgroundLayer.path != null ? 'background${p.extension(_currentShow!.backgroundLayer.path!)}' : '',
          fixtures: _currentShow!.fixtures,
          settings: _currentShow!.settings,
          backgroundLayer: _currentShow!.backgroundLayer.copyWith(
             path: _currentShow!.backgroundLayer.path != null ? 'background${p.extension(_currentShow!.backgroundLayer.path!)}' : null
          ),
          foregroundLayer: _currentShow!.foregroundLayer.copyWith(
             path: _currentShow!.foregroundLayer.path != null ? 'foreground${p.extension(_currentShow!.foregroundLayer.path!)}' : null
          ),
        );
        
        final jsonStr = jsonEncode(exportManifest.toJson());
        final manifestFile = File('${tempDir.path}/manifest.json');
        await manifestFile.writeAsString(jsonStr);
        encoder.addFile(manifestFile);
        
        encoder.close();
        return File(bundlePath);
      } catch (e) {
        debugPrint("Bundling error: $e");
        rethrow;
      }
  }
}
