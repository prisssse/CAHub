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
      // Skip queue-operation and other non-message types
      final messageType = m['type'];
      if (messageType == null || messageType == 'queue-operation') continue;

      // Only process user and assistant types
      if (messageType != 'user' && messageType != 'assistant') continue;

      // Get the nested message object
      final message = m['message'];
      if (message == null) continue;

      // Verify role matches type
      final roleStr = message['role']?.toString();
      if (roleStr == null || roleStr != messageType) continue;

      // Get timestamp from top level
      final timestampStr = m['timestamp'];
      if (timestampStr == null) continue;

      DateTime timestamp;
      try {
        timestamp = DateTime.parse(timestampStr);
      } catch (e) {
        continue; // Skip invalid timestamps
      }

      // Parse content blocks
      final contentBlocks = _parseContentBlocks(message['content']);
      if (contentBlocks.isEmpty) continue;

      // Determine role
      // Tool results are marked as 'user' by backend, but should be displayed as assistant messages
      MessageRole messageRole;
      if (roleStr == 'user') {
        final hasOnlyToolResults = contentBlocks.every((block) => block.type == ContentBlockType.toolResult);
        messageRole = hasOnlyToolResults ? MessageRole.assistant : MessageRole.user;
      } else {
        messageRole = MessageRole.assistant;
      }

      // Use uuid as message ID if available
      final messageId = m['uuid']?.toString() ?? '${sessionId}_${timestamp.millisecondsSinceEpoch}';

      result.add(Message.fromBlocks(
        id: messageId,
        role: messageRole,
        blocks: contentBlocks,
        timestamp: timestamp,
      ));
    }

    return result;
  }

  List<ContentBlock> _parseContentBlocks(dynamic content) {
    final blocks = <ContentBlock>[];

    if (content == null) {
      return blocks;
    }

    if (content is String) {
      // 字符串内容：直接作为 text block
      if (content.isNotEmpty) {
        blocks.add(ContentBlock(type: ContentBlockType.text, text: content));
      }
    } else if (content is List) {
      for (var item in content) {
        if (item is Map<String, dynamic>) {
          final itemType = item['type'];

          // 只处理已知的内容块类型，忽略其他类型
          if (itemType == 'text' && item['text'] != null) {
            final text = item['text'].toString();
            if (text.isNotEmpty) {
              blocks.add(ContentBlock(
                type: ContentBlockType.text,
                text: text,
              ));
            }
          } else if (itemType == 'thinking' && item['thinking'] != null) {
            blocks.add(ContentBlock(
              type: ContentBlockType.thinking,
              thinking: item['thinking'].toString(),
              signature: item['signature']?.toString(),
            ));
          } else if (itemType == 'tool_use') {
            blocks.add(ContentBlock(
              type: ContentBlockType.toolUse,
              id: item['id']?.toString(),
              name: item['name']?.toString(),
              input: item['input'] as Map<String, dynamic>?,
            ));
          } else if (itemType == 'tool_result') {
            blocks.add(ContentBlock(
              type: ContentBlockType.toolResult,
              toolUseId: item['tool_use_id']?.toString(),
              content: item['content'],
              isError: item['is_error'] as bool?,
            ));
          }
          // 如果是未知类型，忽略它（不再添加 fallback）
        } else if (item is String && item.isNotEmpty) {
          // 列表中的字符串项
          blocks.add(ContentBlock(type: ContentBlockType.text, text: item));
        }
      }
    }
    // 其他类型的 content 直接忽略（不再转换为字符串）

    return blocks;
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

  @override
  Stream<MessageStreamEvent> sendMessageStream({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  }) async* {
    final messageId = '${sessionId}_${DateTime.now().millisecondsSinceEpoch}';
    final contentBlocksBuilder = <int, StringBuffer>{}; // index -> accumulated text
    List<ContentBlock> latestContentBlocks = [];

    try {
      await for (var event in _apiService.chat(
        sessionId: sessionId,
        message: content,
        settings: settings,
      )) {
        final eventType = event['event_type'];

        if (eventType == 'stream_event') {
          // Handle real streaming events
          final streamEvent = event['event'];
          if (streamEvent == null) continue;

          final streamEventType = streamEvent['type'];

          if (streamEventType == 'content_block_start') {
            // New content block started
            final index = streamEvent['index'] as int?;
            if (index != null) {
              contentBlocksBuilder[index] = StringBuffer();
            }
          } else if (streamEventType == 'content_block_delta') {
            // Incremental content update
            final index = streamEvent['index'] as int? ?? 0;
            final delta = streamEvent['delta'];

            if (delta != null && delta['type'] == 'text_delta') {
              final text = delta['text'] as String?;
              if (text != null) {
                // Accumulate text for this block
                if (!contentBlocksBuilder.containsKey(index)) {
                  contentBlocksBuilder[index] = StringBuffer();
                }
                contentBlocksBuilder[index]!.write(text);

                // Build current content blocks from accumulated text
                latestContentBlocks = [];
                for (var i = 0; i <= contentBlocksBuilder.keys.reduce((a, b) => a > b ? a : b); i++) {
                  if (contentBlocksBuilder.containsKey(i)) {
                    latestContentBlocks.add(ContentBlock(
                      type: ContentBlockType.text,
                      text: contentBlocksBuilder[i]!.toString(),
                    ));
                  }
                }

                // Emit partial message with current state
                yield MessageStreamEvent(
                  partialMessage: Message.fromBlocks(
                    id: messageId,
                    role: MessageRole.assistant,
                    blocks: List.from(latestContentBlocks),
                  ),
                );
              }
            }
          } else if (streamEventType == 'content_block_stop') {
            // Content block completed
            // Just keep the accumulated content
          }
        } else if (eventType == 'message') {
          final payload = event['payload'];
          if (payload != null && payload['type'] == 'assistant') {
            // Complete message received (fallback for non-streaming)
            final messageContent = payload['content'];
            if (messageContent is List) {
              final currentBlocks = <ContentBlock>[];
              for (var blockJson in messageContent) {
                if (blockJson is Map<String, dynamic>) {
                  try {
                    final block = ContentBlock.fromJson(blockJson);
                    currentBlocks.add(block);
                  } catch (e) {
                    // Skip invalid blocks
                  }
                }
              }

              if (currentBlocks.isNotEmpty) {
                latestContentBlocks = currentBlocks;

                yield MessageStreamEvent(
                  partialMessage: Message.fromBlocks(
                    id: messageId,
                    role: MessageRole.assistant,
                    blocks: List.from(latestContentBlocks),
                  ),
                );
              }
            }
          } else if (payload != null && payload['type'] == 'result') {
            // ResultMessage: 提取统计信息
            final stats = MessageStats.fromResultPayload(payload);
            final result = payload['result'] as String?;
            if (result != null && result.isNotEmpty && latestContentBlocks.isEmpty) {
              latestContentBlocks = [
                ContentBlock(
                  type: ContentBlockType.text,
                  text: result,
                ),
              ];
            }
            // 发送统计信息
            yield MessageStreamEvent(
              stats: stats,
            );
          }
        } else if (eventType == 'done') {
          // Stream completed
          final finalMessage = Message.fromBlocks(
            id: messageId,
            role: MessageRole.assistant,
            blocks: latestContentBlocks,
          );
          yield MessageStreamEvent(
            finalMessage: finalMessage,
            isDone: true,
          );
          return;
        } else if (eventType == 'error') {
          yield MessageStreamEvent(
            error: event['message']?.toString() ?? 'Unknown error',
            isDone: true,
          );
          return;
        }
      }

      // Fallback: if stream ends without 'done' event
      if (latestContentBlocks.isNotEmpty) {
        yield MessageStreamEvent(
          finalMessage: Message.fromBlocks(
            id: messageId,
            role: MessageRole.assistant,
            blocks: latestContentBlocks,
          ),
          isDone: true,
        );
      }
    } catch (e) {
      yield MessageStreamEvent(
        error: e.toString(),
        isDone: true,
      );
    }
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
