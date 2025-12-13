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

  ClaudeSettings? get settings => _settings;
  List<String> get availableModels => _availableModels;
  List<ClaudePlugin> get installedPlugins => _installedPlugins;
  List<ClaudePlugin> get searchResults => _searchResults;
  List<ClaudeMessage> get chatHistory => _chatHistory;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get hasApiKey => _hasApiKey;
  String? get error => _error;

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

  Future<ClaudeMessage> sendMessage(
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
