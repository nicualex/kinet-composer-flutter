import 'layer_config.dart';
import 'media_transform.dart';
import 'schedule_config.dart'; // Import ScheduleConfig
export 'media_transform.dart';
export 'schedule_config.dart';

// Mirroring src/shared/types.ts

// ... [Pixel, DmxInfo, Fixture, PlaybackSettings classes remain unchanged] ...

// Mirroring src/shared/types.ts
class ShowManifest {
  final int version;
  final String name;
  final String mediaFile; // Relative path (Legacy/Global reference)
  final List<Fixture> fixtures;
  final PlaybackSettings settings;
  final LayerConfig backgroundLayer;
  final LayerConfig middleLayer;
  final LayerConfig foregroundLayer;
  final double layoutWidth;
  final double layoutHeight;
  final ScheduleConfig schedule; // New Field

  ShowManifest({
    required this.version,
    required this.name,
    required this.mediaFile,
    required this.fixtures,
    required this.settings,
    this.backgroundLayer = const LayerConfig(),
    this.middleLayer = const LayerConfig(),
    this.foregroundLayer = const LayerConfig(),
    this.layoutWidth = 3200.0, // Default Canvas Width
    this.layoutHeight = 1600.0, // Default Canvas Height
    this.schedule = const ScheduleConfig(), // Default Indefinite
  });

  factory ShowManifest.fromJson(Map<String, dynamic> json) {
    return ShowManifest(
      version: json['version'] as int,
      name: json['name'] as String,
      mediaFile: json['mediaFile'] as String? ?? '', // Handle potential null in legacy
      fixtures: (json['fixtures'] as List<dynamic>)
          .map((e) => Fixture.fromJson(e as Map<String, dynamic>))
          .toList(),
      settings: PlaybackSettings.fromJson(json['settings'] as Map<String, dynamic>),
      backgroundLayer: json['backgroundLayer'] != null ? LayerConfig.fromJson(json['backgroundLayer']) : const LayerConfig(),
      middleLayer: json['middleLayer'] != null ? LayerConfig.fromJson(json['middleLayer']) : const LayerConfig(),
      foregroundLayer: json['foregroundLayer'] != null ? LayerConfig.fromJson(json['foregroundLayer']) : const LayerConfig(),
      layoutWidth: (json['layoutWidth'] as num?)?.toDouble() ?? 3200.0,
      layoutHeight: (json['layoutHeight'] as num?)?.toDouble() ?? 1600.0,
      schedule: json['schedule'] != null ? ScheduleConfig.fromJson(json['schedule']) : const ScheduleConfig(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'name': name,
      'mediaFile': mediaFile,
      'fixtures': fixtures.map((e) => e.toJson()).toList(),
      'settings': settings.toJson(),
      'backgroundLayer': backgroundLayer.toJson(),
      'middleLayer': middleLayer.toJson(),
      'foregroundLayer': foregroundLayer.toJson(),
      'layoutWidth': layoutWidth,
      'layoutHeight': layoutHeight,
      'schedule': schedule.toJson(),
    };
  }

  ShowManifest copyWith({
    int? version,
    String? name,
    String? mediaFile,
    List<Fixture>? fixtures,
    PlaybackSettings? settings,
    LayerConfig? backgroundLayer,
    LayerConfig? middleLayer,
    LayerConfig? foregroundLayer,
    double? layoutWidth,
    double? layoutHeight,
    ScheduleConfig? schedule,
  }) {
    return ShowManifest(
      version: version ?? this.version,
      name: name ?? this.name,
      mediaFile: mediaFile ?? this.mediaFile,
      fixtures: fixtures ?? this.fixtures,
      settings: settings ?? this.settings,
      backgroundLayer: backgroundLayer ?? this.backgroundLayer,
      middleLayer: middleLayer ?? this.middleLayer,
      foregroundLayer: foregroundLayer ?? this.foregroundLayer,
      layoutWidth: layoutWidth ?? this.layoutWidth,
      layoutHeight: layoutHeight ?? this.layoutHeight,
      schedule: schedule ?? this.schedule,
    );
  }
}


class Pixel {
  final String id; // Unique ID (e.g., "0:0")
  final int x; // Grid X (0-indexed)
  final int y; // Grid Y(0-indexed)
  final String fixtureId;
  final DmxInfo dmxInfo;

  Pixel({
    required this.id,
    required this.x,
    required this.y,
    required this.fixtureId,
    required this.dmxInfo,
  });

  factory Pixel.fromJson(Map<String, dynamic> json) {
    return Pixel(
      id: json['id'] as String,
      x: json['x'] as int,
      y: json['y'] as int,
      fixtureId: json['fixtureId'] as String,
      dmxInfo: DmxInfo.fromJson(json['dmxInfo'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'fixtureId': fixtureId,
      'dmxInfo': dmxInfo.toJson(),
    };
  }
}

class DmxInfo {
  final int universe; // KiNET universe
  final int channel; // 1-512 (start channel)

  DmxInfo({required this.universe, required this.channel});

  factory DmxInfo.fromJson(Map<String, dynamic> json) {
    return DmxInfo(
      universe: json['universe'] as int,
      channel: json['channel'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'universe': universe,
      'channel': channel,
    };
  }
}

class Fixture {
  final String id;
  final String name;
  final String ip; // Target IP
  final int port; // usually 6038
  final String protocol; // 'KinetV1' | 'KinetV2' | 'KinetV3'
  final int width; // Logical width in pixels
  final int height;
  final List<Pixel> pixels;
  
  // Layout Properties
  final double x;
  final double y;
  final double rotation; // In degrees

  // Patch Properties
  final int universe;
  final int dmxAddress;

  Fixture({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.protocol,
    required this.width,
    required this.height,
    required this.pixels,
    this.x = 0.0,
    this.y = 0.0,
    this.rotation = 0.0,
    this.universe = 0,
    this.dmxAddress = 1,
  });

  factory Fixture.fromJson(Map<String, dynamic> json) {
    return Fixture(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      protocol: json['protocol'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      pixels: (json['pixels'] as List<dynamic>)
          .map((e) => Pixel.fromJson(e as Map<String, dynamic>))
          .toList(),
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      universe: json['universe'] as int? ?? 0,
      dmxAddress: json['dmxAddress'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'protocol': protocol,
      'width': width,
      'height': height,
      'pixels': pixels.map((e) => e.toJson()).toList(),
      'x': x,
      'y': y,
      'rotation': rotation,
      'universe': universe,
      'dmxAddress': dmxAddress,
    };
  }
  Fixture copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? protocol,
    int? width,
    int? height,
    List<Pixel>? pixels,
    double? x,
    double? y,
    double? rotation,
    int? universe,
    int? dmxAddress,
  }) {
    return Fixture(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      width: width ?? this.width,
      height: height ?? this.height,
      pixels: pixels ?? this.pixels,
      x: x ?? this.x,
      y: y ?? this.y,
      rotation: rotation ?? this.rotation,
      universe: universe ?? this.universe,
      dmxAddress: dmxAddress ?? this.dmxAddress,
    );
  }
}

class PlaybackSettings {
  final bool loop; 
  final bool autoPlay;

  PlaybackSettings({required this.loop, required this.autoPlay});

  factory PlaybackSettings.fromJson(Map<String, dynamic> json) {
    return PlaybackSettings(
      loop: json['loop'] as bool,
      autoPlay: json['autoPlay'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'loop': loop,
      'autoPlay': autoPlay,
    };
  }
}



