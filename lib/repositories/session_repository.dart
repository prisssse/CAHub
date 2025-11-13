import '../models/session.dart';
import '../models/message.dart';
import '../models/session_settings.dart';

abstract class SessionRepository {
  Future<Session> getSession(String id);
  Future<List<Message>> getSessionMessages(String sessionId);
  Future<Message> sendMessage({
    required String sessionId,
    required String content,
    SessionSettings? settings,
  });
  Future<void> clearSessionMessages(String sessionId);
}
