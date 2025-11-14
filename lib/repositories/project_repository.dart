import '../models/project.dart';
import '../models/session.dart';

abstract class ProjectRepository {
  Future<List<Project>> getProjects();
  Future<Project> getProject(String id);
  Future<List<Session>> getProjectSessions(String projectId);
  Future<Session> getSession(String sessionId);

  // 从 Claude Code 目录重新加载会话
  Future<Map<String, int>> reloadSessions({String? claudeDir});

  // For creating new sessions
  dynamic get apiService;
}
