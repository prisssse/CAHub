import 'package:flutter/material.dart';
import '../core/constants/colors.dart';
import '../models/session_settings.dart';

class SessionSettingsScreen extends StatefulWidget {
  final SessionSettings settings;
  final Function(SessionSettings) onSave;

  const SessionSettingsScreen({
    super.key,
    required this.settings,
    required this.onSave,
  });

  @override
  State<SessionSettingsScreen> createState() => _SessionSettingsScreenState();
}

class _SessionSettingsScreenState extends State<SessionSettingsScreen> {
  late PermissionMode _permissionMode;
  late TextEditingController _systemPromptController;
  late bool _includeProjectSettings;

  @override
  void initState() {
    super.initState();
    _permissionMode = widget.settings.permissionMode;
    _systemPromptController = TextEditingController(
      text: widget.settings.systemPrompt ?? '',
    );
    _includeProjectSettings =
        widget.settings.settingSources.contains('project');
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    super.dispose();
  }

  void _save() {
    final settingSources = ['user'];
    if (_includeProjectSettings) {
      settingSources.add('project');
    }

    final updated = SessionSettings(
      sessionId: widget.settings.sessionId,
      cwd: widget.settings.cwd,
      permissionMode: _permissionMode,
      systemPrompt: _systemPromptController.text.trim().isEmpty
          ? null
          : _systemPromptController.text.trim(),
      settingSources: settingSources,
    );

    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('会话设置'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              '保存',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('工作目录'),
          _buildInfoCard(
            child: ListTile(
              title: Text(
                '当前目录',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.settings.cwd,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              trailing: Icon(
                Icons.lock_outline,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('权限模式'),
          _buildInfoCard(
            child: Column(
              children: [
                _buildPermissionOption(
                  PermissionMode.defaultMode,
                  '默认',
                  '标准权限模式，需用户批准',
                ),
                Divider(height: 1, color: AppColors.divider),
                _buildPermissionOption(
                  PermissionMode.plan,
                  '计划模式',
                  '执行前先创建计划',
                ),
                Divider(height: 1, color: AppColors.divider),
                _buildPermissionOption(
                  PermissionMode.acceptEdits,
                  '接受编辑',
                  '自动接受文件编辑',
                ),
                Divider(height: 1, color: AppColors.divider),
                _buildPermissionOption(
                  PermissionMode.bypassPermissions,
                  '跳过权限',
                  '执行所有操作无需询问',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('系统提示词'),
          _buildInfoCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _systemPromptController,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '输入自定义系统提示词（可选）',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('设置来源'),
          _buildInfoCard(
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '用户设置',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '必需 - 始终包含',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                  ),
                ),
                Divider(height: 1, color: AppColors.divider),
                SwitchListTile(
                  title: Text(
                    '项目设置',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '包含项目特定设置',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: _includeProjectSettings,
                  onChanged: (value) {
                    setState(() => _includeProjectSettings = value);
                  },
                  activeColor: AppColors.primary,
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

  Widget _buildInfoCard({required Widget child}) {
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

  Widget _buildPermissionOption(
    PermissionMode mode,
    String title,
    String description,
  ) {
    final isSelected = _permissionMode == mode;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.primary)
          : Icon(Icons.circle_outlined, color: AppColors.textTertiary),
      onTap: () {
        setState(() => _permissionMode = mode);
      },
    );
  }
}
