import '../models/project.dart';
import '../models/session.dart';
import '../services/api_service.dart';
import 'project_repository.dart';

class ApiProjectRepository implements ProjectRepository {
  final ApiService _apiService;

  ApiProjectRepository(this._apiService);

  @override
  Future<List<Project>> getProjects() async {
    final sessions = await _apiService.getSessions();

    // Group sessions by cwd to create projects
    final Map<String, List<Map<String, dynamic>>> projectMap = {};
    for (var session in sessions) {
      final cwd = session['cwd'] as String;
      projectMap.putIfAbsent(cwd, () => []).add(session);
    }

    // Convert to Project list
    final projects = <Project>[];
    projectMap.forEach((cwd, sessions) {
      // Use the directory name as project name
      final name = cwd.split(RegExp(r'[/\\]')).last;

      // Find the earliest created_at and latest updated_at
      DateTime? earliest;
      DateTime? latest;
      int totalMessages = 0;

      for (var session in sessions) {
        final createdAt = DateTime.parse(session['created_at']);
        final updatedAt = DateTime.parse(session['updated_at']);
        totalMessages += (session['message_count'] as int?) ?? 0;

        if (earliest == null || createdAt.isBefore(earliest)) {
          earliest = createdAt;
        }
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }

      projects.add(Project(
        id: cwd, // Use cwd as unique ID
        name: name,
        path: cwd,
        createdAt: earliest ?? DateTime.now(),
        lastActiveAt: latest,
        sessionCount: sessions.length,
      ));
    });

    // Sort by lastActiveAt descending
    projects.sort((a, b) {
      if (a.lastActiveAt == null && b.lastActiveAt == null) return 0;
      if (a.lastActiveAt == null) return 1;
      if (b.lastActiveAt == null) return -1;
      return b.lastActiveAt!.compareTo(a.lastActiveAt!);
    });

    return projects;
  }

  @override
  Future<Project> getProject(String id) async {
    final projects = await getProjects();
    return projects.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Project not found'),
    );
  }

  @override
  Future<List<Session>> getProjectSessions(String projectId) async {
    final allSessions = await _apiService.getSessions();

    // Filter sessions by cwd (projectId is the cwd)
    final projectSessions = allSessions
        .where((s) => s['cwd'] == projectId)
        .map((s) => Session(
              id: s['session_id'],
              projectId: projectId,
              title: s['title'],
              name: s['title'], // Use title as name
              cwd: s['cwd'],
              createdAt: DateTime.parse(s['created_at']),
              updatedAt: DateTime.parse(s['updated_at']),
              messageCount: s['message_count'] ?? 0,
            ))
        .toList();

    // Sort by updatedAt descending
    projectSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return projectSessions;
  }
}
