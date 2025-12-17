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
