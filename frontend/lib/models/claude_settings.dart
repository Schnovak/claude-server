class ClaudeSettings {
  final String userId;
  final String defaultModel;
  final String? systemPrompt;
  final String? extraInstructions;
  final bool useWorkspaceMultiProject;
  final DateTime updatedAt;

  ClaudeSettings({
    required this.userId,
    required this.defaultModel,
    this.systemPrompt,
    this.extraInstructions,
    required this.useWorkspaceMultiProject,
    required this.updatedAt,
  });

  factory ClaudeSettings.fromJson(Map<String, dynamic> json) {
    return ClaudeSettings(
      userId: json['user_id'],
      defaultModel: json['default_model'],
      systemPrompt: json['system_prompt'],
      extraInstructions: json['extra_instructions'],
      useWorkspaceMultiProject: json['use_workspace_multi_project'] ?? true,
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'default_model': defaultModel,
      'system_prompt': systemPrompt,
      'extra_instructions': extraInstructions,
      'use_workspace_multi_project': useWorkspaceMultiProject,
    };
  }

  ClaudeSettings copyWith({
    String? defaultModel,
    String? systemPrompt,
    String? extraInstructions,
    bool? useWorkspaceMultiProject,
  }) {
    return ClaudeSettings(
      userId: userId,
      defaultModel: defaultModel ?? this.defaultModel,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      extraInstructions: extraInstructions ?? this.extraInstructions,
      useWorkspaceMultiProject:
          useWorkspaceMultiProject ?? this.useWorkspaceMultiProject,
      updatedAt: updatedAt,
    );
  }
}

class ClaudeMessage {
  final String userMessage;
  final String response;
  final String? conversationId;
  final int? tokensUsed;
  final List<String> filesModified;
  final List<String> suggestedCommands;

  ClaudeMessage({
    required this.userMessage,
    required this.response,
    this.conversationId,
    this.tokensUsed,
    this.filesModified = const [],
    this.suggestedCommands = const [],
  });

  factory ClaudeMessage.fromJson(Map<String, dynamic> json, {String? userMessage}) {
    return ClaudeMessage(
      userMessage: userMessage ?? json['user_message'] ?? '',
      response: json['response'],
      conversationId: json['conversation_id'],
      tokensUsed: json['tokens_used'],
      filesModified: List<String>.from(json['files_modified'] ?? []),
      suggestedCommands: List<String>.from(json['suggested_commands'] ?? []),
    );
  }
}

class ClaudePlugin {
  final String name;
  final String? version;
  final String? description;
  final bool enabled;
  final bool installed;

  ClaudePlugin({
    required this.name,
    this.version,
    this.description,
    this.enabled = true,
    this.installed = false,
  });

  factory ClaudePlugin.fromJson(Map<String, dynamic> json) {
    return ClaudePlugin(
      name: json['name'],
      version: json['version'],
      description: json['description'],
      enabled: json['enabled'] ?? true,
      installed: json['installed'] ?? false,
    );
  }
}
