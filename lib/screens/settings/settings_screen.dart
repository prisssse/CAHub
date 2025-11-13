import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  bool _notifications = true;
  String _apiEndpoint = 'http://127.0.0.1:8207';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('Appearance'),
          _buildSettingCard(
            child: SwitchListTile(
              title: Text(
                'Dark Mode',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Switch to dark theme',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              value: _darkMode,
              onChanged: (value) {
                setState(() => _darkMode = value);
              },
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Notifications'),
          _buildSettingCard(
            child: SwitchListTile(
              title: Text(
                'Enable Notifications',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Receive notifications for new messages',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              value: _notifications,
              onChanged: (value) {
                setState(() => _notifications = value);
              },
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('API Configuration'),
          _buildSettingCard(
            child: ListTile(
              title: Text(
                'API Endpoint',
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
          _buildSectionTitle('About'),
          _buildSettingCard(
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    'Version',
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
                    'Privacy Policy',
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
                    'Terms of Service',
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
          'API Endpoint',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter API endpoint URL',
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
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _apiEndpoint = controller.text);
              Navigator.pop(context);
            },
            child: Text(
              'Save',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
