import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/project.dart';
import '../../models/session.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/codex_repository.dart';
import '../../repositories/api_session_repository.dart';
import '../../repositories/api_codex_repository.dart';
import '../sessions/session_list_screen.dart';
import '../settings/settings_screen.dart';
import '../chat_screen.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_service.dart';
import '../../services/config_service.dart';

class ProjectListScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
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
  final VoidCallback? onLogout;
  final AgentMode? initialMode; // 初始后端模式，用于锁定标签页的后端选择

  const ProjectListScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onOpenChat,
    this.onNavigate,
    this.onLogout,
    this.initialMode, // 可选参数
  });

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Project> _projects = [];
  bool _isLoading = false;
  AgentMode _currentMode = AgentMode.claudeCode; // 当前选择的模式

  @override
  void initState() {
    super.initState();
    _loadPreferredBackend();
  }

  // 从ConfigService加载用户上次选择的后端，或使用提供的初始模式
  Future<void> _loadPreferredBackend() async {
    // 如果提供了 initialMode，优先使用它（用于锁定标签页的后端选择）
    if (widget.initialMode != null) {
      setState(() {
        _currentMode = widget.initialMode!;
      });
      _loadProjects();
      return;
    }

    // 否则从 ConfigService 读取（用于新建标签页）
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;

    setState(() {
      if (preferredBackend == 'codex') {
        _currentMode = AgentMode.codex;
      } else {
        _currentMode = AgentMode.claudeCode;
      }
    });

    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      // 根据当前模式加载项目
      final projects = _currentMode == AgentMode.claudeCode
          ? await widget.claudeRepository.getProjects()
          : await widget.codexRepository.getProjects();
      setState(() {
        _projects = projects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // 切换模式
  Future<void> _switchMode(AgentMode mode) async {
    if (_currentMode != mode) {
      setState(() => _currentMode = mode);

      // 保存到ConfigService
      final configService = await ConfigService.getInstance();
      final backendString = mode == AgentMode.codex ? 'codex' : 'claude_code';
      await configService.setPreferredBackend(backendString);

      _loadProjects();
    }
  }

  Future<void> _reloadSessionsFromDisk() async {
    // 注意：reloadSessions 目前只有 Claude Code 支持
    if (_currentMode == AgentMode.codex) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Codex 模式暂不支持从磁盘加载会话'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            top: 16,
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).size.height - 100,
          ),
        ),
      );
      return;
    }

    try {
      // 显示加载对话框
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
            final primaryColor = Theme.of(context).colorScheme.primary;

            return Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primaryColor),
                      const SizedBox(height: 16),
                      Text(
                        '正在从 Claude Code 加载会话...',
                        style: TextStyle(color: textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }

      final result = await widget.claudeRepository.reloadSessions();

      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        final primaryColor = Theme.of(context).colorScheme.primary;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已加载 ${result['sessions']} 个会话，${result['agentRuns']} 个子任务',
            ),
            backgroundColor: primaryColor,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }

      // 重新加载项目列表
      _loadProjects();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        final errorColor = Theme.of(context).colorScheme.error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载失败: $e'),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

  Future<void> _addNewProject() async {
    final pathController = TextEditingController(text: 'C:\\Users');

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return AlertDialog(
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
              const SizedBox(height: 12),
              Text(
                '创建后将直接进入对话界面',
                style: TextStyle(
                  fontSize: 12,
                  color: appColors.textSecondary,
                ),
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
                if (pathController.text.trim().isNotEmpty) {
                  Navigator.pop(context, pathController.text.trim());
                }
              },
              child: Text('创建', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      _openNewProjectChat(result);
    }
  }

  void _openNewProjectChat(String cwd) {
    // 创建一个临时session（没有id，表示尚未创建）
    final tempSession = Session(
      id: '', // 空id表示还没有创建session
      projectId: cwd,
      title: '新对话',
      name: '新对话',
      cwd: cwd,
      messageCount: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 根据当前模式选择 repository
    final apiService = _currentMode == AgentMode.claudeCode
        ? widget.claudeRepository.apiService
        : widget.codexRepository.apiService;
    final dynamic sessionRepository = _currentMode == AgentMode.claudeCode
        ? ApiSessionRepository(apiService)
        : ApiCodexRepository(apiService);

    if (widget.onOpenChat != null) {
      // 使用回调在新标签页打开
      widget.onOpenChat!(
        sessionId: 'new_${DateTime.now().millisecondsSinceEpoch}',
        sessionName: '新对话 - ${cwd.split('\\').last}',
        chatWidget: ChatScreen(
          session: tempSession,
          repository: sessionRepository,
        ),
      );
    } else {
      // 降级到导航方式
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            session: tempSession,
            repository: sessionRepository,
          ),
        ),
      ).then((_) => _loadProjects());
    }
  }

  Future<void> _startNewProjectSession(String cwd, String firstMessage) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
          final primaryColor = Theme.of(context).colorScheme.primary;

          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primaryColor),
                    const SizedBox(height: 16),
                    Text(
                      '正在创建会话...',
                      style: TextStyle(color: textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      String? newSessionId;
      final apiService = widget.claudeRepository.apiService;

      await for (var event in apiService.chat(message: firstMessage, cwd: cwd)) {
        if (event['event_type'] == 'session') {
          newSessionId = event['session_id'];
          break;
        }
      }

      if (mounted) Navigator.pop(context); // Close loading dialog

      if (newSessionId != null && mounted) {
        // Fetch the created session
        final session = await widget.claudeRepository.getSession(newSessionId);

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
              repository: widget.claudeRepository,
            ),
          ),
        ).then((_) => _loadProjects());
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        final errorColor = Theme.of(context).colorScheme.error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建失败: $e'),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height - 100,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = Theme.of(context).cardColor;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('项目'),
            const SizedBox(width: 12),
            Flexible(
              child: _buildBackendSelector(primaryColor, cardColor, backgroundColor),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadSessionsFromDisk,
            tooltip: _currentMode == AgentMode.claudeCode
                ? '从 Claude Code 加载会话'
                : '从 Codex 加载会话',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    claudeRepository: widget.claudeRepository,
                    codexRepository: widget.codexRepository,
                    onLogout: widget.onLogout,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewProject,
        backgroundColor: primaryColor,
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
                            color: appColors.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '未找到项目',
                            style: TextStyle(
                              fontSize: 18,
                              color: appColors.textSecondary,
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
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = Theme.of(context).cardColor;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      child: InkWell(
        onTap: () {
          // 根据当前模式选择正确的 repository
          final repository = _currentMode == AgentMode.claudeCode
              ? widget.claudeRepository
              : widget.codexRepository;

          if (widget.onNavigate != null) {
            // 在当前标签页中打开项目的会话列表
            widget.onNavigate!(
              id: 'project_${project.id}',
              title: project.name,
              content: SessionListScreen(
                project: project,
                repository: repository,
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
                  repository: repository,
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
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder,
                      color: primaryColor,
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
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          project.path,
                          style: TextStyle(
                            fontSize: 13,
                            color: appColors.textSecondary,
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

  Widget _buildBackendSelector(Color primaryColor, Color cardColor, Color backgroundColor) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.2), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showBackendPicker(primaryColor, cardColor),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentMode == AgentMode.claudeCode ? Icons.code : Icons.terminal,
                  size: 16,
                  color: primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  _currentMode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 18, color: primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBackendPicker(Color primaryColor, Color cardColor) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: appColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '选择后端模式',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildBackendOption(
              mode: AgentMode.claudeCode,
              icon: Icons.code,
              title: 'Claude Code',
              description: '官方 Claude Code 后端',
              primaryColor: primaryColor,
              appColors: appColors,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 12),
            _buildBackendOption(
              mode: AgentMode.codex,
              icon: Icons.terminal,
              title: 'Codex',
              description: 'Codex 兼容后端',
              primaryColor: primaryColor,
              appColors: appColors,
              textPrimary: textPrimary,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendOption({
    required AgentMode mode,
    required IconData icon,
    required String title,
    required String description,
    required Color primaryColor,
    required dynamic appColors,
    required Color textPrimary,
  }) {
    final isSelected = _currentMode == mode;
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;

    return Material(
      color: isSelected ? primaryColor.withOpacity(0.1) : cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _switchMode(mode);
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primaryColor : dividerColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withOpacity(0.15)
                      : primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? primaryColor : appColors.textSecondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: primaryColor,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    final appColors = context.appColors;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: appColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: appColors.textSecondary,
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
