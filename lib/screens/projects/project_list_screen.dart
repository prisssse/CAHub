import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../models/project.dart';
import '../../repositories/project_repository.dart';
import '../sessions/session_list_screen.dart';
import '../settings/settings_screen.dart';
import '../../services/api_service.dart';

class ProjectListScreen extends StatefulWidget {
  final ProjectRepository repository;
  final Function({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  })? onOpenChat;
  final Function({
    required String id,
    required String title,
    required Widget content,
  })? onNavigate;

  const ProjectListScreen({
    super.key,
    required this.repository,
    this.onOpenChat,
    this.onNavigate,
  });

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Project> _projects = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final projects = await widget.repository.getProjects();
      setState(() {
        _projects = projects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadSessionsFromDisk() async {
    try {
      // 显示加载对话框
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      '正在从 Claude Code 加载会话...',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final result = await widget.repository.reloadSessions();

      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已加载 ${result['sessions']} 个会话，${result['agentRuns']} 个子任务',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }

      // 重新加载项目列表
      _loadProjects();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addNewProject() async {
    final pathController = TextEditingController(text: 'C:\\Users');
    final messageController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加项目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '项目路径',
                hintText: '输入项目目录路径',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: '第一条消息',
                hintText: '输入你想问的问题',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (pathController.text.trim().isNotEmpty &&
                  messageController.text.trim().isNotEmpty) {
                Navigator.pop(context, {
                  'path': pathController.text.trim(),
                  'message': messageController.text.trim(),
                });
              }
            },
            child: Text('创建', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      _startNewProjectSession(result['path']!, result['message']!);
    }
  }

  Future<void> _startNewProjectSession(String cwd, String firstMessage) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    '正在创建会话...',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      String? newSessionId;
      final apiService = widget.repository.apiService;

      await for (var event in apiService.chat(message: firstMessage, cwd: cwd)) {
        if (event['event_type'] == 'session') {
          newSessionId = event['session_id'];
          break;
        }
      }

      if (mounted) Navigator.pop(context); // Close loading dialog

      if (newSessionId != null && mounted) {
        // Fetch the created session
        final session = await widget.repository.getSession(newSessionId);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionListScreen(
              project: Project(
                id: cwd,
                name: cwd.split('\\').last,
                path: cwd,
                sessionCount: 1,
                createdAt: DateTime.now(),
              ),
              repository: widget.repository,
            ),
          ),
        ).then((_) => _loadProjects());
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('项目'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadSessionsFromDisk,
            tooltip: '从 Claude Code 加载会话',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewProject,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProjects,
              child: _projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 64,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '未找到项目',
                            style: TextStyle(
                              fontSize: 18,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _projects.length,
                      itemBuilder: (context, index) {
                        final project = _projects[index];
                        return _buildProjectCard(project);
                      },
                    ),
            ),
    );
  }

  Widget _buildProjectCard(Project project) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: () {
          if (widget.onNavigate != null) {
            // 在当前标签页中打开项目的会话列表
            widget.onNavigate!(
              id: 'project_${project.id}',
              title: project.name,
              content: SessionListScreen(
                project: project,
                repository: widget.repository,
                onOpenChat: widget.onOpenChat,
                onNavigate: widget.onNavigate,
              ),
            );
          } else {
            // 降级到 Navigator（用于独立测试）
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionListScreen(
                  project: project,
                  repository: widget.repository,
                  onOpenChat: widget.onOpenChat,
                  onNavigate: widget.onNavigate,
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          project.path,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(
                    icon: Icons.chat_bubble_outline,
                    label: '${project.sessionCount} 个会话',
                  ),
                  const SizedBox(width: 12),
                  if (project.lastActiveAt != null)
                    _buildInfoChip(
                      icon: Icons.access_time,
                      label: _formatTime(project.lastActiveAt!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.year}/${time.month}/${time.day}';
  }
}
