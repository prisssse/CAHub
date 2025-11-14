import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../core/constants/colors.dart';
import '../core/utils/platform_helper.dart';
import '../repositories/project_repository.dart';
import '../repositories/session_repository.dart';
import '../models/project.dart';
import '../services/app_settings_service.dart';
import 'chat_screen.dart';
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
  bool hasNewReply; // 是否有新回复（用于标签高亮）
  final ValueNotifier<bool> hasNewReplyNotifier; // 新回复通知器

  TabInfo({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.hasNewReply = false,
  }) : hasNewReplyNotifier = ValueNotifier<bool>(hasNewReply);

  void dispose() {
    hasNewReplyNotifier.dispose();
  }
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

    // 保存当前要替换的标签索引
    final targetIndex = _currentIndex;

    // 创建新的TabInfo（包含ValueNotifier）
    final newTab = TabInfo(
      id: 'chat_$sessionId',
      type: TabType.chat,
      title: sessionName,
      content: Container(), // 临时占位
    );

    // 如果 chatWidget 是 ChatScreen，重新创建并添加回调和通知器
    Widget wrappedWidget = chatWidget;
    if (chatWidget is ChatScreen) {
      wrappedWidget = ChatScreen(
        session: chatWidget.session,
        repository: chatWidget.repository,
        onMessageComplete: () => _handleMessageComplete(targetIndex),
        hasNewReplyNotifier: newTab.hasNewReplyNotifier,
      );
    }

    // 替换当前标签页（需要先dispose旧的）
    setState(() {
      _tabs[_currentIndex].dispose();
      _tabs[_currentIndex] = TabInfo(
        id: 'chat_$sessionId',
        type: TabType.chat,
        title: sessionName,
        content: wrappedWidget,
      );
    });
  }

  void _addNewTab() {
    // 默认添加主页标签
    _addHomeTab();
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      // 最后一个标签，关闭后回到主页
      final oldTab = _tabs[index];
      setState(() {
        _tabs.removeAt(index);
      });
      oldTab.dispose();
      // 添加一个新的主页标签
      _addHomeTab();
      return;
    }

    final oldTab = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
    });
    oldTab.dispose();

    // 重新创建 TabController
    final newIndex = index >= _tabs.length ? _tabs.length - 1 : index;
    _rebuildTabController(newIndex);
  }

  // 处理标签的消息完成通知
  void _handleMessageComplete(int tabIndex) {
    // 只有当标签不是当前活动标签时才显示通知
    if (tabIndex != _currentIndex && tabIndex < _tabs.length) {
      setState(() {
        _tabs[tabIndex].hasNewReply = true;
        _tabs[tabIndex].hasNewReplyNotifier.value = true;
      });

      // 检查是否启用了通知
      final settingsService = AppSettingsService();
      if (!settingsService.notificationsEnabled) {
        return; // 通知已禁用，不显示
      }

      // 播放系统提示音（使用 Flutter 内置的反馈）
      if (context.mounted) {
        // 显示顶部MaterialBanner通知（比SnackBar更显眼）
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: AppColors.primary.withOpacity(0.95),
            content: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_tabs[tabIndex].title} 有新回复',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  _tabController.animateTo(tabIndex);
                },
                child: const Text(
                  '查看',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: const Text(
                  '关闭',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        );

        // 3秒后自动隐藏
        Future.delayed(const Duration(seconds: 3), () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          }
        });
      }
    }
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
          // 切换到标签时清除新回复标记
          if (_currentIndex < _tabs.length) {
            _tabs[_currentIndex].hasNewReply = false;
            _tabs[_currentIndex].hasNewReplyNotifier.value = false;
          }
        });
      }
    });

    setState(() {
      _currentIndex = initialIndex;
      // 初始标签也清除标记
      if (_currentIndex < _tabs.length) {
        _tabs[_currentIndex].hasNewReply = false;
        _tabs[_currentIndex].hasNewReplyNotifier.value = false;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var tab in _tabs) {
      tab.dispose();
    }
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
                                    // 新回复提示小圆点
                                    if (tab.hasNewReply) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
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
                                  // 新回复提示小圆点
                                  if (tab.hasNewReply) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
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
