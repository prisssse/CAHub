import 'package:flutter/material.dart';
import '../repositories/project_repository.dart';
import '../repositories/codex_repository.dart';
import '../services/app_settings_service.dart';
import '../services/config_service.dart';
import 'projects/project_list_screen.dart';
import 'recent_sessions_screen.dart';

class HomeScreen extends StatefulWidget {
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
  final AgentMode? initialMode; // 标签页创建时的后端模式，用于锁定

  const HomeScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onOpenChat,
    this.onNavigate,
    this.onLogout,
    this.initialMode, // 可选参数
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      ProjectListScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: widget.onOpenChat,
        onNavigate: widget.onNavigate,
        onLogout: widget.onLogout,
        initialMode: widget.initialMode, // 传递初始模式，锁定标签页的后端选择
      ),
      RecentSessionsScreen(
        repository: widget.claudeRepository,  // Use Claude by default for recent sessions
        onOpenChat: widget.onOpenChat,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        backgroundColor: Theme.of(context).cardColor,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '项目',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: '最近对话',
          ),
        ],
      ),
    );
  }
}
