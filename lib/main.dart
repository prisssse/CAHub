import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/chat_screen.dart';
import 'models/session.dart';
import 'repositories/mock_session_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mockRepository = MockSessionRepository();
    final testSession = Session(
      id: 'test-session-1',
      projectId: 'test-project-1',
      title: 'Test Session',
      name: 'Test Session',
      cwd: '/test/path',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messageCount: 0,
    );

    return MaterialApp(
      title: 'Claude Code Mobile',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: ChatScreen(
        session: testSession,
        repository: mockRepository,
      ),
    );
  }
}
