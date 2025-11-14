import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/app_settings_service.dart';
import '../../services/notification_sound_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsService = AppSettingsService();
  final _soundService = NotificationSoundService();
  late bool _darkMode;
  late bool _notifications;
  late double _notificationVolume;
  late FontFamilyOption _fontFamily;
  String _apiEndpoint = 'http://192.168.31.99:8207';

  @override
  void initState() {
    super.initState();
    // 从服务中加载设置
    _darkMode = _settingsService.darkModeEnabled;
    _notifications = _settingsService.notificationsEnabled;
    _notificationVolume = _settingsService.notificationVolume;
    _fontFamily = _settingsService.fontFamily;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final dividerColor = Theme.of(context).dividerColor;
    final cardColor = Theme.of(context).cardColor;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle(context, '外观'),
          _buildSettingCard(context,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    '深色模式',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '切换浅色/深色主题',
                    style: TextStyle(
                      fontSize: 13,
                      color: appColors.textSecondary,
                    ),
                  ),
                  value: _darkMode,
                  onChanged: (value) {
                    setState(() {
                      _darkMode = value;
                    });
                    _settingsService.setDarkModeEnabled(value);
                  },
                  activeColor: primaryColor,
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  title: Text(
                    '字体',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    _fontFamily.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: appColors.textSecondary,
                      fontFamily: _fontFamily.fontFamily,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: () => _showFontPicker(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '通知'),
          _buildSettingCard(context,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    '启用通知',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '后台标签页有新回复时显示通知',
                    style: TextStyle(
                      fontSize: 13,
                      color: appColors.textSecondary,
                    ),
                  ),
                  value: _notifications,
                  onChanged: (value) {
                    setState(() {
                      _notifications = value;
                    });
                    _settingsService.setNotificationsEnabled(value);
                  },
                  activeColor: primaryColor,
                ),
                if (_notifications) ...[
                  Divider(height: 1, color: dividerColor),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '通知音量',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: appColors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                _soundService.setVolume(_notificationVolume);
                                _soundService.playNotificationSound();
                              },
                              icon: Icon(Icons.volume_up, size: 18),
                              label: Text('测试'),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.volume_mute, size: 20, color: appColors.textTertiary),
                            Expanded(
                              child: Slider(
                                value: _notificationVolume,
                                min: 0.0,
                                max: 1.0,
                                divisions: 10,
                                label: '${(_notificationVolume * 100).round()}%',
                                activeColor: primaryColor,
                                onChanged: (value) {
                                  setState(() {
                                    _notificationVolume = value;
                                  });
                                  _settingsService.setNotificationVolume(value);
                                },
                              ),
                            ),
                            Icon(Icons.volume_up, size: 20, color: appColors.textTertiary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, 'API 配置'),
          _buildSettingCard(context,
            child: ListTile(
              title: Text(
                'API 地址',
                style: TextStyle(
                  fontSize: 16,
                  color: textPrimary,
                ),
              ),
              subtitle: Text(
                _apiEndpoint,
                style: TextStyle(
                  fontSize: 13,
                  color: appColors.textSecondary,
                ),
              ),
              trailing: Icon(
                Icons.edit,
                color: primaryColor,
              ),
              onTap: () => _showApiEndpointDialog(),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '关于'),
          _buildSettingCard(context,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '版本',
                    style: TextStyle(
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  trailing: Text(
                    '1.0.0',
                    style: TextStyle(
                      fontSize: 14,
                      color: appColors.textSecondary,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: dividerColor,
                ),
                ListTile(
                  title: Text(
                    '隐私政策',
                    style: TextStyle(
                      fontSize: 16,
                      color: appColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    '功能开发中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: appColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: appColors.textTertiary,
                  ),
                  onTap: null, // 禁用
                ),
                Divider(
                  height: 1,
                  color: dividerColor,
                ),
                ListTile(
                  title: Text(
                    '服务条款',
                    style: TextStyle(
                      fontSize: 16,
                      color: appColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    '功能开发中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: appColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: appColors.textTertiary,
                  ),
                  onTap: null, // 禁用
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '账户'),
          _buildSettingCard(context,
            child: ListTile(
              leading: Icon(
                Icons.logout,
                color: errorColor,
              ),
              title: Text(
                '退出登录',
                style: TextStyle(
                  fontSize: 16,
                  color: errorColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => _handleLogout(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final errorColor = Theme.of(context).colorScheme.error;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text(
            '确认退出',
            style: TextStyle(color: textPrimary),
          ),
          content: Text(
            '确定要退出登录吗？',
            style: TextStyle(color: appColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '取消',
                style: TextStyle(color: appColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                '退出',
                style: TextStyle(color: errorColor),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final authService = await AuthService.getInstance();
        await authService.logout();

        if (mounted) {
          // 关闭设置页面
          Navigator.pop(context);
          // 调用回调通知父组件
          widget.onLogout?.call();
        }
      } catch (e) {
        if (mounted) {
          final errorColor = Theme.of(context).colorScheme.error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('退出失败: $e'),
              backgroundColor: errorColor,
            ),
          );
        }
      }
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.appColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingCard(BuildContext context, {required Widget child}) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }

  void _showApiEndpointDialog() {
    final controller = TextEditingController(text: _apiEndpoint);
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final dividerColor = Theme.of(context).dividerColor;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text(
            'API 地址',
            style: TextStyle(color: textPrimary),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: textPrimary),
            decoration: InputDecoration(
              hintText: '输入 API 地址',
              hintStyle: TextStyle(color: appColors.textTertiary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: primaryColor),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '取消',
                style: TextStyle(color: appColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _apiEndpoint = controller.text);
                Navigator.pop(context);
              },
              child: Text(
                '保存',
                style: TextStyle(color: primaryColor),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFontPicker() {
    showDialog(
      context: context,
      builder: (context) {
        final appColors = context.appColors;
        final textPrimary = Theme.of(context).textTheme.bodyLarge!.color!;
        final primaryColor = Theme.of(context).colorScheme.primary;
        final cardColor = Theme.of(context).cardColor;

        return AlertDialog(
          backgroundColor: cardColor,
          title: Text(
            '选择字体',
            style: TextStyle(color: textPrimary),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: FontFamilyOption.values.length,
              itemBuilder: (context, index) {
                final option = FontFamilyOption.values[index];
                final isSelected = _fontFamily == option;
                return ListTile(
                  title: Text(
                    option.label,
                    style: TextStyle(
                      color: textPrimary,
                      fontFamily: option.fontFamily,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '这是示例文本 1234',
                    style: TextStyle(
                      color: appColors.textSecondary,
                      fontFamily: option.fontFamily,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: primaryColor)
                      : null,
                  onTap: () {
                    setState(() {
                      _fontFamily = option;
                    });
                    _settingsService.setFontFamily(option);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '关闭',
                style: TextStyle(color: appColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }
}
