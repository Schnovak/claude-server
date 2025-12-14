import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../models/project.dart';
import '../models/job.dart';
import '../models/claude_settings.dart';
import '../models/conversation.dart';

/// Represents Claude's current activity (tool use, etc.)
class ClaudeActivity {
  final String type; // tool_start, tool_call, tool_input, tool_end, tool_result
  final String? tool;
  final Map<String, dynamic>? input;
  final String? partial;
  final String? result;
  final bool? success;

  ClaudeActivity({
    required this.type,
    this.tool,
    this.input,
    this.partial,
    this.result,
    this.success,
  });

  factory ClaudeActivity.fromJson(Map<String, dynamic> json) {
    return ClaudeActivity(
      type: json['type'] ?? '',
      tool: json['tool'],
      input: json['input'],
      partial: json['partial'],
      result: json['result'],
      success: json['success'],
    );
  }

  String get displayName {
    switch (tool) {
      case 'Read':
        return 'Reading file';
      case 'Write':
        return 'Writing file';
      case 'Edit':
        return 'Editing file';
      case 'Bash':
        return 'Running command';
      case 'Glob':
        return 'Searching files';
      case 'Grep':
        return 'Searching content';
      case 'TodoWrite':
        return 'Updating tasks';
      case 'WebFetch':
        return 'Fetching web page';
      case 'WebSearch':
        return 'Searching web';
      default:
        return tool ?? 'Working';
    }
  }

  /// Get a short description of what this activity is doing
  String get detail {
    if (input == null) return '';

    switch (tool) {
      case 'Read':
        final path = input!['file_path'] ?? '';
        // Show only the filename or last part of path
        final parts = path.toString().split('/');
        return parts.isNotEmpty ? parts.last : path.toString();
      case 'Write':
        final path = input!['file_path'] ?? '';
        final parts = path.toString().split('/');
        return parts.isNotEmpty ? parts.last : path.toString();
      case 'Edit':
        final path = input!['file_path'] ?? '';
        final parts = path.toString().split('/');
        return parts.isNotEmpty ? parts.last : path.toString();
      case 'Bash':
        final cmd = input!['command'] ?? input!['description'] ?? '';
        // Truncate long commands
        final cmdStr = cmd.toString();
        return cmdStr.length > 50 ? '${cmdStr.substring(0, 47)}...' : cmdStr;
      case 'Glob':
        return input!['pattern']?.toString() ?? '';
      case 'Grep':
        return input!['pattern']?.toString() ?? '';
      case 'WebFetch':
        final url = input!['url'] ?? '';
        return url.toString();
      case 'WebSearch':
        return input!['query']?.toString() ?? '';
      default:
        return '';
    }
  }
}

/// Represents a streaming chunk from Claude
class ClaudeStreamChunk {
  final String? text;
  final bool done;
  final List<String> filesModified;
  final List<String> suggestedCommands;
  final String? error;
  final ClaudeActivity? activity;

  ClaudeStreamChunk({
    this.text,
    this.done = false,
    this.filesModified = const [],
    this.suggestedCommands = const [],
    this.error,
    this.activity,
  });

  factory ClaudeStreamChunk.fromJson(Map<String, dynamic> json) {
    return ClaudeStreamChunk(
      text: json['text'],
      done: json['done'] ?? false,
      filesModified: json['files_modified'] != null
          ? List<String>.from(json['files_modified'])
          : [],
      suggestedCommands: json['suggested_commands'] != null
          ? List<String>.from(json['suggested_commands'])
          : [],
      error: json['error'],
      activity: json['activity'] != null
          ? ClaudeActivity.fromJson(json['activity'])
          : null,
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  // In debug mode, use localhost. In production, use relative /api path
  static String get baseUrl {
    if (kDebugMode) {
      return 'http://localhost:8000/api';
    }
    // Production: nginx proxies /api to backend
    return '/api';
  }

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<dynamic> _handleResponse(http.Response response) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'Request failed';
      try {
        final body = jsonDecode(response.body);
        message = body['detail'] ?? body['message'] ?? message;
      } catch (_) {}
      throw ApiException(response.statusCode, message);
    }
  }

  // ============== Auth ==============

