
// Mirroring src/shared/types.ts

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

  Fixture({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.protocol,
    required this.width,
    required this.height,
    required this.pixels,
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
    };
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

class CropInfo {
  final double x;
  final double y;
  final double width;
  final double height;

  CropInfo({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory CropInfo.fromJson(Map<String, dynamic> json) {
    return CropInfo(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}

class MediaTransform {
  final double scaleX;
  final double scaleY;
  final double translateX;
  final double translateY;
  final double rotation;
  final CropInfo? crop;

  MediaTransform({
    required this.scaleX,
    required this.scaleY,
    required this.translateX,
    required this.translateY,
    required this.rotation,
    this.crop,
  });

  factory MediaTransform.fromJson(Map<String, dynamic> json) {
    return MediaTransform(
      scaleX: (json['scaleX'] as num).toDouble(),
      scaleY: (json['scaleY'] as num).toDouble(),
      translateX: (json['translateX'] as num).toDouble(),
      translateY: (json['translateY'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      crop: json['crop'] != null
          ? CropInfo.fromJson(json['crop'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scaleX': scaleX,
      'scaleY': scaleY,
      'translateX': translateX,
      'translateY': translateY,
      'rotation': rotation,
      'crop': crop?.toJson(),
    };
  }
}

class ShowManifest {
  final int version;
  final String name;
  final String mediaFile; // Relative path
  final MediaTransform? mediaTransform;
  final List<Fixture> fixtures;
  final PlaybackSettings settings;

  ShowManifest({
    required this.version,
    required this.name,
    required this.mediaFile,
    this.mediaTransform,
    required this.fixtures,
    required this.settings,
  });

  factory ShowManifest.fromJson(Map<String, dynamic> json) {
    return ShowManifest(
      version: json['version'] as int,
      name: json['name'] as String,
      mediaFile: json['mediaFile'] as String,
      mediaTransform: json['mediaTransform'] != null
          ? MediaTransform.fromJson(
              json['mediaTransform'] as Map<String, dynamic>)
          : null,
      fixtures: (json['fixtures'] as List<dynamic>)
          .map((e) => Fixture.fromJson(e as Map<String, dynamic>))
          .toList(),
      settings: PlaybackSettings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'name': name,
      'mediaFile': mediaFile,
      'mediaTransform': mediaTransform?.toJson(),
      'fixtures': fixtures.map((e) => e.toJson()).toList(),
      'settings': settings.toJson(),
    };
  }
}
