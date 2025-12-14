/// Models for per-project chat history persistence.

enum MessageRole {
  user,
  assistant;

  static MessageRole fromString(String value) {
    return MessageRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MessageRole.user,
    );
  }
}

class Conversation {
  final String id;
  final String projectId;
  final String ownerId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  Conversation({
    required this.id,
    required this.projectId,
    required this.ownerId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      projectId: json['project_id'],
      ownerId: json['owner_id'],
      title: json['title'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      messageCount: json['message_count'] ?? 0,
    );
  }

  /// Display title, falls back to date if no title
  String get displayTitle {
    if (title != null && title!.isNotEmpty) {
      return title!;
    }
    return 'Chat ${createdAt.month}/${createdAt.day}';
  }
}

class ConversationMessage {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final List<String>? filesModified;
  final List<String>? suggestedCommands;
  final int? tokensUsed;
  final DateTime createdAt;

  ConversationMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.filesModified,
    this.suggestedCommands,
    this.tokensUsed,
    required this.createdAt,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'],
      conversationId: json['conversation_id'],
      role: MessageRole.fromString(json['role']),
      content: json['content'],
      filesModified: json['files_modified'] != null
          ? List<String>.from(json['files_modified'])
          : null,
      suggestedCommands: json['suggested_commands'] != null
          ? List<String>.from(json['suggested_commands'])
          : null,
      tokensUsed: json['tokens_used'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'role': role.name,
      'content': content,
      if (filesModified != null) 'files_modified': filesModified,
      if (suggestedCommands != null) 'suggested_commands': suggestedCommands,
      if (tokensUsed != null) 'tokens_used': tokensUsed,
    };
  }
}

class ConversationWithMessages {
  final Conversation conversation;
  final List<ConversationMessage> messages;

  ConversationWithMessages({
    required this.conversation,
    required this.messages,
  });

  factory ConversationWithMessages.fromJson(Map<String, dynamic> json) {
    return ConversationWithMessages(
      conversation: Conversation(
        id: json['id'],
        projectId: json['project_id'],
        ownerId: json['owner_id'],
        title: json['title'],
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
      ),
      messages: (json['messages'] as List)
          .map((m) => ConversationMessage.fromJson(m))
          .toList(),
    );
  }
}
