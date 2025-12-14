import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/project.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../utils/file_download/file_download.dart' as file_download;

class FilesScreen extends StatefulWidget {
  final Project project;

  const FilesScreen({super.key, required this.project});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String _currentPath = '';
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _error;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    // Build WebSocket URL
    final wsUrl = kDebugMode
        ? 'ws://localhost:8000/api/projects/${widget.project.id}/files/watch?token=$token'
        : 'ws://${Uri.base.host}:${Uri.base.port}/api/projects/${widget.project.id}/files/watch?token=$token';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _subscription = _channel!.stream.listen(
        _onWebSocketMessage,
        onError: (error) {
          debugPrint('WebSocket error: $error');
        },
        onDone: () {
          debugPrint('WebSocket closed');
        },
      );
    } catch (e) {
      debugPrint('Failed to connect WebSocket: $e');
    }
  }

  void _onWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'];

      if (type == 'file_change') {
        // Debounce refresh to avoid too many refreshes
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadFiles();
          }
        });
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _files = await apiClient.listFiles(widget.project.id, _currentPath);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath.isEmpty) return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _navigateTo(parts.join('/'));
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file data')),
          );
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploading ${file.name}...')),
        );
      }

      await apiClient.uploadFile(
        widget.project.id,
        _currentPath,
        file.bytes!,
        file.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} uploaded successfully')),
        );
      }

      _loadFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(String fileName) async {
    final path = _currentPath.isEmpty ? fileName : '$_currentPath/$fileName';
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    // Build download URL with token
    final downloadUrl = '${apiClient.getFileDownloadUrl(widget.project.id, path)}&token=$token';

    try {
      // Use cross-platform download utility
      await file_download.downloadFile(downloadUrl, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PathBar(
          path: _currentPath,
          onNavigateUp: _currentPath.isNotEmpty ? _navigateUp : null,
          onRefresh: _loadFiles,
          onUpload: _uploadFile,
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadFiles,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text('This folder is empty'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isDir = file['is_dir'] == true;
        final name = file['name'] as String;
        return _FileListTile(
          file: file,
          onTap: () {
            if (isDir) {
              final newPath =
                  _currentPath.isEmpty ? name : '$_currentPath/$name';
              _navigateTo(newPath);
            }
          },
          onDelete: () => _confirmDelete(file),
          onDownload: isDir ? null : () => _downloadFile(name),
        );
      },
    );
  }

  void _confirmDelete(Map<String, dynamic> file) {
    final name = file['name'] as String;
    final isDir = file['is_dir'] == true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${isDir ? 'Folder' : 'File'}'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final path =
                  _currentPath.isEmpty ? name : '$_currentPath/$name';
              try {
                await apiClient.deleteFile(widget.project.id, path);
                _loadFiles();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
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
}

class _PathBar extends StatelessWidget {
  final String path;
  final VoidCallback? onNavigateUp;
  final VoidCallback onRefresh;
  final VoidCallback onUpload;

  const _PathBar({
    required this.path,
    this.onNavigateUp,
    required this.onRefresh,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: onNavigateUp,
            tooltip: 'Go up',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '/${path.isEmpty ? '' : path}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: onUpload,
            tooltip: 'Upload file',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  final Map<String, dynamic> file;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onDownload;

  const _FileListTile({
    required this.file,
    required this.onTap,
    required this.onDelete,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final name = file['name'] as String;
    final isDir = file['is_dir'] == true;
    final size = file['size'] as int?;

    return ListTile(
      leading: Icon(
        isDir ? Icons.folder : _getFileIcon(name),
        color: isDir
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(name),
      subtitle: isDir ? null : Text(_formatSize(size ?? 0)),
      trailing: PopupMenuButton(
        itemBuilder: (context) => [
          if (!isDir && onDownload != null)
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download),
                  SizedBox(width: 8),
                  Text('Download'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline),
                SizedBox(width: 8),
                Text('Delete'),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          if (value == 'delete') onDelete();
          if (value == 'download' && onDownload != null) onDownload!();
        },
      ),
      onTap: onTap,
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'java':
      case 'kt':
      case 'swift':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
        return Icons.code;
      case 'json':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'xml':
        return Icons.data_object;
      case 'md':
      case 'txt':
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        return Icons.image;
      case 'mp3':
      case 'wav':
      case 'ogg':
        return Icons.audio_file;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
        return Icons.archive;
      case 'pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
