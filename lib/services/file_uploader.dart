import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;

class FileUploader {
  Future<bool> uploadShow(File file, String ipAddress, {String? showName}) async {
    final uri = Uri.parse('http://$ipAddress:8080/upload');
    final name = showName ?? path.basenameWithoutExtension(file.path);
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '_');

    final request = http.MultipartRequest('POST', uri);
    
    // Add custom header used by Android app
    request.headers['X-Show-Name'] = safeName;

    // Add file
    request.files.add(
      await http.MultipartFile.fromPath(
        'showFile',
        file.path,
        filename: '$safeName.kshow',
        contentType: MediaType('application', 'octet-stream'),
      ),
    );

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Upload failed: ${response.statusCode} ${response.reasonPhrase}');
      }
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }
}
