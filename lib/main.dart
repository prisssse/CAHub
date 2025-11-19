import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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

  // 只在桌面平台初始化 window_manager
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
  }

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

  // API services - 保持实例以便动态更新
  ApiService? _apiService;
  CodexApiService? _codexApiService;

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
    // 只在桌面平台设置窗口标题栏
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final isDark = _settingsService.darkModeEnabled;
      final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFFFFBF5);

      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );

      // 设置标题栏背景色
      await windowManager.setBackgroundColor(backgroundColor);
    }
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

    // 如果还没有创建 ApiService 实例，或者 URL 发生变化，则创建/更新
    if (_apiService == null) {
      print('DEBUG: Creating ApiService with URL: $apiUrl');
      _apiService = ApiService(
        baseUrl: apiUrl,
        authService: _authService,
      );
    } else if (_apiService!.baseUrl != apiUrl) {
      print('DEBUG: Updating ApiService URL from ${_apiService!.baseUrl} to $apiUrl');
      _apiService!.updateBaseUrl(apiUrl);
    }

    if (_codexApiService == null) {
      print('DEBUG: Creating CodexApiService with URL: $apiUrl');
      _codexApiService = CodexApiService(
        baseUrl: apiUrl,
        authService: _authService,
      );
    } else if (_codexApiService!.baseUrl != apiUrl) {
      print('DEBUG: Updating CodexApiService URL from ${_codexApiService!.baseUrl} to $apiUrl');
      _codexApiService!.updateBaseUrl(apiUrl);
    }

    final claudeRepository = ApiProjectRepository(_apiService!);
    final codexRepository = ApiCodexRepository(_codexApiService!);

    return TabManagerScreen(
      claudeRepository: claudeRepository,
      codexRepository: codexRepository,
      onLogout: () {
        setState(() {});
      },
      onApiUrlChanged: _handleApiUrlChanged,
    );
  }

  /// 当 API 地址变化时调用此方法
  Future<void> _handleApiUrlChanged(String newUrl) async {
    print('DEBUG: API URL changed to: $newUrl');

    // 更新 ApiService 实例
    _apiService?.updateBaseUrl(newUrl);
    _codexApiService?.updateBaseUrl(newUrl);

    // 触发重建
    setState(() {});
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
