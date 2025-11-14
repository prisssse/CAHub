/// 应用设置服务（内存存储）
class AppSettingsService {
  static final AppSettingsService _instance = AppSettingsService._internal();

  factory AppSettingsService() => _instance;

  AppSettingsService._internal();

  // 设置项
  bool _notificationsEnabled = true; // 默认开启通知
  bool _darkModeEnabled = false;

  // Getters
  bool get notificationsEnabled => _notificationsEnabled;
  bool get darkModeEnabled => _darkModeEnabled;

  // Setters
  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
  }

  void setDarkModeEnabled(bool value) {
    _darkModeEnabled = value;
  }
}
