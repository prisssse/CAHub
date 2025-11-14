import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/session_settings.dart';
import '../repositories/session_repository.dart';
import '../widgets/message_bubble.dart';
import '../core/constants/colors.dart';
import 'session_settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final Session session;
  final SessionRepository repository;

  const ChatScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isSending = false;
  late SessionSettings _settings;
  MessageStats? _lastMessageStats; // 最后一条消息的统计信息
  bool _showStats = false; // 是否显示统计信息

  @override
  void initState() {
    super.initState();
    _settings = SessionSettings(
      sessionId: widget.session.id,
      cwd: widget.session.cwd,
    );
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await widget.repository.getSessionMessages(widget.session.id);
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
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
    });
    _textController.clear();
    _scrollToBottom();

    // Track current assistant message by ID (for multi-turn support)
    final assistantMessagesByIdIndex = <String, int>{}; // message.id -> index in _messages

    try {
      await for (var event in widget.repository.sendMessageStream(
        sessionId: widget.session.id,
        content: text,
        settings: _settings,
      )) {
        if (event.error != null) {
          setState(() => _isSending = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('发送失败: ${event.error}')),
            );
          }
          return;
        }

        if (event.stats != null) {
          // 保存统计信息
          setState(() {
            _lastMessageStats = event.stats;
            _showStats = true; // 自动显示统计信息
          });
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
              setState(() {
                _messages[index] = partial;
              });
            }
          } else {
            // Add new assistant message
            setState(() {
              _messages.add(partial);
              assistantMessagesByIdIndex[messageId] = _messages.length - 1;
            });
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
              setState(() {
                _messages[index] = final_;
              });
            }
          } else {
            // Fallback: add final message if no partial was received
            setState(() {
              _messages.add(final_);
              assistantMessagesByIdIndex[messageId] = _messages.length - 1;
            });
          }
          _scrollToBottom();
        }

        if (event.isDone) {
          setState(() => _isSending = false);
          return;
        }
      }

      setState(() => _isSending = false);
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
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

  Future<void> _clearMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除消息'),
        content: const Text('确定要清除所有消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.repository.clearSessionMessages(widget.session.id);
      setState(() {
        _messages.clear();
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: '会话设置',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearMessages,
            tooltip: '清除消息',
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
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
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
