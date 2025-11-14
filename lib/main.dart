import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'config/app_config.dart';
import 'screens/tab_manager_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/config_service.dart';
import 'repositories/api_project_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AuthService? _authService;
  ConfigService? _configService;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      _authService = await AuthService.getInstance();
      _configService = await ConfigService.getInstance();
    } catch (e) {
      print('Error initializing services: $e');
    }
    setState(() {
      _isInitializing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: _isInitializing
          ? Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _authService?.isLoggedIn == true
              ? _buildMainApp()
              : _buildLoginPrompt(),
    );
  }

  Widget _buildMainApp() {
    final apiUrl = _configService?.apiBaseUrl ?? AppConfig.apiBaseUrl;
    print('DEBUG: Creating ApiService with URL: $apiUrl');

    final apiService = ApiService(
      baseUrl: apiUrl,
      authService: _authService,
    );
    final repository = ApiProjectRepository(apiService);

    return TabManagerScreen(
      repository: repository,
      onLogout: () {
        setState(() {});
      },
    );
  }

  Widget _buildLoginPrompt() {
    return LoginScreen(
      onLoginSuccess: () async {
        // 登录成功后重新加载配置并刷新UI
        _configService = await ConfigService.getInstance();
        await _configService?.reload();
        print('DEBUG main.dart: ConfigService reloaded, URL is now: ${_configService?.apiBaseUrl}');
        setState(() {});
      },
    );
  }
}
