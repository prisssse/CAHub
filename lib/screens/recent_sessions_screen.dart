import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/session.dart';
import '../repositories/project_repository.dart';
import '../repositories/api_session_repository.dart';
import 'tab_navigator_screen.dart';
import 'chat_screen.dart';

class RecentSessionsScreen extends StatefulWidget {
  final ProjectRepository repository;
  final Function({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  })? onOpenChat;

  const RecentSessionsScreen({
    super.key,
    required this.repository,
    this.onOpenChat,
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

  @override
  void initState() {
    super.initState();
    _loadRecentSessions();
  }

  @override
  void didUpdateWidget(RecentSessionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    setState(() => _isLoading = true);
    try {
      // 获取所有项目
      final projects = await widget.repository.getProjects();

      // 获取所有项目的会话
      final allSessions = <Session>[];
      for (var project in projects) {
        final sessions = await widget.repository.getProjectSessions(project.id);
        allSessions.addAll(sessions);
      }

      // 按 updatedAt 降序排序
      allSessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      setState(() {
        _recentSessions = allSessions;
        _isLoading = false;
        _lastRefreshTime = DateTime.now(); // 记录刷新时间
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _openSession(Session session) {
    if (widget.onOpenChat != null) {
      // 使用回调在新标签页中打开
      final apiService = widget.repository.apiService;
      final sessionRepository = ApiSessionRepository(apiService);

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
            repository: widget.repository,
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
        title: const Text('最近对话'),
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
}
