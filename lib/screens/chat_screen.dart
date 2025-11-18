import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/session_settings.dart';
import '../models/codex_user_settings.dart';
import '../widgets/message_bubble.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/platform_helper.dart';
import '../repositories/api_codex_repository.dart';
import '../services/session_settings_service.dart';
import '../services/app_settings_service.dart';
import 'session_settings_screen.dart';
import 'codex_session_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final Session session;
  final dynamic repository; // Supports both SessionRepository and CodexRepository
  final VoidCallback? onMessageComplete; // 消息完成回调，用于通知标签页
  final ValueNotifier<bool>? hasNewReplyNotifier; // 新回复通知器，用于显示AppBar提示
  final VoidCallback? onBack; // 返回按钮回调，用于返回项目列表

  const ChatScreen({
    super.key,
    required this.session,
    required this.repository,
    this.onMessageComplete,
    this.hasNewReplyNotifier,
    this.onBack,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin {
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isSending = false;
  SessionSettings? _settings;
  CodexUserSettings? _codexSettings; // Codex 设置（仅当使用 Codex 时）
  MessageStats? _lastMessageStats; // 最后一条消息的统计信息
  bool _showStats = false; // 是否显示统计信息
  bool _userScrolling = false; // 用户是否正在手动滚动
  late Session _currentSession; // 当前session，可能在第一次发送消息时更新

  // 节流相关 - 优化流式传输UI更新
  DateTime? _lastUpdateTime;
  bool _pendingUpdate = false;

  // 消息导航相关
  int _currentUserMessageIndex = -1; // 当前定位到的用户消息索引（从下往上数）

  // 获取最终的 hideToolCalls 设置（优先使用全局设置）
  bool get _effectiveHideToolCalls {
    final appSettingsService = AppSettingsService();
    final globalHideToolCalls = appSettingsService.hideToolCalls;

    // 全局设置优先
    if (globalHideToolCalls) {
      return true;
    }

    // 否则使用会话设置
    if (widget.repository is ApiCodexRepository) {
      return _codexSettings?.hideToolCalls ?? false;
    } else {
      return _settings?.hideToolCalls ?? false;
    }
  }

  @override
  bool get wantKeepAlive => true; // 保持状态，防止切换标签时丢失消息

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session; // 初始化为widget的session
    _loadSavedSettings(); // 加载保存的设置
    // 监听用户手动滚动
    _scrollController.addListener(_onScroll);
    _loadMessages();
    _loadCodexSettingsIfNeeded();
  }

  // 加载保存的设置
  Future<void> _loadSavedSettings() async {
    final settingsService = SessionSettingsService();
    await settingsService.initialize();

    if (widget.repository is ApiCodexRepository) {
      // 加载 Codex 设置
      final savedSettings = settingsService.getCodexSessionSettings(widget.session.id);
      if (savedSettings != null && mounted) {
        setState(() {
          _codexSettings = savedSettings;
        });
      }
    } else {
      // 加载 Claude Code 设置
      final savedSettings = settingsService.getClaudeSessionSettings(widget.session.id);
      if (savedSettings != null) {
        _settings = savedSettings;
      } else {
        // 如果没有保存的设置，尝试使用全局默认项目设置
        final appSettingsService = AppSettingsService();
        await appSettingsService.initialize();
        final defaultSettings = appSettingsService.getDefaultSessionSettingsForNewSession(
          widget.session.id,
          widget.session.cwd,
        );

        _settings = defaultSettings ?? SessionSettings(
          sessionId: widget.session.id,
          cwd: widget.session.cwd,
        );
      }
    }
  }

  Future<void> _loadCodexSettingsIfNeeded() async {
    if (widget.repository is ApiCodexRepository) {
      // 如果已经从本地存储加载了设置，则不再从后端加载
      if (_codexSettings != null) {
        print('DEBUG: Codex settings already loaded from local storage, skipping backend load');
        return;
      }

      try {
        final codexRepo = widget.repository as ApiCodexRepository;
        // 获取当前登录的用户ID
        final userId = codexRepo.apiService.authService?.username ?? 'default';
        final settings = await codexRepo.getUserSettings(userId);
        if (mounted) {
          setState(() {
            _codexSettings = settings;
          });
        }
      } catch (e) {
        print('DEBUG: Failed to load Codex settings: $e');
        // 如果加载失败，使用默认设置
        final codexRepo = widget.repository as ApiCodexRepository;
        final userId = codexRepo.apiService.authService?.username ?? 'default';
        if (mounted) {
          setState(() {
            _codexSettings = CodexUserSettings.defaults(userId);
          });
        }
      }
    }
  }

  void _onScroll() {
    // 检测用户是否在底部附近
    if (_scrollController.hasClients) {
      final isAtBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 50;
      if (isAtBottom && _userScrolling) {
        setState(() => _userScrolling = false);
      }
    }
  }

  // 节流更新UI - 每100ms最多更新一次
  void _throttledUpdate() {
    final now = DateTime.now();
    final shouldUpdate = _lastUpdateTime == null ||
        now.difference(_lastUpdateTime!) >= const Duration(milliseconds: 100);

    if (shouldUpdate) {
      _lastUpdateTime = now;
      _pendingUpdate = false;
      if (mounted) {
        setState(() {}); // 触发UI重建
      }
    } else if (!_pendingUpdate) {
      _pendingUpdate = true;
      // 延迟更新
      final delay = const Duration(milliseconds: 100) -
          now.difference(_lastUpdateTime!);
      Future.delayed(delay, () {
        if (mounted && _pendingUpdate) {
          _lastUpdateTime = DateTime.now();
          _pendingUpdate = false;
          setState(() {});
        }
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      // 只有当用户向上滚动超过一定距离时才打断自动滚动
      if (notification.scrollDelta != null && notification.scrollDelta! < -10) {
        // 向上滚动超过10像素（scrollDelta 为负数）
        if (_scrollController.hasClients) {
          final distanceFromBottom = _scrollController.position.maxScrollExtent -
                                     _scrollController.position.pixels;
          // 只有当离底部超过100像素时才认为用户想查看历史消息
          if (distanceFromBottom > 100 && !_userScrolling) {
            setState(() => _userScrolling = true);
          }
        }
      }
    }
    return false;
  }

  Future<void> _loadMessages() async {
    // 如果session id为空，说明是新session，跳过加载消息
    if (widget.session.id.isEmpty) {
      print('DEBUG ChatScreen: Session ID is empty, skipping message load');
      setState(() => _isLoading = false);
      return;
    }

    print('DEBUG ChatScreen: Loading messages for session ${widget.session.id}');
    setState(() => _isLoading = true);
    try {
      final messages = await widget.repository.getSessionMessages(widget.session.id);
      print('DEBUG ChatScreen: Loaded ${messages.length} messages');
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _isLoading = false;
      });
      // 确保在消息加载后滚动到底部，使用 jumpTo 直接跳转
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomImmediate();
      });
      // 延迟再次确保滚动到底部（给更长时间让消息渲染完成）
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _scrollToBottomImmediate();
        }
      });
    } catch (e) {
      print('DEBUG ChatScreen: Error loading messages: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubmit(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    final userMessage = Message.user(text);
    setState(() {
      _messages.add(userMessage);
      _isSending = true;
      _userScrolling = false; // 重置手动滚动标志，确保新消息能自动滚动
    });
    _textController.clear();
    _scrollToBottom();

    // Track current assistant message by ID (for multi-turn support)
    final assistantMessagesByIdIndex = <String, int>{}; // message.id -> index in _messages

    try {
      // 如果session id为空，传null让API创建新session
      final sessionIdToUse = _currentSession.id.isEmpty ? null : _currentSession.id;
      bool sessionIdUpdated = false; // 标记是否已更新session id

      await for (var event in widget.repository.sendMessageStream(
        sessionId: sessionIdToUse,
        content: text,
        cwd: _currentSession.cwd, // 传递工作目录
        settings: _settings, // Claude Code 设置
        codexSettings: _codexSettings, // Codex 设置
      )) {
        // 捕获新创建的session ID
        if (event.sessionId != null && event.sessionId!.isNotEmpty) {
          if (_currentSession.id.isEmpty && !sessionIdUpdated) {
            // 更新本地session对象
            _currentSession = Session(
              id: event.sessionId!,
              projectId: _currentSession.projectId,
              title: _currentSession.title,
              name: _currentSession.name,
              cwd: _currentSession.cwd,
              createdAt: _currentSession.createdAt,
              updatedAt: DateTime.now(),
              messageCount: _currentSession.messageCount,
            );
            sessionIdUpdated = true;
            print('DEBUG: Updated session ID to ${event.sessionId}');
          }
        }

        if (event.error != null) {
          if (mounted) {
            setState(() => _isSending = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('发送失败: ${event.error}'),
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
          return;
        }

        if (event.stats != null) {
          // 保存统计信息
          if (mounted) {
            setState(() {
              _lastMessageStats = event.stats;
              _showStats = true; // 自动显示统计信息
            });
          }
        }

        if (event.partialMessage != null) {
          final partial = event.partialMessage!;
          final messageId = partial.id;

          if (assistantMessagesByIdIndex.containsKey(messageId)) {
            // Update existing message
            final index = assistantMessagesByIdIndex[messageId]!;
            if (index >= 0 &&
                index < _messages.length &&
                _messages[index].role == MessageRole.assistant) {
              _messages[index] = partial; // 直接更新，不触发setState
              _throttledUpdate(); // 节流更新UI
            }
          } else {
            // Add new assistant message
            _messages.add(partial);
            assistantMessagesByIdIndex[messageId] = _messages.length - 1;
            _throttledUpdate(); // 节流更新UI
          }
          _scrollToBottom();
        }

        if (event.finalMessage != null) {
          final final_ = event.finalMessage!;
          final messageId = final_.id;

          if (assistantMessagesByIdIndex.containsKey(messageId)) {
            // Replace with final message
            final index = assistantMessagesByIdIndex[messageId]!;
            if (index >= 0 &&
                index < _messages.length &&
                _messages[index].role == MessageRole.assistant) {
              if (mounted) {
                setState(() {
                  _messages[index] = final_;
                });
              }
            }
          } else {
            // Fallback: add final message if no partial was received
            if (mounted) {
              setState(() {
                _messages.add(final_);
                assistantMessagesByIdIndex[messageId] = _messages.length - 1;
              });
            }
          }
          _scrollToBottom();
        }

        if (event.isDone) {
          if (mounted) {
            setState(() => _isSending = false);
          }
          // 消息完成，通知标签页
          widget.onMessageComplete?.call();
          return;
        }
      }

      if (mounted) {
        setState(() => _isSending = false);
      }

      // 整个消息流结束后才通知标签页有新回复
      widget.onMessageComplete?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
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

  void _openSettings() async {
    // 检测是否为 Codex 仓库
    final isCodex = widget.repository is ApiCodexRepository;
    print('DEBUG ChatScreen._openSettings: isCodex=$isCodex, repository=${widget.repository.runtimeType}');

    final settingsService = SessionSettingsService();
    await settingsService.initialize();

    if (isCodex) {
      // 打开 Codex 设置
      print('DEBUG ChatScreen._openSettings: Opening Codex settings, _codexSettings=$_codexSettings');
      if (_codexSettings == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('正在加载 Codex 设置...'),
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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CodexSessionSettingsScreen(
            settings: _codexSettings!,
            repository: widget.repository as ApiCodexRepository,
            onSave: (newSettings) async {
              print('DEBUG ChatScreen._openSettings: Codex settings saved: $newSettings');
              // 保存到本地持久化存储
              await settingsService.saveCodexSessionSettings(
                widget.session.id,
                newSettings,
              );
              setState(() {
                _codexSettings = newSettings;
              });
            },
          ),
        ),
      );
    } else {
      // 打开 Claude Code 设置
      print('DEBUG ChatScreen._openSettings: Opening Claude Code settings');

      // 确保 _settings 已初始化
      if (_settings == null) {
        print('ERROR: _settings is null when trying to open settings screen');
        // 创建默认设置
        _settings = SessionSettings(
          sessionId: widget.session.id,
          cwd: widget.session.cwd,
        );
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionSettingsScreen(
            settings: _settings!,
            onSave: (newSettings) async {
              // 保存到本地持久化存储
              await settingsService.saveClaudeSessionSettings(
                widget.session.id,
                newSettings,
              );
              setState(() {
                _settings = newSettings;
              });
            },
          ),
        ),
      );
    }
  }


  // 立即跳转到底部（无动画）
  void _scrollToBottomImmediate() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  // 平滑滚动到底部（仅在用户未手动滚动时）
  void _scrollToBottom() {
    if (_userScrolling) return; // 用户正在手动滚动，不自动滚动

    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients && !_userScrolling) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // 判断消息是否是真正的用户输入消息（排除只包含工具返回结果的消息）
  bool _isRealUserMessage(Message message) {
    if (message.role != MessageRole.user) return false;

    // 检查是否包含文本内容块（不是工具返回结果）
    return message.contentBlocks.any((block) =>
      block.type == ContentBlockType.text &&
      (block.text?.trim().isNotEmpty ?? false)
    );
  }

  // 导航到上一条用户消息（向上）
  void _navigateToPreviousUserMessage() {
    // 找到所有真正的用户消息的索引（排除只有工具返回结果的）
    final userMessageIndices = <int>[];
    for (int i = 0; i < _messages.length; i++) {
      if (_isRealUserMessage(_messages[i])) {
        userMessageIndices.add(i);
      }
    }

    if (userMessageIndices.isEmpty) return;

    // 从当前索引向上找（索引减小）
    if (_currentUserMessageIndex == -1) {
      // 首次点击，从最后一条用户消息开始
      _currentUserMessageIndex = userMessageIndices.length - 1;
    } else if (_currentUserMessageIndex > 0) {
      _currentUserMessageIndex--;
    } else {
      // 已经在第一条，循环到最后一条
      _currentUserMessageIndex = userMessageIndices.length - 1;
    }

    final targetIndex = userMessageIndices[_currentUserMessageIndex];
    _scrollToMessageByIndex(targetIndex);
  }

  // 导航到下一条用户消息（向下）
  void _navigateToNextUserMessage() {
    // 找到所有真正的用户消息的索引（排除只有工具返回结果的）
    final userMessageIndices = <int>[];
    for (int i = 0; i < _messages.length; i++) {
      if (_isRealUserMessage(_messages[i])) {
        userMessageIndices.add(i);
      }
    }

    if (userMessageIndices.isEmpty) return;

    // 从当前索引向下找（索引增大）
    if (_currentUserMessageIndex == -1) {
      // 首次点击，从第一条用户消息开始
      _currentUserMessageIndex = 0;
    } else if (_currentUserMessageIndex < userMessageIndices.length - 1) {
      _currentUserMessageIndex++;
    } else {
      // 已经在最后一条，循环到第一条
      _currentUserMessageIndex = 0;
    }

    final targetIndex = userMessageIndices[_currentUserMessageIndex];
    _scrollToMessageByIndex(targetIndex);
  }

  // 根据消息索引计算并滚动到对应位置（让目标消息显示在屏幕底部）
  void _scrollToMessageByIndex(int messageIndex) {
    if (!_scrollController.hasClients) return;

    // 估算每条消息的平均高度
    const double estimatedMessageHeight = 150.0;

    // 获取屏幕可见高度
    final viewportHeight = _scrollController.position.viewportDimension;

    // 计算目标消息的估算位置
    final targetMessagePosition = messageIndex * estimatedMessageHeight;

    // 计算滚动位置：让目标消息出现在屏幕底部
    // targetMessagePosition 是消息顶部的位置
    // 我们希望消息底部对齐到屏幕底部，所以需要加上消息高度再减去viewport高度
    final scrollPosition = (targetMessagePosition + estimatedMessageHeight - viewportHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    // 滚动到目标位置
    _scrollController.animateTo(
      scrollPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: '返回项目列表',
              )
            : null,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.session.name),
                  Text(
                    widget.session.cwd,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // 显示新回复提示圆点或发送中指示器
            if (widget.hasNewReplyNotifier != null)
              ValueListenableBuilder<bool>(
                valueListenable: widget.hasNewReplyNotifier!,
                builder: (context, hasNewReply, child) {
                  if (hasNewReply || _isSending) {
                    final primaryColor = Theme.of(context).colorScheme.primary;
                    return Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _isSending
                            ? primaryColor.withOpacity(0.8)
                            : primaryColor,
                        shape: BoxShape.circle,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              )
            else if (_isSending)
              Builder(
                builder: (context) {
                  return Container(
                    margin: const EdgeInsets.only(left: 8),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                  );
                },
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: '会话设置',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator()
          else
            Container(height: 4),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : Stack(
                    children: [
                      // 桌面版使用SelectionArea包装，允许自由选择文本
                      PlatformHelper.shouldEnableTextSelection
                          ? SelectionArea(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _handleScrollNotification,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  physics: PlatformHelper.getScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    return MessageBubble(
                                      message: _messages[index],
                                      hideToolCalls: _effectiveHideToolCalls,
                                    );
                                  },
                                ),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              child: ListView.builder(
                                controller: _scrollController,
                                physics: PlatformHelper.getScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  return MessageBubble(
                                    message: _messages[index],
                                    hideToolCalls: _effectiveHideToolCalls,
                                  );
                                },
                              ),
                            ),
                      // 消息导航按钮（在右下角）- 暂时禁用
                      // if (_messages.where((m) => _isRealUserMessage(m)).length > 1)
                      //   _buildMessageNavigationButtons(),
                      // 滚动到底部按钮
                      if (_userScrolling) _buildScrollToBottomButton(),
                    ],
                  ),
          ),
          if (_lastMessageStats != null) _buildStatsPanel(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildStatsPanel() {
    final stats = _lastMessageStats!;
    final appColors = context.appColors;
    final dividerColor = Theme.of(context).dividerColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showStats ? null : 0,
      child: _showStats
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: appColors.toolBackground.withOpacity(0.3),
                border: Border(
                  top: BorderSide(color: dividerColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildStatChip(
                          icon: Icons.token,
                          label: '${stats.totalTokens} tokens',
                          tooltip: 'Input: ${stats.inputTokens ?? 0}, Output: ${stats.outputTokens ?? 0}',
                        ),
                        _buildStatChip(
                          icon: Icons.schedule,
                          label: stats.formattedDuration,
                          tooltip: 'API: ${(stats.durationApiMs / 1000).toStringAsFixed(1)}s',
                        ),
                        if (stats.costUsd != null)
                          _buildStatChip(
                            icon: Icons.attach_money,
                            label: stats.formattedCost,
                          ),
                        if (stats.numTurns > 1)
                          _buildStatChip(
                            icon: Icons.refresh,
                            label: '${stats.numTurns} 轮',
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showStats ? Icons.expand_more : Icons.expand_less,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _showStats = !_showStats;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    String? tooltip,
  }) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final dividerColor = Theme.of(context).dividerColor;
    final textSecondary = context.appColors.textSecondary;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: chip,
      );
    }
    return chip;
  }

  Widget _buildMessageNavigationButtons() {
    final appColors = context.appColors;
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;

    return Positioned(
      right: 16,
      bottom: 88, // 在滚动到底部按钮上方
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 向上按钮（跳转到上一条用户消息）
          Container(
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: dividerColor.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToPreviousUserMessage,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_upward,
                    color: appColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 向下按钮（跳转到下一条用户消息）
          Container(
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: dividerColor.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToNextUserMessage,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_downward,
                    color: appColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomButton() {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Positioned(
      right: 16,
      bottom: 16,
      child: AnimatedOpacity(
        opacity: _userScrolling ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: primaryColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(28),
          elevation: 4,
          child: InkWell(
            onTap: () {
              setState(() => _userScrolling = false);
              _scrollToBottomImmediate();
            },
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_downward,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
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
            '暂无消息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: appColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.repository is ApiCodexRepository
                ? '开始与 Codex 对话'
                : '开始与 Claude Code 对话',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: appColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final cardColor = Theme.of(context).cardColor;
    final dividerColor = Theme.of(context).dividerColor;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final appColors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(
          top: BorderSide(
            color: dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: CallbackShortcuts(
                    bindings: {
                      // Enter 键（不带 Shift）发送消息
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (!_isSending) {
                          _handleSubmit(_textController.text);
                        }
                      },
                      // Shift + Enter 键换行（由 TextField 默认处理）
                    },
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: '输入消息...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      enabled: !_isSending,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _isSending ? appColors.textTertiary : primaryColor,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: _isSending
                      ? null
                      : () => _handleSubmit(_textController.text),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
