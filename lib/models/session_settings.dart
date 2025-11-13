enum PermissionMode {
  defaultMode('default'),
  plan('plan'),
  acceptEdits('acceptEdits'),
  bypassPermissions('bypassPermissions');

  final String value;
  const PermissionMode(this.value);

  static PermissionMode fromString(String value) {
    return PermissionMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => PermissionMode.defaultMode,
    );
  }
}

class SessionSettings {
  final String sessionId;
  final String cwd; // Read-only, cannot be changed
  final PermissionMode permissionMode;
  final String? systemPrompt;
  final List<String> settingSources; // user is required, project is optional

  SessionSettings({
    required this.sessionId,
    required this.cwd,
    this.permissionMode = PermissionMode.defaultMode,
    this.systemPrompt,
    List<String>? settingSources,
  }) : settingSources = settingSources ?? ['user'];

  SessionSettings copyWith({
    String? sessionId,
    String? cwd,
    PermissionMode? permissionMode,
    String? systemPrompt,
    List<String>? settingSources,
  }) {
    return SessionSettings(
      sessionId: sessionId ?? this.sessionId,
      cwd: cwd ?? this.cwd,
      permissionMode: permissionMode ?? this.permissionMode,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      settingSources: settingSources ?? this.settingSources,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'cwd': cwd,
      'permission_mode': permissionMode.value,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      'setting_sources': settingSources,
    };
  }

  factory SessionSettings.fromJson(Map<String, dynamic> json) {
    return SessionSettings(
      sessionId: json['session_id'],
      cwd: json['cwd'],
      permissionMode: json['permission_mode'] != null
          ? PermissionMode.fromString(json['permission_mode'])
          : PermissionMode.defaultMode,
      systemPrompt: json['system_prompt'],
      settingSources: json['setting_sources'] != null
          ? List<String>.from(json['setting_sources'])
          : ['user'],
    );
  }
}
