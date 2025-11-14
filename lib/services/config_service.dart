import 'dart:io';
import 'dart:convert';

class ConfigService {
  static ConfigService? _instance;
  static const String _fileName = 'app_config.json';

  String _apiBaseUrl = 'http://127.0.0.1:8207'; // 默认值

  ConfigService._();

  static Future<ConfigService> getInstance() async {
    if (_instance == null) {
      _instance = ConfigService._();
      await _instance!._loadConfig();
    }
    return _instance!;
  }

  // 获取配置文件的完整路径
  String _getConfigFilePath() {
    if (Platform.isAndroid) {
      // Android: 使用应用的data目录
      return '/data/data/com.example.cc_mobile/files/$_fileName';
    } else if (Platform.isWindows) {
      // Windows: 使用APPDATA目录
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final dir = Directory('$appData\\CCMobile');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return '$appData\\CCMobile\\$_fileName';
      }
    }
    // 其他平台或无法获取路径时，使用当前目录
    return _fileName;
  }

  String get apiBaseUrl => _apiBaseUrl;

  Future<void> setApiBaseUrl(String url) async {
    print('DEBUG ConfigService: Setting API URL to: $url');
    _apiBaseUrl = url;
    await _saveConfig();
    print('DEBUG ConfigService: API URL saved, current value: $_apiBaseUrl');
  }

  // 重新加载配置
  Future<void> reload() async {
    await _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final filePath = _getConfigFilePath();
      print('DEBUG ConfigService: Loading config from: $filePath');
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        print('DEBUG ConfigService: Loaded config content: $content');
        final json = jsonDecode(content) as Map<String, dynamic>;
        _apiBaseUrl = json['apiBaseUrl'] as String? ?? 'http://127.0.0.1:8207';
        print('DEBUG ConfigService: Loaded API URL: $_apiBaseUrl');
      } else {
        print('DEBUG ConfigService: Config file does not exist at $filePath, using default');
        _apiBaseUrl = 'http://127.0.0.1:8207';
      }
    } catch (e) {
      print('DEBUG ConfigService: Error loading config: $e');
      // 如果加载失败，使用默认值
      _apiBaseUrl = 'http://127.0.0.1:8207';
    }
  }

  Future<void> _saveConfig() async {
    try {
      final filePath = _getConfigFilePath();
      final file = File(filePath);
      final json = {
        'apiBaseUrl': _apiBaseUrl,
      };
      final jsonString = jsonEncode(json);
      print('DEBUG ConfigService: Saving config: $jsonString to: $filePath');
      await file.writeAsString(jsonString);
      print('DEBUG ConfigService: Config saved successfully to: ${file.path}');
    } catch (e) {
      print('DEBUG ConfigService: Error saving config: $e');
      // 保存失败静默处理
    }
  }
}