  Future<AuthToken> register(
      String email, String password, String displayName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'display_name': displayName,
      }),
    );
    final data = await _handleResponse(response);
    return AuthToken.fromJson(data);
  }

  Future<AuthToken> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    final data = await _handleResponse(response);
    return AuthToken.fromJson(data);
  }

  Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return User.fromJson(data);
  }

  // ============== Projects ==============

  Future<List<Project>> getProjects() async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects'),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.map((p) => Project.fromJson(p)).toList();
  }

  Future<Project> createProject(String name, ProjectType type) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'type': type.name,
      }),
    );
    final data = await _handleResponse(response);
    return Project.fromJson(data);
  }

  Future<Project> getProject(String projectId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return Project.fromJson(data);
  }

  Future<void> deleteProject(String projectId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/projects/$projectId'),
      headers: _headers,
    );
    await _handleResponse(response);
  }

  // ============== Jobs ==============

  Future<Job> createJob(String projectId, JobType type, {String? command}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects/$projectId/jobs'),
      headers: _headers,
      body: jsonEncode({
        'type': type.toApiString(),
        if (command != null) 'command': command,
      }),
    );
    final data = await _handleResponse(response);
    return Job.fromJson(data);
  }

  Future<List<Job>> getProjectJobs(String projectId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId/jobs'),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.map((j) => Job.fromJson(j)).toList();
  }

  Future<Job> getJob(String jobId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/jobs/$jobId'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return Job.fromJson(data);
  }

  Future<String> getJobLogs(String jobId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/jobs/$jobId/logs'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return data['logs'] ?? '';
  }

  Future<void> cancelJob(String jobId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/jobs/$jobId/cancel'),
      headers: _headers,
    );
    await _handleResponse(response);
  }

  // ============== Claude ==============

  Future<ClaudeSettings> getClaudeSettings() async {
    final response = await http.get(
      Uri.parse('$baseUrl/claude/settings'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return ClaudeSettings.fromJson(data);
  }

  Future<ClaudeSettings> updateClaudeSettings(ClaudeSettings settings) async {
    final response = await http.post(
      Uri.parse('$baseUrl/claude/settings'),
      headers: _headers,
      body: jsonEncode(settings.toUpdateJson()),
    );
    final data = await _handleResponse(response);
    return ClaudeSettings.fromJson(data);
  }

  Future<List<String>> getClaudeModels() async {
    final response = await http.get(
      Uri.parse('$baseUrl/claude/models'),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.cast<String>();
  }

  Future<bool> getApiKeyStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/claude/api-key/status'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return data['configured'] ?? false;
  }

  Future<void> setApiKey(String apiKey) async {
    final response = await http.post(
      Uri.parse('$baseUrl/claude/api-key'),
      headers: _headers,
      body: jsonEncode({'api_key': apiKey}),
    );
    await _handleResponse(response);
  }

  // GitHub Token
  Future<bool> getGitHubTokenStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/claude/github-token/status'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return data['configured'] ?? false;
  }

  Future<void> setGitHubToken(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/claude/github-token'),
      headers: _headers,
      body: jsonEncode({'github_token': token}),
    );
    await _handleResponse(response);
  }

  Future<void> removeGitHubToken() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/claude/github-token'),
      headers: _headers,
    );
    await _handleResponse(response);
  }

  Future<ClaudeMessage> sendClaudeMessage(
    String message, {
    String? projectId,
    bool continueConversation = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/claude/message'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        if (projectId != null) 'project_id': projectId,
        'continue_conversation': continueConversation,
      }),
    );
    final data = await _handleResponse(response);
    return ClaudeMessage.fromJson(data, userMessage: message);
  }

  /// Stream a message to Claude using Server-Sent Events
  Stream<ClaudeStreamChunk> sendClaudeMessageStream(
    String message, {
    String? projectId,
    bool continueConversation = false,
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/claude/message/stream'),
      );
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'message': message,
        if (projectId != null) 'project_id': projectId,
        'continue_conversation': continueConversation,
      });

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw ApiException(
          streamedResponse.statusCode,
          'Stream request failed',
        );
      }

      // Buffer for incomplete lines
      String buffer = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;

        // Process complete SSE messages (format: "data: {...}\n\n")
        while (buffer.contains('\n\n')) {
          final endIndex = buffer.indexOf('\n\n');
          final line = buffer.substring(0, endIndex);
          buffer = buffer.substring(endIndex + 2);

          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6); // Remove "data: " prefix
            try {
              final data = jsonDecode(jsonStr);
              yield ClaudeStreamChunk.fromJson(data);
            } catch (e) {
              // Skip malformed JSON
              debugPrint('Error parsing SSE chunk: $e');
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Future<List<ClaudePlugin>> getInstalledPlugins() async {
    final response = await http.get(
      Uri.parse('$baseUrl/claude/plugins'),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.map((p) => ClaudePlugin.fromJson(p)).toList();
  }

  Future<List<ClaudePlugin>> searchPlugins(String query) async {
    final response = await http.get(
      Uri.parse('$baseUrl/claude/plugins/search?query=$query'),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.map((p) => ClaudePlugin.fromJson(p)).toList();
  }

  Future<void> installPlugin(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/claude/plugins/install'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    await _handleResponse(response);
  }

  Future<void> uninstallPlugin(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/claude/plugins/uninstall'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    await _handleResponse(response);
  }

  // ============== Files ==============

  Future<List<Map<String, dynamic>>> listFiles(
      String projectId, String path) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId/files/list?path=$path'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return List<Map<String, dynamic>>.from(data['items']);
  }

  Future<void> deleteFile(String projectId, String path) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/projects/$projectId/files?path=$path'),
      headers: _headers,
    );
    await _handleResponse(response);
  }

  /// Get the download URL for a file
  String getFileDownloadUrl(String projectId, String path) {
    final encodedPath = Uri.encodeComponent(path);
    return '$baseUrl/projects/$projectId/files/download?path=$encodedPath';
  }

  /// Get the download URL for a folder (as ZIP)
  String getFolderDownloadUrl(String projectId, String path) {
    final encodedPath = Uri.encodeComponent(path);
    return '$baseUrl/projects/$projectId/files/download-folder?path=$encodedPath';
  }

  /// Upload a file to a project
  Future<Map<String, dynamic>> uploadFile(
    String projectId,
    String path,
    List<int> bytes,
    String filename,
  ) async {
    final uri = Uri.parse('$baseUrl/projects/$projectId/files/upload?path=$path');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return await _handleResponse(response);
  }

  // ============== Git ==============

  Future<void> gitInit(String projectId, {String branch = 'main'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects/$projectId/git/init'),
      headers: _headers,
      body: jsonEncode({'default_branch': branch}),
    );
    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> gitStatus(String projectId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId/git/status'),
      headers: _headers,
    );
    return await _handleResponse(response);
  }

  Future<void> gitCommitAndPush(
    String projectId,
    String message, {
    bool push = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects/$projectId/git/commit-and-push'),
      headers: _headers,
      body: jsonEncode({
        'message': message,
        'push': push,
      }),
    );
    await _handleResponse(response);
  }

  Future<void> gitSetRemote(
    String projectId,
    String url, {
    String name = 'origin',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects/$projectId/git/remote'),
      headers: _headers,
      body: jsonEncode({
        'url': url,
        'name': name,
      }),
    );
    await _handleResponse(response);
  }

  Future<Map<String, dynamic>> gitHubCreate(
    String projectId, {
    String? name,
    String? description,
    bool private = false,
    bool push = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects/$projectId/git/github/create'),
      headers: _headers,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        'private': private,
        'push': push,
      }),
    );
    return await _handleResponse(response);
  }

  Future<List<Map<String, dynamic>>> gitLog(
    String projectId, {
    int limit = 10,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId/git/log?limit=$limit'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return List<Map<String, dynamic>>.from(data['commits']);
  }

  // ============== Conversations ==============

  Future<List<Conversation>> getConversations(String projectId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId/conversations'),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.map((c) => Conversation.fromJson(c)).toList();
  }

  Future<Conversation> createConversation(
    String projectId, {
    String? title,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/projects/$projectId/conversations'),
      headers: _headers,
      body: jsonEncode({
        if (title != null) 'title': title,
      }),
    );
    final data = await _handleResponse(response);
    return Conversation.fromJson(data);
  }

  Future<ConversationWithMessages> getConversation(
    String projectId,
    String conversationId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/projects/$projectId/conversations/$conversationId'),
      headers: _headers,
    );
    final data = await _handleResponse(response);
    return ConversationWithMessages.fromJson(data);
  }

  Future<Conversation> updateConversation(
    String projectId,
    String conversationId, {
    String? title,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/projects/$projectId/conversations/$conversationId'),
      headers: _headers,
      body: jsonEncode({
        if (title != null) 'title': title,
      }),
    );
    final data = await _handleResponse(response);
    return Conversation.fromJson(data);
  }

  Future<void> deleteConversation(
    String projectId,
    String conversationId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/projects/$projectId/conversations/$conversationId'),
      headers: _headers,
    );
    await _handleResponse(response);
  }

  Future<ConversationMessage> addConversationMessage(
    String projectId,
    String conversationId,
    ConversationMessage message,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/projects/$projectId/conversations/$conversationId/messages',
      ),
      headers: _headers,
      body: jsonEncode(message.toCreateJson()),
    );
    final data = await _handleResponse(response);
    return ConversationMessage.fromJson(data);
  }

  Future<List<ConversationMessage>> getConversationMessages(
    String projectId,
    String conversationId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/projects/$projectId/conversations/$conversationId/messages'
        '?limit=$limit&offset=$offset',
      ),
      headers: _headers,
    );
    final data = await _handleResponse(response) as List;
    return data.map((m) => ConversationMessage.fromJson(m)).toList();
  }
}

// Global instance
final apiClient = ApiClient();
