import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'config/app_config.dart';
import 'screens/tab_manager_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/api_service.dart';
import 'services/codex_api_service.dart';
import 'services/auth_service.dart';
import 'services/config_service.dart';
import 'services/app_settings_service.dart';
import 'repositories/api_project_repository.dart';
import 'repositories/api_codex_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 window_manager
  await windowManager.ensureInitialized();
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
  final _settingsService = AppSettingsService();
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _settingsService.addListener(_onSettingsChanged);
    _initializeServices();
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {}); // 重建应用以应用新设置
    _updateWindowTitleBarColor(); // 更新标题栏颜色
  }

  Future<void> _updateWindowTitleBarColor() async {
    final isDark = _settingsService.darkModeEnabled;
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFFFFBF5);

    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );

    // 设置标题栏背景色
    await windowManager.setBackgroundColor(backgroundColor);
  }

  Future<void> _initializeServices() async {
    try {
      await _settingsService.initialize(); // 先初始化设置
      _authService = await AuthService.getInstance();
      _configService = await ConfigService.getInstance();

      // 初始化标题栏颜色
      await _updateWindowTitleBarColor();
    } catch (e) {
      print('Error initializing services: $e');
    }
    setState(() {
      _isInitializing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用AppTheme.generate生成动态主题
    final theme = AppTheme.generate(
      isDark: _settingsService.darkModeEnabled,
      fontFamily: _settingsService.fontFamily.fontFamily,
      fontScale: _settingsService.fontSize.scale,
    );

    return MaterialApp(
      title: AppConfig.appName,
      theme: theme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // 应用全局字号缩放
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaleFactor: _settingsService.fontSize.scale,
          ),
          child: child!,
        );
      },
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

    // Create Claude Code services
    final apiService = ApiService(
      baseUrl: apiUrl,
      authService: _authService,
    );
    final claudeRepository = ApiProjectRepository(apiService);

    // Create Codex services
    final codexApiService = CodexApiService(
      baseUrl: apiUrl,
      authService: _authService,
    );
    final codexRepository = ApiCodexRepository(codexApiService);

    return TabManagerScreen(
      claudeRepository: claudeRepository,
      codexRepository: codexRepository,
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
