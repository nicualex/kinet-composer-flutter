import 'package:flutter/material.dart';

enum ScheduleType {
  indefinite,
  scheduled
}

enum ScheduleTrigger {
  specific,
  sunrise,
  sunset
}

class ScheduleConfig {
  final ScheduleType type;
  
  // Start
  final ScheduleTrigger startTrigger;
  final TimeOfDay startTime;
  final int startOffsetMinutes; // e.g. "30 mins before sunset"
  
  // End
  final ScheduleTrigger endTrigger;
  final TimeOfDay endTime;
  final int endOffsetMinutes;

  // Days (Index 0 = Monday, 6 = Sunday)
  final List<bool> enabledDays;
  
  // Location (Optional, for precise calc if not using system)
  final double? latitude;
  final double? longitude;

  const ScheduleConfig({
    this.type = ScheduleType.indefinite,
    this.startTrigger = ScheduleTrigger.specific,
    this.startTime = const TimeOfDay(hour: 18, minute: 0),
    this.startOffsetMinutes = 0,
    this.endTrigger = ScheduleTrigger.specific,
    this.endTime = const TimeOfDay(hour: 6, minute: 0),
    this.endOffsetMinutes = 0,
    this.enabledDays = const [true, true, true, true, true, true, true],
    this.latitude,
    this.longitude,
  });

  ScheduleConfig copyWith({
    ScheduleType? type,
    ScheduleTrigger? startTrigger,
    TimeOfDay? startTime,
    int? startOffsetMinutes,
    ScheduleTrigger? endTrigger,
    TimeOfDay? endTime,
    int? endOffsetMinutes,
    List<bool>? enabledDays,
    double? latitude,
    double? longitude,
  }) {
    return ScheduleConfig(
      type: type ?? this.type,
      startTrigger: startTrigger ?? this.startTrigger,
      startTime: startTime ?? this.startTime,
      startOffsetMinutes: startOffsetMinutes ?? this.startOffsetMinutes,
      endTrigger: endTrigger ?? this.endTrigger,
      endTime: endTime ?? this.endTime,
      endOffsetMinutes: endOffsetMinutes ?? this.endOffsetMinutes,
      enabledDays: enabledDays ?? this.enabledDays,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'startTrigger': startTrigger.index,
      'startTime': '${startTime.hour}:${startTime.minute}',
      'startOffsetMinutes': startOffsetMinutes,
      'endTrigger': endTrigger.index,
      'endTime': '${endTime.hour}:${endTime.minute}',
      'endOffsetMinutes': endOffsetMinutes,
      'enabledDays': enabledDays,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    TimeOfDay parseTime(String s) {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    return ScheduleConfig(
      type: ScheduleType.values[json['type'] ?? 0],
      startTrigger: ScheduleTrigger.values[json['startTrigger'] ?? 0],
      startTime: parseTime(json['startTime'] ?? "18:00"),
      startOffsetMinutes: json['startOffsetMinutes'] ?? 0,
      endTrigger: ScheduleTrigger.values[json['endTrigger'] ?? 0],
      endTime: parseTime(json['endTime'] ?? "06:00"),
      endOffsetMinutes: json['endOffsetMinutes'] ?? 0,
      enabledDays: (json['enabledDays'] as List?)?.cast<bool>() ?? const [true, true, true, true, true, true, true],
      latitude: json['latitude'],
      longitude: json['longitude'],
    );
  }
}
