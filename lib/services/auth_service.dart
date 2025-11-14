import 'dart:io';
import 'dart:convert';

class AuthService {
  static const String _fileName = 'user_auth.json';
  static AuthService? _instance;

  String? _username;
  String? _password; // 只在内存中保存，不持久化
  bool _isInitialized = false;

  AuthService._();

  static Future<AuthService> getInstance() async {
    if (_instance == null) {
      _instance = AuthService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    if (!_isInitialized) {
      await _loadUsername();
      _isInitialized = true;
    }
  }

  String _getAuthFilePath() {
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

  Future<void> _loadUsername() async {
    try {
      final filePath = _getAuthFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = json.decode(contents) as Map<String, dynamic>;
        _username = data['username'] as String?;
        print('DEBUG AuthService: Loaded username from: $filePath');
        // 不加载密码，只加载用户名
      }
    } catch (e) {
      print('Error loading username: $e');
    }
  }

  Future<void> _saveUsername() async {
    try {
      final filePath = _getAuthFilePath();
      final file = File(filePath);
      await file.writeAsString(json.encode({
        'username': _username,
      }));
      print('DEBUG AuthService: Saved username to: $filePath');
    } catch (e) {
      print('Error saving username: $e');
    }
  }

  // 设置登录凭证（密码只保存在内存中）
  void setCredentials(String username, String password) {
    _username = username;
    _password = password;
  }

  // 保存用户名（供下次自动填充）
  Future<void> saveUsername(String username) async {
    _username = username;
    await _saveUsername();
  }

  // 登出（只清除密码，保留用户名供下次自动填充）
  Future<void> logout() async {
    _password = null; // 只清除密码
    // 保留 _username 和文件，这样下次启动时可以自动填充用户名
  }

  // 检查是否已登录（需要同时有用户名和密码）
  bool get isLoggedIn => _username != null && _password != null;

  // 获取保存的用户名（用于自动填充）
  String? get savedUsername => _username;

  // 获取用户名
  String? get username => _username;

  // 获取密码（用于 HTTP Basic Auth）
  String? get password => _password;

  // 获取 Basic Auth header 值
  String? get basicAuthHeader {
    if (_username == null || _password == null) return null;
    final credentials = '$_username:$_password';
    final encoded = base64Encode(utf8.encode(credentials));
    return 'Basic $encoded';
  }
}
