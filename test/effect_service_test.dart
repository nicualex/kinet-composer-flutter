import 'package:flutter_test/flutter_test.dart';
import 'package:kinet_composer/services/effect_service.dart';
import 'package:flutter/material.dart';

void main() {
  group('EffectService Tests', () {
    test('getFFmpegFilter generates correct filter for Rainbow Wave', () {
      final params = {'speed': 1.0, 'scale': 1.0};
      final filter = EffectService.getFFmpegFilter(EffectType.rainbow, params);
      
      // Expected frequency string part
      const freq = "((X/W)*2*PI*1.0 + T*1.0)";
      
      const expected = "color=c=black:s=1920x1080,geq="
               "r='127.5+127.5*sin($freq)':"
               "g='127.5+127.5*sin($freq+2.09)':"
               "b='127.5+127.5*sin($freq+4.18)'";

      expect(filter, expected);
    });

    test('getFFmpegFilter generates correct filter for Static Noise', () {
      final params = {'intensity': 0.5};
      final filter = EffectService.getFFmpegFilter(EffectType.noise, params);
      
      // 0.5 intensity * 100 = 50
      const expected = "color=c=black:s=1920x1080,noise=alls=50:allf=t+u";

      expect(filter, expected);
    });

    test('getFFmpegFilter clamps noise intensity correctly', () {
       // Test > 1.0
       var params = {'intensity': 1.5};
       var filter = EffectService.getFFmpegFilter(EffectType.noise, params);
       expect(filter, contains("alls=100"));

       // Test < 0.0
       params = {'intensity': -0.5};
       filter = EffectService.getFFmpegFilter(EffectType.noise, params);
       expect(filter, contains("alls=0"));
    });
  });
}
