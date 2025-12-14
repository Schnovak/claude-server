import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/claude_settings.dart';
import '../models/conversation.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

class ClaudeProvider extends ChangeNotifier {
  ClaudeSettings? _settings;
  List<String> _availableModels = [];
  List<ClaudePlugin> _installedPlugins = [];
  List<ClaudePlugin> _searchResults = [];
  List<ClaudeMessage> _chatHistory = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _hasApiKey = false;
  String? _error;

  // Conversation persistence
  List<Conversation> _conversations = [];
  String? _currentConversationId;
  String? _currentProjectId;

  // Streaming state
  String _streamingResponse = '';
  String _pendingUserMessage = '';
  ClaudeActivity? _currentActivity;
  List<ClaudeActivity> _activityHistory = [];
  StreamSubscription<ClaudeStreamChunk>? _streamSubscription;

  ClaudeSettings? get settings => _settings;
  List<String> get availableModels => _availableModels;
  List<ClaudePlugin> get installedPlugins => _installedPlugins;
  List<ClaudePlugin> get searchResults => _searchResults;
  List<ClaudeMessage> get chatHistory => _chatHistory;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get hasApiKey => _hasApiKey;
  String? get error => _error;
  String get streamingResponse => _streamingResponse;
  String get pendingUserMessage => _pendingUserMessage;
  ClaudeActivity? get currentActivity => _currentActivity;
  List<ClaudeActivity> get activityHistory => _activityHistory;

  // Conversation getters
  List<Conversation> get conversations => _conversations;
  String? get currentConversationId => _currentConversationId;
  Conversation? get currentConversation => _currentConversationId != null
      ? _conversations.firstWhere(
          (c) => c.id == _currentConversationId,
          orElse: () => _conversations.first,
        )
      : null;

  void updateAuth(AuthProvider auth) {
    if (auth.isAuthenticated) {
      loadSettings();
      loadModels();
      loadPlugins();
      checkApiKey();
    } else {
      _settings = null;
      _availableModels = [];
      _installedPlugins = [];
      _chatHistory = [];
      _hasApiKey = false;
      notifyListeners();
    }
  }

  Future<void> checkApiKey() async {
    try {
      _hasApiKey = await apiClient.getApiKeyStatus();
      notifyListeners();
    } catch (e) {
      _hasApiKey = false;
    }
  }

