import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/claude_settings.dart';
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

  // Streaming state
  String _streamingResponse = '';
  String _pendingUserMessage = '';
  ClaudeActivity? _currentActivity;
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
            } else if (activity.type == 'tool_end') {
              _currentActivity = null;
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
}
