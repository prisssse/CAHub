import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/session_settings.dart';

class ApiService {
  final String baseUrl;

  ApiService({this.baseUrl = 'http://127.0.0.1:8207'});

  Future<List<Map<String, dynamic>>> getSessions() async {
    final response = await http.get(Uri.parse('$baseUrl/sessions'));

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load sessions: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final response = await http.get(Uri.parse('$baseUrl/sessions/$sessionId'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load session: ${response.statusCode}');
    }
  }

  Stream<Map<String, dynamic>> chat({
    String? sessionId,
    required String message,
    String? cwd,
    SessionSettings? settings,
  }) async* {
    final body = <String, dynamic>{};

    if (sessionId != null) {
      body['session_id'] = sessionId;
    }
    body['message'] = message;

    if (cwd != null) {
      body['cwd'] = cwd;
    }

    // Add settings if provided
    if (settings != null) {
      body['permission_mode'] = settings.permissionMode.value;
      if (settings.systemPrompt != null) {
        body['system_prompt'] = settings.systemPrompt;
      }
      body['setting_sources'] = settings.settingSources;
    }

    final request = http.Request('POST', Uri.parse('$baseUrl/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.body = json.encode(body);

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != 200) {
      throw Exception('Chat request failed: ${streamedResponse.statusCode}');
    }

    String? currentEvent;
    final buffer = StringBuffer();

    await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final content = buffer.toString();
      final lines = content.split('\n');

      // Keep the last incomplete line in buffer
      buffer.clear();
      if (!content.endsWith('\n')) {
        buffer.write(lines.last);
        lines.removeLast();
      }

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) {
          // Empty line marks end of event
          currentEvent = null;
          continue;
        }

        if (line.startsWith('event: ')) {
          currentEvent = line.substring(7);
        } else if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data.trim().isNotEmpty && currentEvent != null) {
            try {
              final parsed = json.decode(data);
              // Yield event with type
              yield {
                'event_type': currentEvent,
                ...parsed,
              };
            } catch (e) {
              // Skip invalid JSON
            }
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>> loadSessions({String? claudeDir}) async {
    final body = <String, dynamic>{};
    if (claudeDir != null) {
      body['claude_dir'] = claudeDir;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/sessions/load'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load sessions: ${response.statusCode}');
    }
  }
}
