import 'dart:convert';

import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';
import '../services/api_service.dart';
import 'session_repository.dart';

// Helper class to track message building state
class _MessageBuildState {
  final contentBlockTypes = <int, String>{};
  final textBlocksBuilder = <int, StringBuffer>{};
  final toolUseBlocks = <int, Map<String, dynamic>>{};
  final finalizedBlocks = <int>{}; // Track which blocks are finalized
  bool finalized = false;
}

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
    String? sessionId, // 可选，如果为null则创建新session
    required String content,
    String? cwd, // 工作目录，创建新session时必需
    SessionSettings? settings,
  }) async* {
    // Track multiple messages by their message IDs (for multi-turn)
    final messageStates = <String, _MessageBuildState>{}; // message.id -> build state
    String? currentMessageId;
    String? createdSessionId; // 捕获新创建的session ID
    bool sessionIdEmitted = false; // 标记是否已发送session ID

    try {
      await for (var event in _apiService.chat(
        sessionId: sessionId,
        message: content,
        cwd: cwd,
        settings: settings,
      )) {
        final eventType = event['event_type'];
        print('DEBUG SSE: Received event type: $eventType');

        // 捕获session_id（通常在第一个事件中）
        if (!sessionIdEmitted && event['session_id'] != null) {
          createdSessionId = event['session_id'] as String?;
          if (createdSessionId != null && createdSessionId.isNotEmpty) {
            // 立即发送session ID给前端
            yield MessageStreamEvent(sessionId: createdSessionId);
            sessionIdEmitted = true;
            print('DEBUG SSE: Captured session_id: $createdSessionId');
          }
        }

        // Check if this is a message event with stream_event payload
        bool isStreamEvent = false;
        Map<String, dynamic>? streamEvent;

        if (eventType == 'message') {
          final payload = event['payload'];
          print('DEBUG SSE: Message payload type: ${payload?['type']}');
          if (payload != null && payload['type'] == 'stream_event') {
            isStreamEvent = true;
            streamEvent = payload['event'] as Map<String, dynamic>?;
            print('DEBUG SSE: Stream event type: ${streamEvent?['type']}');
          }
        }

        if (isStreamEvent && streamEvent != null) {
          final streamEventType = streamEvent['type'];

          // message_start: Extract message ID
          if (streamEventType == 'message_start') {
            final message = streamEvent['message'];
            if (message != null) {
              final messageId = message['id'] as String?;
              if (messageId != null) {
                currentMessageId = messageId;
                if (!messageStates.containsKey(messageId)) {
                  messageStates[messageId] = _MessageBuildState();
                }
              }
            }
            continue; // Don't emit anything for message_start
          }

          // Get current state
          final state = currentMessageId != null ? messageStates[currentMessageId!] : null;
          if (state == null) continue;

          if (streamEventType == 'content_block_start') {
            // New content block started
            final index = streamEvent['index'] as int?;
            final contentBlock = streamEvent['content_block'];

            if (index != null && contentBlock != null) {
              final blockType = contentBlock['type'] as String?;
              state.contentBlockTypes[index] = blockType ?? 'text';

              if (blockType == 'text') {
                state.textBlocksBuilder[index] = StringBuffer();
                final text = contentBlock['text'] as String?;
                if (text != null) {
                  state.textBlocksBuilder[index]!.write(text);
                }
              } else if (blockType == 'tool_use') {
                state.toolUseBlocks[index] = {
                  'id': contentBlock['id'],
                  'name': contentBlock['name'],
                  'input': {},
                };
              }
            }
          } else if (streamEventType == 'content_block_delta') {
            // Incremental content update
            final index = streamEvent['index'] as int? ?? 0;
            final delta = streamEvent['delta'];
            print('DEBUG SSE: content_block_delta at index $index, delta type: ${delta?['type']}');

            if (delta != null) {
              final deltaType = delta['type'] as String?;

              if (deltaType == 'text_delta') {
                final text = delta['text'] as String?;
                print('DEBUG SSE: text_delta: "$text"');
                if (text != null) {
                  if (!state.textBlocksBuilder.containsKey(index)) {
                    state.textBlocksBuilder[index] = StringBuffer();
                    state.contentBlockTypes[index] = 'text';
                  }
                  state.textBlocksBuilder[index]!.write(text);
                }
              } else if (deltaType == 'input_json_delta') {
                final jsonDelta = delta['partial_json'] as String?;
                if (jsonDelta != null && state.toolUseBlocks.containsKey(index)) {
                  // Accumulate JSON for tool input
                  state.toolUseBlocks[index]!['input_json'] =
                      (state.toolUseBlocks[index]!['input_json'] ?? '') + jsonDelta;
                }
              }
            }

            // Rebuild content blocks from current state
            final blocks = _buildContentBlocks(
              state.contentBlockTypes,
              state.textBlocksBuilder,
              state.toolUseBlocks,
              state.finalizedBlocks,
            );

            // Emit partial message with current state
            if (blocks.isNotEmpty) {
              print('DEBUG SSE: Emitting partialMessage with ${blocks.length} blocks');
              yield MessageStreamEvent(
                partialMessage: Message.fromBlocks(
                  id: currentMessageId!,
                  role: MessageRole.assistant,
                  blocks: List.from(blocks),
                ),
              );
            }
          } else if (streamEventType == 'content_block_stop') {
            // Content block completed - finalize any pending tool inputs
            final index = streamEvent['index'] as int?;
            if (index != null) {
              // Mark this block as finalized
              state.finalizedBlocks.add(index);

              // For tool_use blocks, parse the accumulated JSON
              if (state.toolUseBlocks.containsKey(index)) {
                final inputJson = state.toolUseBlocks[index]!['input_json'] as String?;
                if (inputJson != null && inputJson.isNotEmpty) {
                  try {
                    final decoded = json.decode(inputJson);
                    if (decoded is Map<String, dynamic>) {
                      state.toolUseBlocks[index]!['input'] = decoded;
                    }
                  } catch (e) {
                    print('Failed to parse tool input JSON: $e');
                    print('JSON string was: $inputJson');
                    // Keep empty input if JSON parsing fails
                  }
                }
              }

              // Rebuild and emit message with newly finalized block
              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty && currentMessageId != null) {
                yield MessageStreamEvent(
                  partialMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: List.from(blocks),
                  ),
                );
              }
            }
          } else if (streamEventType == 'message_stop') {
            // Message completed - emit final version
            if (currentMessageId != null && state != null) {
              final blocks = _buildContentBlocks(
                state.contentBlockTypes,
                state.textBlocksBuilder,
                state.toolUseBlocks,
                state.finalizedBlocks,
              );

              if (blocks.isNotEmpty) {
                yield MessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: currentMessageId!,
                    role: MessageRole.assistant,
                    blocks: blocks,
                  ),
                );
                state.finalized = true;
              }
            }
          }
        } else if (eventType == 'message') {
          final payload = event['payload'];

          // Skip stream_event payloads (already handled above)
          if (payload != null && payload['type'] == 'stream_event') {
            continue;
          }

          if (payload != null && payload['type'] == 'assistant') {
            // Complete message received - only use if no streaming occurred
            final messageId = payload['id'] as String?;

            // Skip if we have any messages built via streaming
            // (AssistantMessage often lacks ID, so we can't match it precisely)
            if (messageStates.isNotEmpty) {
              // If any streaming has occurred, ignore non-streaming fallbacks
              continue;
            }

            // Fallback for truly non-streaming responses (rare)
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
                final fallbackId = messageId ?? '${sessionId}_${DateTime.now().millisecondsSinceEpoch}';
                yield MessageStreamEvent(
                  finalMessage: Message.fromBlocks(
                    id: fallbackId,
                    role: MessageRole.assistant,
                    blocks: List.from(currentBlocks),
                  ),
                );
              }
            }
          } else if (payload != null && payload['type'] == 'result') {
            // ResultMessage: 提取统计信息
            final stats = MessageStats.fromResultPayload(payload);
            // 发送统计信息
            yield MessageStreamEvent(
              stats: stats,
            );
          }
        } else if (eventType == 'done') {
          // Stream completed - only needed for stats/cleanup
          yield MessageStreamEvent(isDone: true);
          return;
        } else if (eventType == 'error') {
          yield MessageStreamEvent(
            error: event['message']?.toString() ?? 'Unknown error',
            isDone: true,
          );
          return;
        }
      }

      // Fallback: if stream ends without 'done' event (shouldn't happen normally)
      yield MessageStreamEvent(isDone: true);
    } catch (e) {
      // More detailed error logging
      print('Stream error: $e');
      yield MessageStreamEvent(
        error: e.toString(),
        isDone: true,
      );
    }
  }

  List<ContentBlock> _buildContentBlocks(
    Map<int, String> types,
    Map<int, StringBuffer> textBlocks,
    Map<int, Map<String, dynamic>> toolBlocks,
    Set<int> finalizedBlocks,
  ) {
    final blocks = <ContentBlock>[];

    // Get all indices and sort them
    final allIndices = <int>{};
    allIndices.addAll(types.keys);
    final sortedIndices = allIndices.toList()..sort();

    for (final index in sortedIndices) {
      final blockType = types[index];

      if (blockType == 'text' && textBlocks.containsKey(index)) {
        final text = textBlocks[index]!.toString();
        if (text.isNotEmpty) {
          blocks.add(ContentBlock(
            type: ContentBlockType.text,
            text: text,
          ));
        }
      } else if (blockType == 'tool_use' && toolBlocks.containsKey(index)) {
        // Only include tool_use blocks that have been finalized
        if (finalizedBlocks.contains(index)) {
          final toolBlock = toolBlocks[index]!;
          blocks.add(ContentBlock(
            type: ContentBlockType.toolUse,
            id: toolBlock['id'] as String?,
            name: toolBlock['name'] as String?,
            input: toolBlock['input'] as Map<String, dynamic>?,
          ));
        }
      }
    }

    return blocks;
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
