import '../models/project.dart';
import '../models/session.dart';

abstract class ProjectRepository {
  Future<List<Project>> getProjects();
  Future<Project> getProject(String id);
  Future<List<Session>> getProjectSessions(String projectId);
}
