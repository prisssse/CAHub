import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';

// 用于流式消息更新的事件
class MessageStreamEvent {
  final Message? partialMessage; // 正在构建中的消息
  final Message? finalMessage; // 最终完成的消息
  final MessageStats? stats; // 统计信息（从 ResultMessage 提取）
  final String? error;
  final bool isDone;

  MessageStreamEvent({
    this.partialMessage,
    this.finalMessage,
    this.stats,
    this.error,
    this.isDone = false,
  });
}

abstract class SessionRepository {
  Future<Session> getSession(String id);
  Future<List<Message>> getSessionMessages(String sessionId);

  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  });

  // 流式发送消息，实时返回内容块
  Stream<MessageStreamEvent> sendMessageStream({
    String? sessionId, // 可选，如果为null则创建新session
    required String content,
    String? cwd, // 工作目录，创建新session时必需
    SessionSettings? settings,
  });

  Future<void> clearSessionMessages(String sessionId);
}
