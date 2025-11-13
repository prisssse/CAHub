import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../services/api_service.dart';
import 'session_repository.dart';

class ApiSessionRepository implements SessionRepository {
  final ApiService _apiService;

  ApiSessionRepository(this._apiService);

  @override
  Future<Session> getSession(String id) async {
    final data = await _apiService.getSession(id);
    return Session(
      id: data['session_id'],
      projectId: data['cwd'], // Use cwd as projectId
      title: data['title'],
      name: data['title'],
      cwd: data['cwd'],
      createdAt: DateTime.parse(data['created_at']),
      updatedAt: DateTime.parse(data['updated_at']),
      messageCount: (data['messages'] as List).length,
    );
  }

  @override
  Future<List<Message>> getSessionMessages(String sessionId) async {
    final data = await _apiService.getSession(sessionId);
    final messages = data['messages'] as List;

    final result = <Message>[];

    for (var m in messages) {
      // Skip non-message records (file-history-snapshot, summary, etc.)
      if (!m.containsKey('message')) continue;

      final message = m['message'];
      if (message == null || !message.containsKey('role')) continue;

      final role = message['role'];
      if (role != 'user' && role != 'assistant') continue;

      // Get timestamp
      final timestampStr = m['timestamp'];
      if (timestampStr == null) continue;
      final timestamp = DateTime.parse(timestampStr);

      // Extract text content from content field
      final content = _extractTextContent(message['content']);
      if (content.isEmpty) continue;

      result.add(Message(
        id: '${sessionId}_${timestamp.millisecondsSinceEpoch}',
        role: role == 'user' ? MessageRole.user : MessageRole.assistant,
        content: content,
        timestamp: timestamp,
      ));
    }

    return result;
  }

  @override
  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  }) async {
    final buffer = StringBuffer();
    String? finalResult;

    await for (var event in _apiService.chat(
      sessionId: sessionId,
      message: content,
      settings: settings,
    )) {
      final eventType = event['event_type'];

      if (eventType == 'token') {
        // Token event: {"session_id": "...", "text": "..."}
        final text = event['text'];
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
        }
      } else if (eventType == 'message') {
        // Message event: {"session_id": "...", "payload": {...}}
        final payload = event['payload'];
        if (payload != null) {
          final payloadType = payload['type'];

          if (payloadType == 'result') {
            // ResultMessage: extract result field
            finalResult = payload['result'] as String?;
          } else if (payloadType == 'assistant') {
            // AssistantMessage: extract content blocks
            final messageContent = payload['content'];
            if (messageContent != null) {
              final extracted = _extractTextContent(messageContent);
              if (extracted.isNotEmpty) {
                buffer.write(extracted);
              }
            }
          }
        }
      } else if (eventType == 'done') {
        // Done event: return accumulated message
        if (finalResult != null && finalResult.isNotEmpty) {
          return Message.assistant(finalResult);
        } else if (buffer.isNotEmpty) {
          return Message.assistant(buffer.toString());
        }
      } else if (eventType == 'error') {
        throw Exception('Chat error: ${event['message']}');
      }
    }

    // Fallback if no content received
    if (finalResult != null && finalResult.isNotEmpty) {
      return Message.assistant(finalResult);
    } else if (buffer.isNotEmpty) {
      return Message.assistant(buffer.toString());
    }
    return Message.assistant('');
  }

  @override
  Future<void> clearSessionMessages(String sessionId) async {
    // API doesn't support clearing messages, this is a no-op
    // In real implementation, this might call a DELETE endpoint
  }

  String _extractTextContent(dynamic content) {
    if (content is String) {
      return content;
    }

    if (content is List) {
      final buffer = StringBuffer();
      for (var item in content) {
        if (item is Map) {
          if (item['type'] == 'text') {
            buffer.write(item['text']);
          } else if (item['type'] == 'tool_use') {
            // Format tool use for display
            buffer.write('\n[Tool: ${item['name']}]\n');
          } else if (item['type'] == 'tool_result') {
            // Format tool result for display
            buffer.write('\n[Result]\n');
          }
        }
      }
      return buffer.toString();
    }

    return '';
  }
}
