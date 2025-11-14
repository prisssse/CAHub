import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/session_settings.dart';
import '../repositories/session_repository.dart';
import '../widgets/message_bubble.dart';
import '../core/constants/colors.dart';
import '../core/utils/platform_helper.dart';
import 'session_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final Session session;
  final SessionRepository repository;
  final VoidCallback? onMessageComplete; // 消息完成回调，用于通知标签页
  final ValueNotifier<bool>? hasNewReplyNotifier; // 新回复通知器，用于显示AppBar提示

  const ChatScreen({
    super.key,
    required this.session,
    required this.repository,
    this.onMessageComplete,
    this.hasNewReplyNotifier,
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
  late SessionSettings _settings;
  MessageStats? _lastMessageStats; // 最后一条消息的统计信息
  bool _showStats = false; // 是否显示统计信息
  bool _userScrolling = false; // 用户是否正在手动滚动
  late Session _currentSession; // 当前session，可能在第一次发送消息时更新

  // 节流相关 - 优化流式传输UI更新
  DateTime? _lastUpdateTime;
  bool _pendingUpdate = false;

  @override
  bool get wantKeepAlive => true; // 保持状态，防止切换标签时丢失消息

  @override
  void initState() {
    super.initState();
    _currentSession = widget.session; // 初始化为widget的session
    _settings = SessionSettings(
      sessionId: widget.session.id,
      cwd: widget.session.cwd,
    );
    // 监听用户手动滚动
    _scrollController.addListener(_onScroll);
    _loadMessages();
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
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final messages = await widget.repository.getSessionMessages(widget.session.id);
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
        settings: _settings,
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
              SnackBar(content: Text('发送失败: ${event.error}')),
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
          // 通知标签页有新回复（如果当前不在焦点）
          widget.onMessageComplete?.call();
          return;
        }
      }

      if (mounted) {
        setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionSettingsScreen(
          settings: _settings,
          onSave: (newSettings) {
            setState(() {
              _settings = newSettings;
            });
          },
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用以保持状态
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.session.name),
                  Text(
                    widget.session.cwd,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textSecondary,
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
                    return Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _isSending
                            ? AppColors.primary.withOpacity(0.8)
                            : AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              )
            else if (_isSending)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
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
                                    return MessageBubble(message: _messages[index]);
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
                                  return MessageBubble(message: _messages[index]);
                                },
                              ),
                            ),
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showStats ? null : 0,
      child: _showStats
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.toolBackground.withOpacity(0.3),
                border: Border(
                  top: BorderSide(color: AppColors.divider, width: 1),
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
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
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

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        child: chip,
      );
    }
    return chip;
  }

  Widget _buildScrollToBottomButton() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: AnimatedOpacity(
        opacity: _userScrolling ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: AppColors.primary.withOpacity(0.9),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无消息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始与 Claude Code 对话',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.divider,
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
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
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
              const SizedBox(width: 8),
              Material(
                color: _isSending ? AppColors.textTertiary : AppColors.primary,
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
