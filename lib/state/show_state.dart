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
import '../models/layer_config.dart';
import '../models/media_transform.dart';
import '../services/effect_service.dart';
import 'package:flutter/material.dart'; // For TimeOfDay
import 'dart:async';
import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';
import '../models/schedule_config.dart';

// Export LayerTarget for convenience
export '../models/layer_config.dart' show LayerTarget;

class ShowState extends ChangeNotifier {
  ShowManifest? _currentShow;
  File? _currentFile;
  bool _isModified = false;
  
  // For Rendering
  double? _overrideTime;
  double? get overrideTime => _overrideTime;

  // View State (Global)
  bool _isGridLocked = false;
  bool get isGridLocked => _isGridLocked;
  
  // Transport State (Global)
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  ShowState() {
     _initNewShow();
     // Check schedule every minute
     _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        _checkSchedule();
     });
  }

  Timer? _scheduleTimer;

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    super.dispose();
  }

  void setGridLock(bool locked) {
     _isGridLocked = locked;
     notifyListeners();
  }

  void setPlaying(bool playing) {
     if (_isPlaying == playing) return;
     _isPlaying = playing;
     notifyListeners();
  }

  // Pixel Mapping System
  bool _isPixelMappingEnabled = false;
  bool get isPixelMappingEnabled => _isPixelMappingEnabled;

  void setPixelMapping(bool enabled) {
    if (_isPixelMappingEnabled == enabled) return;
    _isPixelMappingEnabled = enabled;
    notifyListeners();
  }

  void setOverrideTime(double? t) {
     _overrideTime = t;
     notifyListeners();
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
    _currentShow = ShowManifest(
      version: 1,
      name: 'New Show',
      mediaFile: '',
      fixtures: [],
      settings: PlaybackSettings(loop: true, autoPlay: true),
      backgroundLayer: const LayerConfig(),
      middleLayer: const LayerConfig(),
      foregroundLayer: const LayerConfig(),
    );
    _currentFile = null;
    _isModified = true; 
  }

  ShowManifest? get currentShow => _currentShow;
  File? get currentFile => _currentFile;
  bool get isModified => _isModified;
  String? get fileName => _currentFile?.path.split(Platform.pathSeparator).last;
  
  // Helpers for RenderService/Dialog
  Fixture get matrixConfig => _currentShow?.fixtures.isNotEmpty == true ? _currentShow!.fixtures.first : Fixture(id: 'dummy', name: 'dummy', ip: '', port: 0, protocol: '', width: 100, height: 100, pixels: []); // Safe fallback
  String get currentShowPath => _currentFile?.path ?? "New Show";
  List<LayerConfig> get layers => _currentShow != null ? [_currentShow!.backgroundLayer, _currentShow!.middleLayer, _currentShow!.foregroundLayer] : [];

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
        // 1. CLEAR EXISTING STATE
        // Reset everything to defaults first
        _initNewShow();
        
        // 2. LOAD NEW STATE
        final bytes = await file.readAsBytes();
        String content;
        // Check BOM for UTF-16LE (FF FE)
        if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
           final codes = <int>[];
           for (int i = 2; i < bytes.length - 1; i += 2) {
              codes.add(bytes[i] | (bytes[i + 1] << 8));
           }
           content = String.fromCharCodes(codes);
        } else {
           try {
              content = utf8.decode(bytes);
           } catch (_) {
              content = String.fromCharCodes(bytes);
           }
        }
        final json = jsonDecode(content);
        final loadedShow = ShowManifest.fromJson(json);

        // 3. INITIALIZE MATRIX FROM FILE
        // Check if loaded show has fixtures with missing pixels (common in compact saves) and regen them
        List<Fixture> fixtures = loadedShow.fixtures;
        for (int i = 0; i < fixtures.length; i++) {
           final f = fixtures[i];
           if (f.pixels.isEmpty && f.width > 0 && f.height > 0) {
              final newPixels = _generatePixels(f.width, f.height, f.id);
              fixtures[i] = f.copyWith(pixels: newPixels);
           }
        }
        
        // Derive name from filename to ensure sync
        String filename = file.path.split(Platform.pathSeparator).last;
        if (filename.contains('.')) {
          filename = filename.substring(0, filename.lastIndexOf('.'));
        }

        _currentShow = ShowManifest(
           version: loadedShow.version,
           name: filename,
           mediaFile: loadedShow.mediaFile,
           fixtures: fixtures,
           settings: loadedShow.settings,
           backgroundLayer: loadedShow.backgroundLayer,
           middleLayer: loadedShow.middleLayer,
           foregroundLayer: loadedShow.foregroundLayer,
           layoutWidth: loadedShow.layoutWidth,
           layoutHeight: loadedShow.layoutHeight,
        );
        
        _currentFile = file;
        _isModified = false;
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading show: $e');
      }
    }
  }

  void loadManifest(ShowManifest show) {
    _currentShow = show;
    _currentFile = null; // Loaded from raw manifest, file unknown unless set via saving
    _isModified = false;
    notifyListeners();
  }

  Future<void> saveShow({bool forceDialog = false}) async {
    if (_currentShow == null) return;

    if (_currentFile == null || forceDialog) {
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
     
     // Update Show Name from Filename
     String filename = path.split(Platform.pathSeparator).last;
     if (filename.contains('.')) {
       filename = filename.substring(0, filename.lastIndexOf('.'));
     }

     _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: filename,
        mediaFile: _currentShow!.mediaFile,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
        backgroundLayer: _currentShow!.backgroundLayer,
        middleLayer: _currentShow!.middleLayer,
        foregroundLayer: _currentShow!.foregroundLayer,
        layoutWidth: _currentShow!.layoutWidth,
        layoutHeight: _currentShow!.layoutHeight,
     );

     final file = File(path);
     final json = _currentShow!.toJson();
     final content = const JsonEncoder.withIndent('  ').convert(json);
     await file.writeAsString(content);
     
     _currentFile = file;
     _isModified = false;
     notifyListeners();
  }

  // Legacy support or quick access for Background Video
  void updateMedia(String path) {
    updateLayer(target: LayerTarget.background, type: LayerType.video, path: path);
  }

  void updateLayer({
    // Replacing isForeground with target
    LayerTarget target = LayerTarget.background,
    // Helper for boolean backward compatibility if needed, but safer to enforce target
    bool? isForeground, 
    
    LayerType? type,
    String? path,
    EffectType? effect,
    Map<String, dynamic>? params,
    double? opacity,

    bool? isVisible,
    MediaTransform? transform,
    bool? lockAspectRatio,
  }) {
    if (_currentShow == null) return;
    
    // Backward compatibility wrapper
    final effectiveTarget = isForeground != null 
       ? (isForeground ? LayerTarget.foreground : LayerTarget.background)
       : target;

    LayerConfig currentLayer;
    switch (effectiveTarget) {
       case LayerTarget.background: currentLayer = _currentShow!.backgroundLayer; break;
       case LayerTarget.middle: currentLayer = _currentShow!.middleLayer; break;
       case LayerTarget.foreground: currentLayer = _currentShow!.foregroundLayer; break;
    }

    final newLayer = currentLayer.copyWith(
      type: type,
      path: path,
      effect: effect,
      effectParams: params,
      opacity: opacity,
      isVisible: isVisible,
      transform: transform,
      lockAspectRatio: lockAspectRatio,
    );

    // Sync legacy mediaFile if updating background video
    String newMediaFile = _currentShow!.mediaFile;
    if (effectiveTarget == LayerTarget.background && path != null) {
      newMediaFile = path;
    }

    _currentShow = ShowManifest(
      version: _currentShow!.version,
      name: _currentShow!.name,
      mediaFile: newMediaFile,
      fixtures: _currentShow!.fixtures,
      settings: _currentShow!.settings,
      backgroundLayer: effectiveTarget == LayerTarget.background ? newLayer : _currentShow!.backgroundLayer,
      middleLayer: effectiveTarget == LayerTarget.middle ? newLayer : _currentShow!.middleLayer,
      foregroundLayer: effectiveTarget == LayerTarget.foreground ? newLayer : _currentShow!.foregroundLayer,
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
        middleLayer: _currentShow!.middleLayer,
        foregroundLayer: _currentShow!.foregroundLayer,
      );
      _isModified = true;
      notifyListeners();
    }
  }

  // updateTransform is removed. Use updateLayer(transform: ...) instead.

  void setMediaAndTransform(String mediaPath, MediaTransform? transform) {
    if (_currentShow != null) {
       _currentShow = ShowManifest(
        version: _currentShow!.version,
        name: _currentShow!.name,
        mediaFile: mediaPath,
        fixtures: _currentShow!.fixtures,
        settings: _currentShow!.settings,
        backgroundLayer: _currentShow!.backgroundLayer,
        middleLayer: _currentShow!.middleLayer,
        foregroundLayer: _currentShow!.foregroundLayer,
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
        backgroundLayer: _currentShow!.backgroundLayer,
        middleLayer: _currentShow!.middleLayer,
        foregroundLayer: _currentShow!.foregroundLayer,
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

    final newFixture = oldFixture.copyWith(
      width: width,
      height: height,
      pixels: newPixels
    );

    List<Fixture> newFixtures = List.from(_currentShow!.fixtures);
    newFixtures[index] = newFixture;

    _currentShow = _currentShow!.copyWith(fixtures: newFixtures);
    _isModified = true;
    notifyListeners();
  }

  void updateFixturePosition(String fixtureId, double x, double y, double rotation) {
    if (_currentShow == null) return;

    final index = _currentShow!.fixtures.indexWhere((f) => f.id == fixtureId);
    if (index == -1) return;

    final oldFixture = _currentShow!.fixtures[index];
    final newFixture = oldFixture.copyWith(x: x, y: y, rotation: rotation);

    List<Fixture> newFixtures = List.from(_currentShow!.fixtures);
    newFixtures[index] = newFixture;

    _currentShow = _currentShow!.copyWith(fixtures: newFixtures);
    _isModified = true;
    notifyListeners();
  }

  void updateFixtures(List<Fixture> fixtures) {
     if (_currentShow == null) return;
     _currentShow = _currentShow!.copyWith(fixtures: fixtures);
     _isModified = true;
     notifyListeners();
  }

  void updateGridBounds(double w, double h) {
     if (_currentShow == null) return;
     if (_currentShow!.layoutWidth == w && _currentShow!.layoutHeight == h) return;
     
     _currentShow = _currentShow!.copyWith(layoutWidth: w, layoutHeight: h);
     _isModified = true;
     notifyListeners();
  }

  void updateFixture(Fixture fixture) {
    if (_currentShow == null) return;
    final index = _currentShow!.fixtures.indexWhere((f) => f.id == fixture.id);
    if (index == -1) return;

    List<Fixture> newFixtures = List.from(_currentShow!.fixtures);
    newFixtures[index] = fixture;

    _currentShow = _currentShow!.copyWith(fixtures: newFixtures);
    _isModified = true;
    notifyListeners();
  }
  
  void addFixture(Fixture fixture) {
     if (_currentShow == null) return;
     List<Fixture> newFixtures = List.from(_currentShow!.fixtures);
     newFixtures.add(fixture);
      _currentShow = _currentShow!.copyWith(fixtures: newFixtures);
      _isModified = true;
      notifyListeners();
  }
  
  void removeFixture(String id) {
     if (_currentShow == null) return;
     List<Fixture> newFixtures = List.from(_currentShow!.fixtures);
     newFixtures.removeWhere((f) => f.id == id);
      _currentShow = _currentShow!.copyWith(fixtures: newFixtures);
      _isModified = true;
      notifyListeners();
  }

  // --- SCHEDULER LOGIC ---
  void updateSchedule(ScheduleConfig config) {
    if (_currentShow == null) return;
    _currentShow = _currentShow!.copyWith(schedule: config);
    _isModified = true;
    notifyListeners();
    
    // Force immediate check
    _checkSchedule();
  }

  void _checkSchedule() {
     if (_currentShow == null) return;
     final schedule = _currentShow!.schedule;

     // 1. If Indefinite, do nothing (User controls play/pause)
     if (schedule.type == ScheduleType.indefinite) return;

     // 2. Scheduled Mode
     final now = DateTime.now();
     
     // A. Check Day of Week
     // Monday = 1, Sunday = 7. List is 0-indexed (Mon-Sun)
     final dayIndex = now.weekday - 1; // 0 = Mon, 6 = Sun
     if (dayIndex < 0 || dayIndex >= schedule.enabledDays.length || !schedule.enabledDays[dayIndex]) {
        // Today is disabled. Stop if playing.
        if (_isPlaying) {
           setPlaying(false);
           debugPrint("Scheduler: Stopping (Day Disabled)");
        }
        return;
     }

     // B. Calculate Times
     // Default Location: New York (Approx) if not set. 
     // Ideally we'd ask user or use IP geolocation, but for now hardcoded fallback is safer than crash.
     final double lat = schedule.latitude ?? 40.7128;
     final double lng = schedule.longitude ?? -74.0060;

     DateTime? getSunrise(DateTime date, double lat, double lng) {
        final result = getSunriseSunset(lat, lng, const Duration(hours: 0), date);
        return result.sunrise;
     }

     DateTime? getSunset(DateTime date, double lat, double lng) {
        final result = getSunriseSunset(lat, lng, const Duration(hours: 0), date);
        return result.sunset;
     }

     DateTime getTriggerTime(ScheduleTrigger trigger, TimeOfDay? specific, int offset) {
        DateTime base;
        if (trigger == ScheduleTrigger.specific) {
           base = DateTime(now.year, now.month, now.day, specific!.hour, specific.minute);
        } else if (trigger == ScheduleTrigger.sunrise) {
           base = getSunrise(now, lat, lng) ?? DateTime(now.year, now.month, now.day, 6, 0);
        } else { // Sunset
           base = getSunset(now, lat, lng) ?? DateTime(now.year, now.month, now.day, 18, 0);
        }
        return base.add(Duration(minutes: offset));
     }

     final startTime = getTriggerTime(schedule.startTrigger, schedule.startTime, schedule.startOffsetMinutes);
     final endTime = getTriggerTime(schedule.endTrigger, schedule.endTime, schedule.endOffsetMinutes);

     // Handle overnight logic (Start 10PM, End 5AM)
     bool isOvernight = endTime.isBefore(startTime);
     if (isOvernight) {
        // If it's overnight, we are "active" if:
        // NOW > Start (Before midnight) OR NOW < End (After midnight)
        // Adjust endTime to tomorrow for comparison if currently PM? 
        // Or adjust startTime to yesterday if currently AM?
        
        // Simpler: 
        // Is Active = (Now >= Start) || (Now < End)
        // Check strict inequality?
        // Using "isAfter" and "isBefore"
        bool afterStart = now.isAfter(startTime) || now.isAtSameMomentAs(startTime);
        bool beforeEnd = now.isBefore(endTime); // This endTime is "Today's" end time instance (e.g. 5am today)
        
        // If Schedule is 10PM -> 5AM. 
        // If Now is 11PM. Start(Today 10PM). End(Today 5AM).
        // 11PM > 10PM (True). 11PM < 5AM (False). OR => True. Correct.
        
        // If Now is 2AM. Start(Today 10PM). End(Today 5AM).
        // 2AM > 10PM (False). 2AM < 5AM (True). OR => True. Correct.
        
        // If Now is 6AM. Start(Today 10PM). End(Today 5AM).
        // 6AM > 10PM (False). 6AM < 5AM (False). OR => False. Correct. (Stopped)
        
        if (afterStart || beforeEnd) {
           if (!_isPlaying) {
              setPlaying(true);
               debugPrint("Scheduler: Starting (Overnight Schedule Active)");
           }
        } else {
           if (_isPlaying) {
              setPlaying(false);
              debugPrint("Scheduler: Stopping (Overnight Schedule Inactive)");
           }
        }

     } else {
        // Standard Day Schedule (e.g. 9AM -> 5PM)
        // Start < End
        // Active if Now > Start AND Now < End
        bool afterStart = now.isAfter(startTime) || now.isAtSameMomentAs(startTime);
        bool beforeEnd = now.isBefore(endTime);
        
        if (afterStart && beforeEnd) {
           if (!_isPlaying) {
              setPlaying(true);
              debugPrint("Scheduler: Starting (Standard Schedule Active)");
           }
        } else {
           if (_isPlaying) {
              setPlaying(false);
              debugPrint("Scheduler: Stopping (Standard Schedule Inactive)");
           }
        }
     }
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

        // 3. Add Media Files (Middle)
        if (_currentShow!.middleLayer.type == LayerType.video && 
            _currentShow!.middleLayer.path != null && 
            _currentShow!.middleLayer.path!.isNotEmpty) {
           
           final file = File(_currentShow!.middleLayer.path!);
           if (await file.exists()) {
             encoder.addFile(file, 'middle${p.extension(_currentShow!.middleLayer.path!)}');
           }
        }

        // 4. Add Media Files (Foreground)
        if (_currentShow!.foregroundLayer.type == LayerType.video && 
            _currentShow!.foregroundLayer.path != null && 
            _currentShow!.foregroundLayer.path!.isNotEmpty) {
           
           final file = File(_currentShow!.foregroundLayer.path!);
           if (await file.exists()) {
             encoder.addFile(file, 'foreground${p.extension(_currentShow!.foregroundLayer.path!)}');
           }
        }
        
        // 5. Create Modified Manifest
        final exportManifest = ShowManifest(
          version: _currentShow!.version,
          name: _currentShow!.name,
          mediaFile: _currentShow!.backgroundLayer.path != null ? 'background${p.extension(_currentShow!.backgroundLayer.path!)}' : '',
          fixtures: _currentShow!.fixtures,
          settings: _currentShow!.settings,
          backgroundLayer: _currentShow!.backgroundLayer.copyWith(
             path: _currentShow!.backgroundLayer.path != null ? 'background${p.extension(_currentShow!.backgroundLayer.path!)}' : null
          ),
          middleLayer: _currentShow!.middleLayer.copyWith(
             path: _currentShow!.middleLayer.path != null ? 'middle${p.extension(_currentShow!.middleLayer.path!)}' : null
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
