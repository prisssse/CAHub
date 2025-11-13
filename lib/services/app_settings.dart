import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const String _keyApiEndpoint = 'api_endpoint';
  static const String _keyDarkMode = 'dark_mode';
  static const String _keyNotifications = 'notifications';

  static const String defaultApiEndpoint = 'http://192.168.31.99:8207';

  final SharedPreferences _prefs;

  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  // API Endpoint
  String get apiEndpoint =>
      _prefs.getString(_keyApiEndpoint) ?? defaultApiEndpoint;

  Future<void> setApiEndpoint(String value) async {
    await _prefs.setString(_keyApiEndpoint, value);
  }

  // Dark Mode
  bool get darkMode => _prefs.getBool(_keyDarkMode) ?? false;

  Future<void> setDarkMode(bool value) async {
    await _prefs.setBool(_keyDarkMode, value);
  }

  // Notifications
  bool get notifications => _prefs.getBool(_keyNotifications) ?? true;

  Future<void> setNotifications(bool value) async {
    await _prefs.setBool(_keyNotifications, value);
  }
}