  Future<void> setApiKey(String apiKey) async {
    await apiClient.setApiKey(apiKey);
    _hasApiKey = true;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _settings = await apiClient.getClaudeSettings();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(ClaudeSettings settings) async {
    try {
      _settings = await apiClient.updateClaudeSettings(settings);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadModels() async {
    try {
      _availableModels = await apiClient.getClaudeModels();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    }
  }

  Future<void> loadPlugins() async {
    try {
      _installedPlugins = await apiClient.getInstalledPlugins();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    }
  }

  Future<void> installPlugin(String name) async {
    await apiClient.installPlugin(name);
    await loadPlugins();
  }

  Future<void> uninstallPlugin(String name) async {
    await apiClient.uninstallPlugin(name);
    await loadPlugins();
  }

  Future<void> searchPlugins(String query) async {
    try {
      _searchResults = await apiClient.searchPlugins(query);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Send a message with live streaming updates
  Future<void> sendMessage(
    String message, {
    String? projectId,
    bool continueConversation = false,
  }) async {
    // Cancel any existing stream
    await _streamSubscription?.cancel();

    _isSending = true;
    _streamingResponse = '';
    _pendingUserMessage = message;
    _currentActivity = null;
    _activityHistory = [];
    _error = null;
    notifyListeners();

    List<String> filesModified = [];
    List<String> suggestedCommands = [];

    try {
      final stream = apiClient.sendClaudeMessageStream(
        message,
        projectId: projectId,
        continueConversation: continueConversation,
      );

      final completer = Completer<void>();

      _streamSubscription = stream.listen(
        (chunk) {
          if (chunk.error != null) {
            _error = chunk.error;
            _currentActivity = null;
            notifyListeners();
            return;
          }

          // Handle activity updates
          if (chunk.activity != null) {
            final activity = chunk.activity!;
            if (activity.type == 'tool_start' || activity.type == 'tool_call') {
              _currentActivity = activity;
              // Add to history when starting
              _activityHistory.add(activity);
            } else if (activity.type == 'tool_end') {
              _currentActivity = null;
            } else if (activity.type == 'tool_result') {
              // Update the last activity with result info
              if (_activityHistory.isNotEmpty) {
                final lastIdx = _activityHistory.length - 1;
                final last = _activityHistory[lastIdx];
                _activityHistory[lastIdx] = ClaudeActivity(
                  type: last.type,
                  tool: last.tool,
                  input: last.input,
                  result: activity.result,
                  success: activity.success,
                );
              }
            }
            notifyListeners();
          }

          if (chunk.text != null) {
            _streamingResponse += chunk.text!;
            notifyListeners();
          }

          if (chunk.done) {
            filesModified = chunk.filesModified;
            suggestedCommands = chunk.suggestedCommands;
          }
        },
        onError: (e) {
          _error = e.toString();
          _currentActivity = null;
          notifyListeners();
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          // Add completed message to history
          final claudeMessage = ClaudeMessage(
            userMessage: message,
            response: _streamingResponse,
            filesModified: filesModified,
            suggestedCommands: suggestedCommands,
          );
          _chatHistory.add(claudeMessage);
          _streamingResponse = '';
          _pendingUserMessage = '';
          _currentActivity = null;
          _activityHistory = [];
          _isSending = false;
          notifyListeners();
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      _error = e.toString();
      _isSending = false;
      _streamingResponse = '';
      _pendingUserMessage = '';
      _currentActivity = null;
      _activityHistory = [];
      notifyListeners();
      rethrow;
    }
  }

  /// Send a message without streaming (fallback)
  Future<ClaudeMessage> sendMessageSync(
    String message, {
    String? projectId,
    bool continueConversation = false,
  }) async {
    _isSending = true;
    _error = null;
    notifyListeners();

    try {
      final response = await apiClient.sendClaudeMessage(
        message,
        projectId: projectId,
        continueConversation: continueConversation,
      );
      _chatHistory.add(response);
      return response;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void clearChatHistory() {
    _chatHistory = [];
    notifyListeners();
  }

  // ============== Conversation Management ==============

  /// Load conversations for a project
  Future<void> loadConversations(String projectId) async {
    // Clear state when switching to a different project
    if (_currentProjectId != projectId) {
      _currentConversationId = null;
      _chatHistory = [];
      _streamingResponse = '';
      _pendingUserMessage = '';
      _currentActivity = null;
      _activityHistory = [];
    }

    _currentProjectId = projectId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _conversations = await apiClient.getConversations(projectId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _conversations = [];
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new conversation for the current project
  Future<Conversation?> createConversation({String? title}) async {
    if (_currentProjectId == null) return null;

    try {
      final conversation = await apiClient.createConversation(
        _currentProjectId!,
        title: title,
      );
      _conversations.insert(0, conversation);
      _currentConversationId = conversation.id;
      _chatHistory = []; // Clear local chat history for new conversation
      notifyListeners();
      return conversation;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Select an existing conversation and load its messages
  Future<void> selectConversation(String conversationId) async {
    if (_currentProjectId == null) return;

    _currentConversationId = conversationId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final conversationWithMessages = await apiClient.getConversation(
        _currentProjectId!,
        conversationId,
      );

      // Convert ConversationMessages to ClaudeMessages for display
      _chatHistory = [];
      for (int i = 0; i < conversationWithMessages.messages.length; i++) {
        final msg = conversationWithMessages.messages[i];
        if (msg.role == MessageRole.user) {
          // Find the next assistant message if it exists
          String response = '';
          List<String> filesModified = [];
          List<String> suggestedCommands = [];

          if (i + 1 < conversationWithMessages.messages.length) {
            final nextMsg = conversationWithMessages.messages[i + 1];
            if (nextMsg.role == MessageRole.assistant) {
              response = nextMsg.content;
              filesModified = nextMsg.filesModified ?? [];
              suggestedCommands = nextMsg.suggestedCommands ?? [];
            }
          }

          _chatHistory.add(ClaudeMessage(
            userMessage: msg.content,
            response: response,
            conversationId: conversationId,
            filesModified: filesModified,
            suggestedCommands: suggestedCommands,
          ));
        }
      }
    } catch (e) {
      _error = e.toString();
      _chatHistory = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a conversation
  Future<bool> deleteConversation(String conversationId) async {
    if (_currentProjectId == null) return false;

    try {
      await apiClient.deleteConversation(_currentProjectId!, conversationId);
      _conversations.removeWhere((c) => c.id == conversationId);

      // If we deleted the current conversation, clear it
      if (_currentConversationId == conversationId) {
        _currentConversationId = null;
        _chatHistory = [];
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Start a new chat (clears current conversation)
  void startNewChat() {
    _currentConversationId = null;
    _chatHistory = [];
    _streamingResponse = '';
    _pendingUserMessage = '';
    _currentActivity = null;
    _activityHistory = [];
    notifyListeners();
  }

  /// Save a message to the current conversation
  Future<void> _saveMessageToConversation(
    String projectId,
    MessageRole role,
    String content, {
    List<String>? filesModified,
    List<String>? suggestedCommands,
    int? tokensUsed,
  }) async {
    if (_currentConversationId == null || projectId != _currentProjectId) {
      return;
    }

    try {
      final message = ConversationMessage(
        id: '', // Will be assigned by server
        conversationId: _currentConversationId!,
        role: role,
        content: content,
        filesModified: filesModified,
        suggestedCommands: suggestedCommands,
        tokensUsed: tokensUsed,
        createdAt: DateTime.now(),
      );

      await apiClient.addConversationMessage(
        projectId,
        _currentConversationId!,
        message,
      );
    } catch (e) {
      debugPrint('Failed to save message to conversation: $e');
      // Don't throw - message saving failure shouldn't break the chat
    }
  }

  /// Enhanced sendMessage that persists to conversation
  Future<void> sendMessageWithPersistence(
    String message, {
    required String projectId,
    bool continueConversation = false,
  }) async {
    // Create conversation if none exists
    if (_currentConversationId == null) {
      final conversation = await createConversation();
      if (conversation == null) {
        _error = 'Failed to create conversation';
        notifyListeners();
        return;
      }
    }

    // Save user message to conversation
    await _saveMessageToConversation(
      projectId,
      MessageRole.user,
      message,
    );

    // Cancel any existing stream
    await _streamSubscription?.cancel();

    _isSending = true;
    _streamingResponse = '';
    _pendingUserMessage = message;
    _currentActivity = null;
    _activityHistory = [];
    _error = null;
    notifyListeners();

    List<String> filesModified = [];
    List<String> suggestedCommands = [];

    try {
      final stream = apiClient.sendClaudeMessageStream(
        message,
        projectId: projectId,
        continueConversation: continueConversation,
      );

      final completer = Completer<void>();

      _streamSubscription = stream.listen(
        (chunk) {
          if (chunk.error != null) {
            _error = chunk.error;
            _currentActivity = null;
            notifyListeners();
            return;
          }

          // Handle activity updates
          if (chunk.activity != null) {
            final activity = chunk.activity!;
            if (activity.type == 'tool_start' || activity.type == 'tool_call') {
              _currentActivity = activity;
              _activityHistory.add(activity);
            } else if (activity.type == 'tool_end') {
              _currentActivity = null;
            } else if (activity.type == 'tool_result') {
              if (_activityHistory.isNotEmpty) {
                final lastIdx = _activityHistory.length - 1;
                final last = _activityHistory[lastIdx];
                _activityHistory[lastIdx] = ClaudeActivity(
                  type: last.type,
                  tool: last.tool,
                  input: last.input,
                  result: activity.result,
                  success: activity.success,
                );
              }
            }
            notifyListeners();
          }

          if (chunk.text != null) {
            _streamingResponse += chunk.text!;
            notifyListeners();
          }

          if (chunk.done) {
            filesModified = chunk.filesModified;
            suggestedCommands = chunk.suggestedCommands;
          }
        },
        onError: (e) {
          _error = e.toString();
          _currentActivity = null;
          notifyListeners();
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () async {
          // Save assistant response to conversation
          await _saveMessageToConversation(
            projectId,
            MessageRole.assistant,
            _streamingResponse,
            filesModified: filesModified,
            suggestedCommands: suggestedCommands,
          );

          // Add completed message to local history
          final claudeMessage = ClaudeMessage(
            userMessage: message,
            response: _streamingResponse,
            conversationId: _currentConversationId,
            filesModified: filesModified,
            suggestedCommands: suggestedCommands,
          );
          _chatHistory.add(claudeMessage);
          _streamingResponse = '';
          _pendingUserMessage = '';
          _currentActivity = null;
          _activityHistory = [];
          _isSending = false;
          notifyListeners();

          // Refresh conversations list to update message count
          if (_currentProjectId != null) {
            loadConversations(_currentProjectId!);
          }

          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      _error = e.toString();
      _isSending = false;
      _streamingResponse = '';
      _pendingUserMessage = '';
      _currentActivity = null;
      _activityHistory = [];
      notifyListeners();
      rethrow;
    }
  }
}
