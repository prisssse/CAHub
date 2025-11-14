import 'package:flutter/material.dart';

/// 字体选项
enum FontFamilyOption {
  microsoftYaHei('微软雅黑', 'Microsoft YaHei'),
  notoSans('Noto Sans', 'Noto Sans'),
  notoSerifSC('Noto Serif SC', 'Noto Serif SC'),
  system('系统默认', null),
  simSun('宋体', 'SimSun'),
  simHei('黑体', 'SimHei'),
  kaiti('楷体', 'KaiTi'),
  fangSong('仿宋', 'FangSong'),
  consolas('Consolas', 'Consolas'),
  arial('Arial', 'Arial'),
  timesNewRoman('Times New Roman', 'Times New Roman');

  final String label;
  final String? fontFamily;
  const FontFamilyOption(this.label, this.fontFamily);
}

/// 应用设置服务（内存存储）
class AppSettingsService {
  static final AppSettingsService _instance = AppSettingsService._internal();

  factory AppSettingsService() => _instance;

  AppSettingsService._internal();

  // 设置项
  bool _notificationsEnabled = true; // 默认开启通知
  bool _darkModeEnabled = false;
  double _notificationVolume = 0.5; // 通知音量（0.0 - 1.0）
  FontFamilyOption _fontFamily = FontFamilyOption.microsoftYaHei; // 默认微软雅黑

  // 通知回调（当设置变化时）
  final List<VoidCallback> _listeners = [];

  // Getters
  bool get notificationsEnabled => _notificationsEnabled;
  bool get darkModeEnabled => _darkModeEnabled;
  double get notificationVolume => _notificationVolume;
  FontFamilyOption get fontFamily => _fontFamily;

  // Setters
  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _notifyListeners();
  }

  void setDarkModeEnabled(bool value) {
    _darkModeEnabled = value;
    _notifyListeners();
  }

  void setNotificationVolume(double value) {
    _notificationVolume = value.clamp(0.0, 1.0);
    _notifyListeners();
  }

  void setFontFamily(FontFamilyOption value) {
    _fontFamily = value;
    _notifyListeners();
  }

  // 监听器管理
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }
}
