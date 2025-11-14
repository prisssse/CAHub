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
  late SystemPromptMode _systemPromptMode;
  late String _systemPromptPreset;

  final List<String> _availablePresets = [
    'default',
    'advanced',
    'concise',
    'creative',
  ];

  @override
  void initState() {
    super.initState();
    _permissionMode = widget.settings.permissionMode;
    _systemPromptMode = widget.settings.systemPromptMode;
    _systemPromptPreset = widget.settings.systemPromptPreset ?? 'default';
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
      systemPromptMode: _systemPromptMode,
      systemPromptPreset: _systemPromptMode == SystemPromptMode.preset ? _systemPromptPreset : null,
      systemPrompt: _systemPromptMode == SystemPromptMode.custom && _systemPromptController.text.trim().isNotEmpty
          ? _systemPromptController.text.trim()
          : null,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode selector
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeButton(
                          mode: SystemPromptMode.preset,
                          label: '预设',
                          icon: Icons.style,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModeButton(
                          mode: SystemPromptMode.custom,
                          label: '自定义',
                          icon: Icons.edit,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Preset dropdown or custom text field
                  if (_systemPromptMode == SystemPromptMode.preset)
                    DropdownButtonFormField<String>(
                      value: _systemPromptPreset,
                      decoration: InputDecoration(
                        labelText: '选择预设',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: _availablePresets.map((preset) {
                        return DropdownMenuItem(
                          value: preset,
                          child: Text(
                            _getPresetDisplayName(preset),
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _systemPromptPreset = value);
                        }
                      },
                      dropdownColor: AppColors.cardBackground,
                    )
                  else
                    TextField(
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
                ],
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

  Widget _buildModeButton({
    required SystemPromptMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _systemPromptMode == mode;
    return Material(
      color: isSelected ? AppColors.primary : AppColors.background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() => _systemPromptMode = mode);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.divider,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPresetDisplayName(String preset) {
    switch (preset) {
      case 'default':
        return '默认 (Default)';
      case 'advanced':
        return '高级 (Advanced)';
      case 'concise':
        return '简洁 (Concise)';
      case 'creative':
        return '创意 (Creative)';
      default:
        return preset;
    }
  }
}
