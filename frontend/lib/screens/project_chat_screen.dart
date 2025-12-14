import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/project.dart';
import '../models/claude_settings.dart';
import '../models/conversation.dart';
import '../providers/claude_provider.dart';
import '../services/api_client.dart';
import 'settings_screen.dart';

class ProjectChatScreen extends StatefulWidget {
  final Project project;

  const ProjectChatScreen({super.key, required this.project});

  @override
  State<ProjectChatScreen> createState() => _ProjectChatScreenState();
}

class _ProjectChatScreenState extends State<ProjectChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkApiKey();
      _loadConversations();
      _focusNode.requestFocus();
    });
  }

  void _loadConversations() {
    context.read<ClaudeProvider>().loadConversations(widget.project.id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-focus when app resumes
    if (state == AppLifecycleState.resumed) {
      _focusNode.requestFocus();
    }
  }

  void _checkApiKey() {
    final provider = context.read<ClaudeProvider>();
    provider.checkApiKey().then((_) {
      if (mounted && !provider.hasApiKey) {
        _showApiKeyPrompt();
      }
    });
  }

  void _showApiKeyPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key, size: 48),
        title: const Text('API Key Required'),
        content: const Text(
          'You need to configure your Anthropic API key to chat with Claude.\n\n'
          'Go to Settings > Claude to add your API key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Check API key before sending
    final provider = context.read<ClaudeProvider>();
    if (!provider.hasApiKey) {
      _showApiKeyPrompt();
      return;
    }

    _messageController.clear();

    // Keep focus on input immediately after clearing
    _focusNode.requestFocus();

    try {
      // Use the persistent message method
      await provider.sendMessageWithPersistence(
        message,
        projectId: widget.project.id,
        continueConversation: true,
      );

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    // Re-focus after completion in case it was lost during streaming
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  void _showConversationDrawer() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _ConversationDrawer(
        projectId: widget.project.id,
        onSelect: (conversationId) {
          Navigator.pop(ctx);
          context.read<ClaudeProvider>().selectConversation(conversationId);
        },
        onNewChat: () {
          Navigator.pop(ctx);
          context.read<ClaudeProvider>().startNewChat();
        },
        onDelete: (conversationId) async {
          await context.read<ClaudeProvider>().deleteConversation(conversationId);
        },
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClaudeProvider>(
      builder: (context, provider, _) {
        // Calculate total items (history + streaming bubble if sending)
        final isStreaming = provider.isSending;
        final itemCount = provider.chatHistory.length + (isStreaming ? 1 : 0);
        final showEmptyView = provider.chatHistory.isEmpty && !isStreaming;

        // Auto-scroll when streaming
        if (isStreaming) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        // Show API key warning banner if not configured
        return GestureDetector(
          // Re-focus on tap anywhere in the chat area
          behavior: HitTestBehavior.translucent,
          onTap: () => _focusNode.requestFocus(),
          child: Column(
            children: [
              if (!provider.hasApiKey)
                MaterialBanner(
                  content: const Text('API key not configured. Chat will not work.'),
                  leading: const Icon(Icons.warning, color: Colors.orange),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                      },
                      child: const Text('Configure'),
                    ),
                  ],
                ),
              Expanded(
                child: showEmptyView
                    ? _EmptyChatView(projectName: widget.project.name)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          // Show streaming response as last item
                          if (isStreaming && index == itemCount - 1) {
                            return _StreamingBubble(
                              userMessage: provider.pendingUserMessage,
                              response: provider.streamingResponse,
                              activity: provider.currentActivity,
                              activityHistory: provider.activityHistory,
                            );
                          }
                          final message = provider.chatHistory[index];
                          return _ChatBubble(message: message);
                        },
                      ),
              ),
              _ChatInputBar(
                controller: _messageController,
                focusNode: _focusNode,
                onSend: _sendMessage,
                isSending: provider.isSending,
                onClear: () => provider.startNewChat(),
                onHistory: _showConversationDrawer,
                conversationCount: provider.conversations.length,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  final String projectName;

  const _EmptyChatView({required this.projectName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Chat with Claude',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask Claude to help you with "$projectName"',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(label: 'Explain this code'),
                _SuggestionChip(label: 'Fix the bug'),
                _SuggestionChip(label: 'Add a feature'),
                _SuggestionChip(label: 'Write tests'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;

  const _SuggestionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () {},
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ClaudeMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User message
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message.userMessage,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Claude response
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Claude',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MarkdownBody(
                    data: message.response,
                    selectable: true,
                    onTapLink: (text, href, title) async {
                      if (href != null) {
                        final uri = Uri.parse(href);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      code: TextStyle(
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (message.filesModified.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      children: message.filesModified.map((file) {
                        return Chip(
                          label: Text(file, style: const TextStyle(fontSize: 11)),
                          avatar: const Icon(Icons.edit_document, size: 14),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to display a streaming response with typing indicator
class _StreamingBubble extends StatelessWidget {
  final String userMessage;
  final String response;
  final ClaudeActivity? activity;
  final List<ClaudeActivity> activityHistory;

  const _StreamingBubble({
    required this.userMessage,
    required this.response,
    this.activity,
    this.activityHistory = const [],
  });

  IconData _getActivityIcon(String? tool) {
    switch (tool) {
      case 'Read':
        return Icons.description_outlined;
      case 'Write':
        return Icons.edit_note;
      case 'Edit':
        return Icons.edit_outlined;
      case 'Bash':
        return Icons.terminal;
      case 'Glob':
      case 'Grep':
        return Icons.search;
      case 'WebFetch':
      case 'WebSearch':
        return Icons.language;
      case 'TodoWrite':
        return Icons.checklist;
      default:
        return Icons.build_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User message (if provided)
          if (userMessage.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  userMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          if (userMessage.isNotEmpty) const SizedBox(height: 8),
          // Activity panel showing what Claude is doing
          if (activityHistory.isNotEmpty || activity != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.build_circle_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Claude is working...',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Show activity history
                    ...activityHistory.map((act) {
                      final isActive = activity?.tool == act.tool &&
                          activity?.input?.toString() == act.input?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            if (isActive)
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            else
                              Icon(
                                act.success == false ? Icons.error_outline : Icons.check_circle_outline,
                                size: 14,
                                color: act.success == false
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.outline,
                              ),
                            const SizedBox(width: 8),
                            Icon(
                              _getActivityIcon(act.tool),
                              size: 14,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              act.displayName,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isActive
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context).colorScheme.outline,
                                    fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                                  ),
                            ),
                            if (act.detail.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  act.detail,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.outline,
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          // Claude streaming response
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Claude',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (activity == null && response.isEmpty) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (response.isEmpty && activity == null)
                    Text(
                      'Thinking...',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (response.isEmpty)
                    Text(
                      '...',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: response,
                      selectable: true,
                      onTapLink: (text, href, title) async {
                        if (href != null) {
                          final uri = Uri.parse(href);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        code: TextStyle(
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                          fontFamily: 'monospace',
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool isSending;
  final VoidCallback onClear;
  final VoidCallback onHistory;
  final int conversationCount;

  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.isSending,
    required this.onClear,
    required this.onHistory,
    this.conversationCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // History button with badge
            SizedBox(
              height: 48,
              width: 48,
              child: Badge(
                isLabelVisible: conversationCount > 0,
                label: Text('$conversationCount'),
                child: IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: onHistory,
                  tooltip: 'Chat history',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            // New chat button
            SizedBox(
              height: 48,
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: onClear,
                tooltip: 'New chat',
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isSending ? 'Claude is responding...' : 'Ask Claude anything...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: isSending ? null : (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              width: 48,
              child: FilledButton(
                onPressed: isSending ? null : onSend,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drawer showing conversation history for the project
class _ConversationDrawer extends StatelessWidget {
  final String projectId;
  final Function(String) onSelect;
  final VoidCallback onNewChat;
  final Function(String) onDelete;

  const _ConversationDrawer({
    required this.projectId,
    required this.onSelect,
    required this.onNewChat,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ClaudeProvider>(
      builder: (context, provider, _) {
        final conversations = provider.conversations;
        final currentId = provider.currentConversationId;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Chat History',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: onNewChat,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Chat'),
                    ),
                  ],
                ),
              ),
              // Conversation list
              Flexible(
                child: conversations.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No chat history yet',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          final conv = conversations[index];
                          final isSelected = conv.id == currentId;

                          return ListTile(
                            selected: isSelected,
                            leading: Icon(
                              isSelected
                                  ? Icons.chat_bubble
                                  : Icons.chat_bubble_outline,
                            ),
                            title: Text(
                              conv.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${conv.messageCount} messages - ${_formatDate(conv.updatedAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _confirmDelete(context, conv),
                            ),
                            onTap: () => onSelect(conv.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Conversation conv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text('Delete "${conv.displayTitle}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(conv.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
