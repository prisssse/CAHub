import 'package:flutter/material.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';
import '../core/constants/colors.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSampleMessages();
  }

  void _loadSampleMessages() {
    setState(() {
      _messages.addAll([
        Message.system('Chat started'),
        Message.user('Hello! Can you help me understand how to use Flutter?'),
        Message.assistant(
          'Of course! I\'d be happy to help you with Flutter.\n\n'
          'Flutter is Google\'s UI toolkit for building natively compiled applications. Here are some key concepts:\n\n'
          '1. **Widgets**: Everything in Flutter is a widget\n'
          '2. **State Management**: Flutter provides multiple ways to manage state\n'
          '3. **Hot Reload**: You can see changes instantly\n\n'
          '```dart\n'
          'class MyApp extends StatelessWidget {\n'
          '  @override\n'
          '  Widget build(BuildContext context) {\n'
          '    return MaterialApp(\n'
          '      home: Scaffold(\n'
          '        appBar: AppBar(title: Text(\'Hello\')),\n'
          '      ),\n'
          '    );\n'
          '  }\n'
          '}\n'
          '```\n\n'
          'What specific aspect would you like to learn more about?'
        ),
        Message.user('That\'s helpful! What about state management?'),
        Message.assistant(
          'Great question! Flutter offers several state management solutions:\n\n'
          '**Built-in Options:**\n'
          '- `setState()`: For simple, local state\n'
          '- `InheritedWidget`: For passing data down the widget tree\n\n'
          '**Popular Packages:**\n'
          '- **Provider**: Simple and recommended by Google\n'
          '- **Riverpod**: Modern, type-safe, testable\n'
          '- **Bloc**: Event-driven, great for complex apps\n'
          '- **GetX**: All-in-one solution\n\n'
          'For beginners, I recommend starting with `setState()` and then moving to Provider or Riverpod as your app grows.'
        ),
      ]);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _handleSubmit(String text) {
    if (text.trim().isEmpty) return;

    final userMessage = Message.user(text);
    setState(() {
      _messages.add(userMessage);
    });
    _textController.clear();
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 500), () {
      final response = Message.assistant(
        'This is a demo response. In the full version, this will connect to Claude Code API and stream real responses.'
      );
      setState(() {
        _messages.add(response);
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claude Code Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(Message.system('Chat cleared'));
              });
            },
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              border: Border(
                top: BorderSide(
                  color: AppColors.divider,
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleSubmit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _handleSubmit(_textController.text),
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
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
