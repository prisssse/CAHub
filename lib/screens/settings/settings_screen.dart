import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../services/auth_service.dart';
import '../../services/app_settings_service.dart';

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
  late bool _darkMode;
  late bool _notifications;
  String _apiEndpoint = 'http://192.168.31.99:8207';

  @override
  void initState() {
    super.initState();
    // 从服务中加载设置
    _darkMode = _settingsService.darkModeEnabled;
    _notifications = _settingsService.notificationsEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('外观'),
          _buildSettingCard(
            child: SwitchListTile(
              title: Text(
                '深色模式',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              subtitle: Text(
                '功能开发中...',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              value: _darkMode,
              onChanged: null, // 禁用开关
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('通知'),
          _buildSettingCard(
            child: SwitchListTile(
              title: Text(
                '启用通知',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                '后台标签页有新回复时显示通知',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              value: _notifications,
              onChanged: (value) {
                setState(() {
                  _notifications = value;
                });
                _settingsService.setNotificationsEnabled(value);
              },
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('API 配置'),
          _buildSettingCard(
            child: ListTile(
              title: Text(
                'API 地址',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                _apiEndpoint,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: Icon(
                Icons.edit,
                color: AppColors.primary,
              ),
              onTap: () => _showApiEndpointDialog(),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('关于'),
          _buildSettingCard(
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '版本',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: Text(
                    '1.0.0',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: AppColors.divider,
                ),
                ListTile(
                  title: Text(
                    '隐私政策',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    '功能开发中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  onTap: null, // 禁用
                ),
                Divider(
                  height: 1,
                  color: AppColors.divider,
                ),
                ListTile(
                  title: Text(
                    '服务条款',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    '功能开发中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  onTap: null, // 禁用
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('账户'),
          _buildSettingCard(
            child: ListTile(
              leading: Icon(
                Icons.logout,
                color: AppColors.error,
              ),
              title: Text(
                '退出登录',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.error,
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
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(
          '确认退出',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '确定要退出登录吗？',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '退出',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('退出失败: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingCard({required Widget child}) {
    return Card(
      color: AppColors.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.divider),
      ),
      child: child,
    );
  }

  void _showApiEndpointDialog() {
    final controller = TextEditingController(text: _apiEndpoint);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text(
          'API 地址',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '输入 API 地址',
            hintStyle: TextStyle(color: AppColors.textTertiary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _apiEndpoint = controller.text);
              Navigator.pop(context);
            },
            child: Text(
              '保存',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
