import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/session.dart';
import '../repositories/project_repository.dart';
import '../repositories/codex_repository.dart';
import '../repositories/api_session_repository.dart';
import '../repositories/api_codex_repository.dart';
import '../services/app_settings_service.dart';
import '../services/config_service.dart';
import 'tab_navigator_screen.dart';
import 'chat_screen.dart';

class RecentSessionsScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
  final Function({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  })? onOpenChat;
  final AgentMode? sharedMode; // 共享的模式状态
  final Function(AgentMode)? onModeChanged; // 模式切换回调

  const RecentSessionsScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onOpenChat,
    this.sharedMode,
    this.onModeChanged,
  });

  @override
  State<RecentSessionsScreen> createState() => _RecentSessionsScreenState();
}

class _RecentSessionsScreenState extends State<RecentSessionsScreen> with AutomaticKeepAliveClientMixin {
  List<Session> _recentSessions = [];
  bool _isLoading = false;
  DateTime? _lastRefreshTime; // 上次刷新时间
  static const Duration _autoRefreshInterval = Duration(minutes: 1); // 自动刷新间隔

  @override
  bool get wantKeepAlive => true; // 保持状态

  // 获取当前模式（优先使用共享模式）
  AgentMode get _currentMode => widget.sharedMode ?? AgentMode.claudeCode;

  // 获取当前使用的仓库
  dynamic get _currentRepository => _currentMode == AgentMode.claudeCode
      ? widget.claudeRepository
      : widget.codexRepository;

  @override
  void initState() {
    super.initState();
    _loadRecentSessions();
  }

  @override
  void didUpdateWidget(RecentSessionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果共享模式变化，重新加载会话
    if (oldWidget.sharedMode != widget.sharedMode && widget.sharedMode != null) {
      _loadRecentSessions();
    }

    _checkAndAutoRefresh();
  }

  // 检查并自动刷新
  void _checkAndAutoRefresh() {
    if (_lastRefreshTime == null) {
      return; // 首次加载，不需要自动刷新
    }

    final now = DateTime.now();
    final timeSinceLastRefresh = now.difference(_lastRefreshTime!);

    if (timeSinceLastRefresh >= _autoRefreshInterval) {
      print('DEBUG: Auto-refreshing recent sessions (last refresh: ${timeSinceLastRefresh.inSeconds}s ago)');
      _loadRecentSessions();
    }
  }

  Future<void> _loadRecentSessions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // 获取所有项目
      final projects = await _currentRepository.getProjects();

      // 获取所有项目的会话
      final allSessions = <Session>[];
      for (var project in projects) {
        final sessions = await _currentRepository.getProjectSessions(project.id);
        allSessions.addAll(sessions);
      }

      // 按 updatedAt 降序排序
      allSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) return;
      setState(() {
        _recentSessions = allSessions;
        _isLoading = false;
        _lastRefreshTime = DateTime.now(); // 记录刷新时间
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // 切换模式
  Future<void> _switchMode(AgentMode mode) async {
    if (_currentMode != mode) {
      // 通知父组件模式变化
      widget.onModeChanged?.call(mode);

      // 保存到ConfigService
      final configService = await ConfigService.getInstance();
      final backendString = mode == AgentMode.codex ? 'codex' : 'claude_code';
      await configService.setPreferredBackend(backendString);
    }
  }

  void _openSession(Session session) {
    if (widget.onOpenChat != null) {
      // 使用回调在新标签页中打开
      final apiService = _currentRepository.apiService;
      final sessionRepository = _currentMode == AgentMode.claudeCode
          ? ApiSessionRepository(apiService)
          : ApiCodexRepository(apiService);

      widget.onOpenChat!(
        sessionId: session.id,
        sessionName: session.name,
        chatWidget: ChatScreen(
          session: session,
          repository: sessionRepository,
        ),
      );
    } else {
      // 降级到导航方式（用于独立测试）
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TabNavigatorScreen(
            repository: _currentRepository,
            initialSession: session,
          ),
        ),
      ).then((_) => _loadRecentSessions());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以支持 AutomaticKeepAliveClientMixin

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
        title: _buildBackendSelector(primaryColor, cardColor, backgroundColor),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRecentSessions,
              child: _recentSessions.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _recentSessions.length,
                      itemBuilder: (context, index) {
                        final session = _recentSessions[index];
                        return _buildSessionCard(session);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    final appColors = context.appColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: appColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无最近对话',
            style: TextStyle(
              fontSize: 18,
              color: appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Session session) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = Theme.of(context).cardColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
      child: InkWell(
        onTap: () => _openSession(session),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.chat,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          session.cwd,
                          style: TextStyle(
                            fontSize: 12,
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
                    icon: Icons.message_outlined,
                    label: '${session.messageCount} 条消息',
                  ),
                  const SizedBox(width: 12),
                  _buildInfoChip(
                    icon: Icons.access_time,
                    label: _formatTime(session.updatedAt),
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
          Icon(icon, size: 12, color: appColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
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

  // 构建后端选择器
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
          Navigator.pop(context);
          _switchMode(mode);
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
              Icon(icon, size: 24, color: isSelected ? primaryColor : textPrimary),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 4),
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
                Icon(Icons.check_circle, size: 24, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }
}
