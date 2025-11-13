import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/projects/project_list_screen.dart';
import 'repositories/mock_project_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mockRepository = MockProjectRepository();

    return MaterialApp(
      title: 'Claude Code Mobile',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: ProjectListScreen(
        repository: mockRepository,
      ),
    );
  }
}
