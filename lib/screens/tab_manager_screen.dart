import 'dart:ui';

import 'package:flutter/material.dart';
import '../core/constants/colors.dart';
import '../core/utils/platform_helper.dart';
import '../repositories/project_repository.dart';
import 'home_screen.dart';

// 定义标签页类型
enum TabType {
  home, // 首页（项目和最近对话）
  chat, // 具体对话
}

class TabInfo {
  final String id;
  final TabType type;
  final String title;
  final Widget content;

  TabInfo({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
  });
}

class TabManagerScreen extends StatefulWidget {
  final ProjectRepository repository;
  final VoidCallback? onLogout;

  const TabManagerScreen({
    super.key,
    required this.repository,
    this.onLogout,
  });

  @override
  State<TabManagerScreen> createState() => _TabManagerScreenState();
}

class _TabManagerScreenState extends State<TabManagerScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final List<TabInfo> _tabs = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 初始化 TabController
    _tabController = TabController(
      length: 0,
      vsync: this,
    );
    // 默认打开一个首页标签
    _addHomeTab();
  }

  void _addHomeTab() {
    final newTab = TabInfo(
      id: 'home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        repository: widget.repository,
        onOpenChat: _openChatInCurrentTab,
        onNavigate: _replaceCurrentTab,
        onLogout: widget.onLogout,
      ),
    );

    setState(() {
      _tabs.add(newTab);
    });

    _rebuildTabController(_tabs.length - 1);
  }

  void _replaceCurrentTab({
    required String id,
    required String title,
    required Widget content,
  }) {
    final newTab = TabInfo(
      id: id,
      type: TabType.home, // 保持为 home 类型，因为不是聊天
      title: title,
      content: content,
    );

    setState(() {
      _tabs[_currentIndex] = newTab;
    });
  }

  void _openChatInCurrentTab({
    required String sessionId,
    required String sessionName,
    required Widget chatWidget,
  }) {
    // 检查是否已经在其他标签页打开该会话
    final existingIndex = _tabs.indexWhere(
      (tab) => tab.id == 'chat_$sessionId',
    );

    if (existingIndex != -1) {
      // 切换到已存在的标签
      _tabController.animateTo(existingIndex);
      return;
    }

    // 替换当前标签页
    final newTab = TabInfo(
      id: 'chat_$sessionId',
      type: TabType.chat,
      title: sessionName,
      content: chatWidget,
    );

    setState(() {
      _tabs[_currentIndex] = newTab;
    });
  }

  void _addNewTab() {
    // 默认添加主页标签
    _addHomeTab();
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      // 最后一个标签，关闭后回到主页
      setState(() {
        _tabs.removeAt(index);
      });
      // 添加一个新的主页标签
      _addHomeTab();
      return;
    }

    setState(() {
      _tabs.removeAt(index);
    });

    // 重新创建 TabController
    final newIndex = index >= _tabs.length ? _tabs.length - 1 : index;
    _rebuildTabController(newIndex);
  }

  void _rebuildTabController(int initialIndex) {
    _tabController.dispose();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });

    setState(() {
      _currentIndex = initialIndex;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claude Code Mobile'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.cardBackground,
            child: Row(
              children: [
                Expanded(
                  child: PlatformHelper.showTabBarScrollbar
                      ? ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                            },
                            scrollbars: true,
                          ),
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: _tabs.asMap().entries.map((entry) {
                              final index = entry.key;
                              final tab = entry.value;
                              return Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      tab.type == TabType.home
                                          ? Icons.home_outlined
                                          : Icons.chat_outlined,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      tab.title.length > 12
                                          ? '${tab.title.substring(0, 12)}...'
                                          : tab.title,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _closeTab(index),
                                      child: const Icon(Icons.close, size: 14),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        )
                      : TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: _tabs.asMap().entries.map((entry) {
                            final index = entry.key;
                            final tab = entry.value;
                            return Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    tab.type == TabType.home
                                        ? Icons.home_outlined
                                        : Icons.chat_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    tab.title.length > 12
                                        ? '${tab.title.substring(0, 12)}...'
                                        : tab.title,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => _closeTab(index),
                                    child: const Icon(Icons.close, size: 14),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.divider, width: 1),
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: _addNewTab,
                    tooltip: '新建标签页',
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) => tab.content).toList(),
      ),
    );
  }
}
