import 'dart:convert';
import 'dart:io';

void main() {
  final fixtures = <Map<String, dynamic>>[];
  
  // 20 Controllers 10x10
  // Grid Layout: 5 columns per row, spacing 200px
  for (int i = 0; i < 20; i++) {
    int row = i ~/ 5;
    int col = i % 5;
    
    fixtures.add({
      'id': 'Ctrl-10x10-${i+1}',
      'name': '10x10 Panel ${i+1}',
      'ip': '192.168.1.${100+i}',
      'port': 6038,
      'protocol': 'KiNET v2',
      'width': 10,
      'height': 10,
      'pixels': [], // Logic will hydrate this
      'x': col * 200.0 + 50,
      'y': row * 200.0 + 50,
      'rotation': 0.0
    });
  }

  // 20 Controllers 5x5
  // Placed below the 10x10s
  double startY = 4 * 200.0 + 250.0;
  for (int i = 0; i < 20; i++) {
    int row = i ~/ 10;
    int col = i % 10;

    fixtures.add({
      'id': 'Ctrl-5x5-${i+1}',
      'name': '5x5 Tile ${i+1}',
      'ip': '192.168.2.${100+i}',
      'port': 6038,
      'protocol': 'KiNET v2',
      'width': 5,
      'height': 5,
      'pixels': [], // Logic will hydrate this
      'x': col * 100.0 + 50,
      'y': startY + (row * 100.0),
      'rotation': 0.0
    });
  }

  final manifest = {
    'version': 1,
    'name': 'Simulation Show',
    'mediaFile': '',
    'fixtures': fixtures,
    'settings': {'loop': true, 'autoPlay': true},
    'backgroundLayer': {'type': 'none', 'opacity': 1.0, 'isVisible': true},
    'middleLayer': {'type': 'none', 'opacity': 1.0, 'isVisible': true},
    'foregroundLayer': {'type': 'none', 'opacity': 1.0, 'isVisible': true},
    'layoutWidth': 3200.0,
    'layoutHeight': 1600.0
  };

  print(jsonEncode(manifest));
}
