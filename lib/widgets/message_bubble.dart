import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/platform_helper.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;
    final appColors = context.appColors;

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: appColors.toolBackground.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 48 : 16,
          right: isUser ? 16 : 48,
          top: 8,
          bottom: 8,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? appColors.userBubble : appColors.claudeBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...message.contentBlocks.map((block) => _buildContentBlock(context, block)),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                color: appColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentBlock(BuildContext context, ContentBlock block) {
    switch (block.type) {
      case ContentBlockType.text:
        return _buildTextBlock(context, block.text ?? '');

      case ContentBlockType.thinking:
        return _buildThinkingBlock(context, block.thinking ?? '');

      case ContentBlockType.toolUse:
        return _buildToolUseBlock(
          context,
          name: block.name ?? 'unknown',
          input: block.input ?? {},
        );

      case ContentBlockType.toolResult:
        return _buildToolResultBlock(
          context,
          content: block.content,
          isError: block.isError ?? false,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextBlock(BuildContext context, String text) {
    if (text.isEmpty) return const SizedBox.shrink();

    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final appColors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MarkdownBody(
        data: text,
        // 必须设为 false，让外层的 SelectionArea 统一管理选择
        // 如果设为 true，会创建独立的选择区域，导致无法跨行/跨消息选择
        selectable: false,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            color: textPrimary,
            fontSize: 15,
            height: 1.5,
          ),
          code: TextStyle(
            backgroundColor: appColors.codeBackground,
            color: textPrimary,
            fontSize: 14,
          ),
          codeblockDecoration: BoxDecoration(
            color: appColors.codeBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          blockquote: TextStyle(
            color: appColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingBlock(BuildContext context, String thinking) {
    if (thinking.isEmpty) return const SizedBox.shrink();

    final appColors = context.appColors;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appColors.toolBackground.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, size: 16, color: appColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '思考中',
                style: TextStyle(
                  color: appColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            thinking,
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolUseBlock(BuildContext context, {required String name, required Map<String, dynamic> input}) {
    final appColors = context.appColors;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appColors.toolBackground.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build, size: 16, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                '工具调用: $name',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (input.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: appColors.codeBackground,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                JsonEncoder.withIndent('  ').convert(input),
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolResultBlock(BuildContext context, {required dynamic content, required bool isError}) {
    final displayContent = content?.toString() ?? '';
    if (displayContent.isEmpty) return const SizedBox.shrink();

    final appColors = context.appColors;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError
            ? errorColor.withOpacity(0.1)
            : appColors.toolBackground.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? errorColor.withOpacity(0.3)
              : dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                size: 16,
                color: isError ? errorColor : appColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                isError ? '工具错误' : '工具结果',
                style: TextStyle(
                  color: isError ? errorColor : appColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            displayContent,
            style: TextStyle(
              color: appColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
