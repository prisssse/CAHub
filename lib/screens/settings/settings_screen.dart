import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../services/app_settings.dart';
import '../../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  late bool _darkMode;
  late bool _notifications;
  late String _apiEndpoint;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _settings = await AppSettings.load();
    setState(() {
      _darkMode = _settings.darkMode;
      _notifications = _settings.notifications;
      _apiEndpoint = _settings.apiEndpoint;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('设置'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                '切换到深色主题',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              value: _darkMode,
              onChanged: (value) async {
                setState(() => _darkMode = value);
                await _settings.setDarkMode(value);
                if (mounted) {
                  MyApp.of(context)?.toggleDarkMode(value);
                }
              },
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
                '接收新消息通知',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              value: _notifications,
              onChanged: (value) async {
                setState(() => _notifications = value);
                await _settings.setNotifications(value);
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () {
                    // TODO: Show privacy policy
                  },
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
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () {
                    // TODO: Show terms of service
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
            onPressed: () async {
              final newEndpoint = controller.text.trim();
              if (newEndpoint.isNotEmpty) {
                setState(() => _apiEndpoint = newEndpoint);
                await _settings.setApiEndpoint(newEndpoint);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('API 地址已保存，请重启应用以生效'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
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
