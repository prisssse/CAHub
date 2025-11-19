import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/platform_helper.dart';
import '../repositories/api_codex_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/codex_repository.dart';
import '../models/project.dart';
import '../services/app_settings_service.dart';
import '../services/config_service.dart';
import '../services/notification_sound_service.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'sessions/session_list_screen.dart';

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
  final Widget? previousContent; // 上一个界面（用于返回）
  final String? previousTitle; // 上一个界面的标题
  final Widget? previousPreviousContent; // 更深一层的历史界面
  final String? previousPreviousTitle; // 更深一层的历史标题

  TabInfo({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.hasNewReply = false,
    this.previousContent,
    this.previousTitle,
    this.previousPreviousContent,
    this.previousPreviousTitle,
  }) : hasNewReplyNotifier = ValueNotifier<bool>(hasNewReply);

  void dispose() {
    hasNewReplyNotifier.dispose();
  }
}

class TabManagerScreen extends StatefulWidget {
  final ProjectRepository claudeRepository;
  final CodexRepository codexRepository;
  final VoidCallback? onLogout;
  final Future<void> Function(String)? onApiUrlChanged;

  const TabManagerScreen({
    super.key,
    required this.claudeRepository,
    required this.codexRepository,
    this.onLogout,
    this.onApiUrlChanged,
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

  Future<void> _addHomeTab() async {
    // 从 ConfigService 读取当前的后端选择，作为标签页的初始模式
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;
    final initialMode = preferredBackend == 'codex' ? AgentMode.codex : AgentMode.claudeCode;

    final newTab = TabInfo(
      id: 'home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: _openChatInCurrentTab,
        onNavigate: _replaceCurrentTab,
        onLogout: widget.onLogout,
        onGoBack: _goBackInCurrentTab, // 传递返回回调
        initialMode: initialMode, // 传入初始模式，锁定标签页的后端选择
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
    final currentTab = _tabs[_currentIndex];

    final newTab = TabInfo(
      id: id,
      type: TabType.home, // 保持为 home 类型，因为不是聊天
      title: title,
      content: content,
      previousContent: currentTab.content, // 保存当前内容，用于返回
      previousTitle: currentTab.title, // 保存当前标题
      // 保存更深一层的历史（如果当前tab已经有历史的话）
      previousPreviousContent: currentTab.previousContent,
      previousPreviousTitle: currentTab.previousTitle,
    );

    setState(() {
      _tabs[_currentIndex] = newTab;
    });
  }

  void _goBackInCurrentTab() {
    final currentTab = _tabs[_currentIndex];

    // 找到最底层的主页内容
    Widget? targetContent = currentTab.previousContent;
    String? targetTitle = currentTab.previousTitle;

    // 如果有更深层的历史，一直往下找到最底层
    if (currentTab.previousPreviousContent != null) {
      targetContent = currentTab.previousPreviousContent;
      targetTitle = currentTab.previousPreviousTitle;
    }

    // 如果有之前的内容，恢复到最底层的内容（主页）
    if (targetContent != null) {
      final restoredTab = TabInfo(
        id: 'home_${DateTime.now().millisecondsSinceEpoch}',
        type: TabType.home,
        title: targetTitle ?? '主页',
        content: targetContent,
        // 不再保留历史，直接回到主页
      );

      setState(() {
        _tabs[_currentIndex] = restoredTab;
      });
    }
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
        onBack: () => _handleBackToHome(targetIndex),
      );
    }

    // 替换当前标签页（需要先dispose旧的）
    setState(() {
      // 保存当前界面及其历史，以便返回时恢复
      final currentTab = _tabs[_currentIndex];
      final previousContent = currentTab.content;
      final previousTitle = currentTab.title;
      final previousPreviousContent = currentTab.previousContent;
      final previousPreviousTitle = currentTab.previousTitle;

      currentTab.dispose();
      _tabs[_currentIndex] = TabInfo(
        id: 'chat_$sessionId',
        type: TabType.chat,
        title: sessionName,
        content: wrappedWidget,
        previousContent: previousContent,
        previousTitle: previousTitle,
        // 保留更深层次的历史
        previousPreviousContent: previousPreviousContent,
        previousPreviousTitle: previousPreviousTitle,
      );
    });
  }

  void _handleBackToHome(int tabIndex) async {
    final currentTab = _tabs[tabIndex];

    // 如果有保存的上一个界面，则恢复到上一个界面
    if (currentTab.previousContent != null) {
      final newTab = TabInfo(
        id: 'home_${DateTime.now().millisecondsSinceEpoch}',
        type: TabType.home,
        title: currentTab.previousTitle ?? '主页',
        content: currentTab.previousContent!,
        // 保留更深层次的历史，这样从会话列表还能返回到主页
        previousContent: currentTab.previousPreviousContent,
        previousTitle: currentTab.previousPreviousTitle,
      );

      setState(() {
        _tabs[tabIndex].dispose();
        _tabs[tabIndex] = newTab;
      });
      return;
    }

    // 如果没有保存的上一个界面，则创建新的主页
    // 从 ConfigService 读取当前的后端选择，作为标签页的初始模式
    final configService = await ConfigService.getInstance();
    final preferredBackend = configService.preferredBackend;
    final initialMode = preferredBackend == 'codex' ? AgentMode.codex : AgentMode.claudeCode;

    final newTab = TabInfo(
      id: 'home_${DateTime.now().millisecondsSinceEpoch}',
      type: TabType.home,
      title: '主页',
      content: HomeScreen(
        claudeRepository: widget.claudeRepository,
        codexRepository: widget.codexRepository,
        onOpenChat: _openChatInCurrentTab,
        onNavigate: _replaceCurrentTab,
        onLogout: widget.onLogout,
        onGoBack: _goBackInCurrentTab, // 传递返回回调
        initialMode: initialMode,
      ),
    );

    setState(() {
      _tabs[tabIndex].dispose();
      _tabs[tabIndex] = newTab;
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
    print('DEBUG: _handleMessageComplete called, tabIndex=$tabIndex, currentIndex=$_currentIndex');

    // 检查是否启用了通知
    final settingsService = AppSettingsService();
    print('DEBUG: notificationsEnabled=${settingsService.notificationsEnabled}');

    if (!settingsService.notificationsEnabled) {
      print('DEBUG: Notifications disabled, skipping');
      return; // 通知已禁用，不显示
    }

    // 播放通知提示音
    final soundService = NotificationSoundService();
    soundService.setVolume(settingsService.notificationVolume);
    soundService.playNotificationSound();

    // 如果是当前标签页，显示简短的 SnackBar 提示
    if (tabIndex == _currentIndex && tabIndex < _tabs.length) {
      print('DEBUG: Showing completion notification for current tab');
      if (context.mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Text('消息已完成'),
              ],
            ),
            backgroundColor: primaryColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 100,
              left: 16,
              right: 16,
            ),
          ),
        );
      }
      return;
    }

    // 后台标签页的通知（保持原有逻辑）
    if (tabIndex != _currentIndex && tabIndex < _tabs.length) {
      print('DEBUG: Showing notification for background tab');
      setState(() {
        _tabs[tabIndex].hasNewReply = true;
        _tabs[tabIndex].hasNewReplyNotifier.value = true;
      });

      // 显示通知界面
      if (context.mounted) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        // 显示顶部MaterialBanner通知（比SnackBar更显眼）
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: primaryColor.withOpacity(0.95),
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

  // 获取AppBar标题
  String _getAppBarTitle() {
    if (_tabs.isEmpty) return 'CodeAgent Hub';

    final currentTab = _tabs[_currentIndex];

    // 如果是主页标签
    if (currentTab.type == TabType.home) {
      final content = currentTab.content;

      // 检查是否是 SessionListScreen（项目的会话列表）
      if (content is SessionListScreen) {
        // 获取 SessionListScreen 的 repository 来判断模式
        if (content.repository is CodexRepository) {
          return 'Codex';
        } else {
          return 'Claude Code';
        }
      }

      // 如果是 HomeScreen，显示 CodeAgent Hub
      return 'CodeAgent Hub';
    }

    // 如果是对话标签，检查是哪个后端
    if (currentTab.type == TabType.chat && currentTab.content is ChatScreen) {
      final chatScreen = currentTab.content as ChatScreen;
      // 判断repository类型
      if (chatScreen.repository is ApiCodexRepository) {
        return 'Codex';
      } else {
        return 'Claude Code';
      }
    }

    return 'CodeAgent Hub';
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: cardColor,
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
                                          color: primaryColor,
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
                                        color: primaryColor,
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
                      left: BorderSide(color: dividerColor, width: 1),
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
