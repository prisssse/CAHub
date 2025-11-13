import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/projects/project_list_screen.dart';
import 'services/api_service.dart';
import 'repositories/api_project_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use 10.0.2.2 for Android emulator to access host machine's localhost
    final apiService = ApiService(baseUrl: 'http://192.168.31.99:8207');
    final repository = ApiProjectRepository(apiService);

    return MaterialApp(
      title: 'Claude Code Mobile',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: ProjectListScreen(
        repository: repository,
      ),
    );
  }
}
