enum MessageRole {
  user,
  assistant,
  system,
}

// 消息统计信息（从 ResultMessage 提取）
class MessageStats {
  final int? inputTokens;
  final int? outputTokens;
  final int? cacheCreationTokens;
  final int? cacheReadTokens;
  final int durationMs;
  final int durationApiMs;
  final double? costUsd;
  final int numTurns;

  MessageStats({
    this.inputTokens,
    this.outputTokens,
    this.cacheCreationTokens,
    this.cacheReadTokens,
    required this.durationMs,
    required this.durationApiMs,
    this.costUsd,
    this.numTurns = 1,
  });

  factory MessageStats.fromResultPayload(Map<String, dynamic> payload) {
    final usage = payload['usage'] as Map<String, dynamic>?;
    return MessageStats(
      inputTokens: usage?['input_tokens'] as int?,
      outputTokens: usage?['output_tokens'] as int?,
      cacheCreationTokens: usage?['cache_creation_input_tokens'] as int?,
      cacheReadTokens: usage?['cache_read_input_tokens'] as int?,
      durationMs: payload['duration_ms'] as int? ?? 0,
      durationApiMs: payload['duration_api_ms'] as int? ?? 0,
      costUsd: payload['total_cost_usd'] as double?,
      numTurns: payload['num_turns'] as int? ?? 1,
    );
  }

  int get totalTokens => (inputTokens ?? 0) + (outputTokens ?? 0);

  String get formattedDuration {
    final seconds = durationMs / 1000;
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}秒';
    }
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)}分钟';
  }

  String get formattedCost {
    if (costUsd == null) return '-';
    return '\$${costUsd!.toStringAsFixed(4)}';
  }
}

enum ContentBlockType {
  text,
  thinking,
  toolUse,
  toolResult,
}

class ContentBlock {
  final ContentBlockType type;
  final String? text;
  final String? thinking;
  final String? signature;
  final String? id;
  final String? name;
  final Map<String, dynamic>? input;
  final String? toolUseId;
  final dynamic content;
  final bool? isError;

  ContentBlock({
    required this.type,
    this.text,
    this.thinking,
    this.signature,
    this.id,
    this.name,
    this.input,
    this.toolUseId,
    this.content,
    this.isError,
  });

  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    ContentBlockType type;

    switch (typeStr) {
      case 'text':
        type = ContentBlockType.text;
        break;
      case 'thinking':
        type = ContentBlockType.thinking;
        break;
      case 'tool_use':
        type = ContentBlockType.toolUse;
        break;
      case 'tool_result':
        type = ContentBlockType.toolResult;
        break;
      default:
        type = ContentBlockType.text;
    }

    return ContentBlock(
      type: type,
      text: json['text'] as String?,
      thinking: json['thinking'] as String?,
      signature: json['signature'] as String?,
      id: json['id'] as String?,
      name: json['name'] as String?,
      input: json['input'] as Map<String, dynamic>?,
      toolUseId: json['tool_use_id'] as String?,
      content: json['content'],
      isError: json['is_error'] as bool?,
    );
  }
}

class Message {
  final String id;
  final MessageRole role;
  final List<ContentBlock> contentBlocks;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.role,
    required this.contentBlocks,
    required this.timestamp,
  });

  // 向后兼容：获取纯文本内容
  String get content {
    final textBlocks = contentBlocks.where((b) => b.type == ContentBlockType.text);
    return textBlocks.map((b) => b.text ?? '').join('\n');
  }

  static Message user(String content) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      contentBlocks: [
        ContentBlock(
          type: ContentBlockType.text,
          text: content,
        ),
      ],
      timestamp: DateTime.now(),
    );
  }

  static Message assistant(String content) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      contentBlocks: [
        ContentBlock(
          type: ContentBlockType.text,
          text: content,
        ),
      ],
      timestamp: DateTime.now(),
    );
  }

  static Message system(String content) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.system,
      contentBlocks: [
        ContentBlock(
          type: ContentBlockType.text,
          text: content,
        ),
      ],
      timestamp: DateTime.now(),
    );
  }

  static Message fromBlocks({
    required String id,
    required MessageRole role,
    required List<ContentBlock> blocks,
    DateTime? timestamp,
  }) {
    return Message(
      id: id,
      role: role,
      contentBlocks: blocks,
      timestamp: timestamp ?? DateTime.now(),
    );
  }
}
