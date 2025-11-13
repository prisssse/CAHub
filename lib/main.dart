import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/projects/project_list_screen.dart';
import 'services/api_service.dart';
import 'services/app_settings.dart';
import 'repositories/api_project_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(MyApp(settings: settings));
}

class MyApp extends StatefulWidget {
  final AppSettings settings;

  const MyApp({super.key, required this.settings});

  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MyAppState>();
  }
}

class _MyAppState extends State<MyApp> {
  late bool _darkMode;

  @override
  void initState() {
    super.initState();
    _darkMode = widget.settings.darkMode;
  }

  void toggleDarkMode(bool value) {
    setState(() {
      _darkMode = value;
    });
    widget.settings.setDarkMode(value);
  }

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService(baseUrl: widget.settings.apiEndpoint);
    final repository = ApiProjectRepository(apiService);

    return MaterialApp(
      title: 'Claude Code Mobile',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: ProjectListScreen(
        repository: repository,
      ),
    );
  }
}
