import 'package:flutter/material.dart';
import '../repositories/project_repository.dart';
import 'projects/project_list_screen.dart';
import 'recent_sessions_screen.dart';

class HomeScreen extends StatefulWidget {
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
  final VoidCallback? onLogout;

  const HomeScreen({
    super.key,
    required this.repository,
    this.onOpenChat,
    this.onNavigate,
    this.onLogout,
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
        repository: widget.repository,
        onOpenChat: widget.onOpenChat,
        onNavigate: widget.onNavigate,
        onLogout: widget.onLogout,
      ),
      RecentSessionsScreen(
        repository: widget.repository,
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
