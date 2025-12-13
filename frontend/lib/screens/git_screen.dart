import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/project.dart';
import '../services/api_client.dart';

class GitScreen extends StatefulWidget {
  final Project project;

  const GitScreen({super.key, required this.project});

  @override
  State<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends State<GitScreen> {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _commits = [];
  bool _isLoading = true;
  bool _isInitialized = true;
  String? _error;
  bool _hasGitHubToken = false;

  @override
  void initState() {
    super.initState();
    _loadGitInfo();
    _checkGitHubToken();
  }

  Future<void> _checkGitHubToken() async {
    try {
      final hasToken = await apiClient.getGitHubTokenStatus();
      if (mounted) {
        setState(() => _hasGitHubToken = hasToken);
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _loadGitInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _status = await apiClient.gitStatus(widget.project.id);
      _isInitialized = true;
      _commits = await apiClient.gitLog(widget.project.id);
    } on ApiException catch (e) {
      if (e.message.contains('Not a git repository')) {
        _isInitialized = false;
        _status = null;
        _commits = [];
      } else {
        _error = e.message;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initGit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await apiClient.gitInit(widget.project.id);
      await _loadGitInfo();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: _loadGitInfo,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.code_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Git not initialized',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Initialize a git repository to track changes'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _initGit,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Initialize Git'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGitInfo,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GitStatusCard(
            status: _status!,
            onCommit: () => _showCommitDialog(),
            onSetRemote: () => _showRemoteDialog(),
            onCreateGitHub: _hasGitHubToken
                ? () => _showGitHubCreateDialog()
                : () => _showGitHubTokenSetupDialog(),
            hasGitHubToken: _hasGitHubToken,
          ),
          const SizedBox(height: 24),
          Text(
            'Recent Commits',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_commits.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No commits yet',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            )
          else
            ..._commits.map((commit) => _CommitCard(commit: commit)),
        ],
      ),
    );
  }

  void _showCommitDialog() {
    final controller = TextEditingController();
    bool pushAfterCommit = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Commit Changes'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Commit Message',
                    border: OutlineInputBorder(),
                    hintText: 'Describe your changes',
                  ),
                  maxLines: 3,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Push after commit'),
                  value: pushAfterCommit,
                  onChanged: (value) {
                    setDialogState(() => pushAfterCommit = value ?? true);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(context);
                await _commitAndPush(controller.text.trim(), pushAfterCommit);
              },
              child: const Text('Commit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _commitAndPush(String message, bool push) async {
    try {
      await apiClient.gitCommitAndPush(
        widget.project.id,
        message,
        push: push,
      );
      await _loadGitInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(push ? 'Committed and pushed!' : 'Committed!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showRemoteDialog() {
    final urlController = TextEditingController();
    final nameController = TextEditingController(text: 'origin');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Remote'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Remote Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Remote URL',
                  border: OutlineInputBorder(),
                  hintText: 'https://github.com/user/repo.git',
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (urlController.text.trim().isEmpty) return;
              Navigator.pop(context);
              await _setRemote(
                nameController.text.trim(),
                urlController.text.trim(),
              );
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Future<void> _setRemote(String name, String url) async {
    try {
      await apiClient.gitSetRemote(widget.project.id, url, name: name);
      await _loadGitInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remote set!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showGitHubTokenSetupDialog() {
    final tokenController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.key, color: Colors.orange),
              SizedBox(width: 8),
              Text('GitHub Token Required'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'To create repositories on GitHub, you need to add your Personal Access Token.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'How to get a token:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('1. Go to GitHub → Settings → Developer settings'),
                const Text('2. Click "Personal access tokens" → "Tokens (classic)"'),
                const Text('3. Generate new token with "repo" permission'),
                const Text('4. Copy and paste the token below'),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final uri = Uri.parse('https://github.com/settings/tokens/new');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Open GitHub Token Page',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'GitHub Personal Access Token',
                    hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                  ),
                  obscureText: true,
                  enabled: !isSaving,
                ),
                if (isSaving) ...[
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Saving...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final token = tokenController.text.trim();
                      if (token.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a token')),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      try {
                        await apiClient.setGitHubToken(token);
                        if (mounted) {
                          Navigator.pop(context);
                          setState(() => _hasGitHubToken = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('GitHub token saved! You can now create repositories.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          // Open the create dialog now that token is set
                          _showGitHubCreateDialog();
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: const Text('Save & Continue'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGitHubCreateDialog() {
    final nameController = TextEditingController(text: widget.project.name);
    final descController = TextEditingController();
    bool isPrivate = false;
    bool isCreating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_upload),
              SizedBox(width: 8),
              Text('Create on GitHub'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Repository Name',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !isCreating,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !isCreating,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Private repository'),
                  subtitle: const Text('Only you can see this repository'),
                  value: isPrivate,
                  onChanged: isCreating
                      ? null
                      : (value) {
                          setDialogState(() => isPrivate = value ?? false);
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (isCreating) ...[
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Creating repository...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isCreating
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) return;
                      setDialogState(() => isCreating = true);

                      try {
                        final result = await apiClient.gitHubCreate(
                          widget.project.id,
                          name: nameController.text.trim(),
                          description: descController.text.trim().isEmpty
                              ? null
                              : descController.text.trim(),
                          private: isPrivate,
                        );

                        if (mounted) {
                          Navigator.pop(context);
                          await _loadGitInfo();

                          final webUrl = result['web_url'] as String?;
                          final needsCommit = result['needs_commit'] == true;
                          final message = result['message'] as String? ?? 'Repository created!';

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(message),
                              backgroundColor: needsCommit ? Colors.orange : Colors.green,
                              duration: Duration(seconds: needsCommit ? 5 : 3),
                              action: webUrl != null
                                  ? SnackBarAction(
                                      label: 'Open',
                                      textColor: Colors.white,
                                      onPressed: () async {
                                        final uri = Uri.parse(webUrl);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                    )
                                  : null,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isCreating = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: const Text('Create & Push'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GitStatusCard extends StatelessWidget {
  final Map<String, dynamic> status;
  final VoidCallback onCommit;
  final VoidCallback onSetRemote;
  final VoidCallback onCreateGitHub;
  final bool hasGitHubToken;

  const _GitStatusCard({
    required this.status,
    required this.onCommit,
    required this.onSetRemote,
    required this.onCreateGitHub,
    required this.hasGitHubToken,
  });

  @override
  Widget build(BuildContext context) {
    final branch = status['branch'] as String? ?? 'unknown';
    final files = status['files'] as List<dynamic>? ?? [];
    final ahead = status['ahead'] as int? ?? 0;
    final behind = status['behind'] as int? ?? 0;
    final remoteWebUrl = status['remote_web_url'] as String?;

    // Categorize files by status
    int staged = 0;
    int modified = 0;
    int untracked = 0;

    for (final file in files) {
      final fileStatus = file['status'] as String? ?? '';
      if (fileStatus == '??') {
        untracked++;
      } else if (fileStatus.startsWith('A') || fileStatus.startsWith('M') || fileStatus.startsWith('D')) {
        if (fileStatus.length == 1 || fileStatus[1] == ' ') {
          staged++;
        } else {
          modified++;
        }
      } else if (fileStatus.contains('M') || fileStatus.contains('D')) {
        modified++;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.code,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Branch: $branch',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (ahead > 0 || behind > 0)
                  Chip(
                    label: Text('$ahead ahead, $behind behind'),
                    avatar: const Icon(Icons.sync, size: 16),
                  ),
              ],
            ),
            if (remoteWebUrl != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(remoteWebUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        remoteWebUrl,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _StatusChip(
                  label: 'Staged',
                  count: staged,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: 'Modified',
                  count: modified,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: 'Untracked',
                  count: untracked,
                  color: Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: files.isNotEmpty ? onCommit : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Commit'),
                ),
                if (remoteWebUrl == null)
                  FilledButton.icon(
                    onPressed: onCreateGitHub,
                    icon: Icon(hasGitHubToken ? Icons.add_circle_outline : Icons.key),
                    label: Text(hasGitHubToken ? 'Create on GitHub' : 'Setup GitHub'),
                    style: FilledButton.styleFrom(
                      backgroundColor: hasGitHubToken
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.orange,
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: onSetRemote,
                    icon: const Icon(Icons.edit),
                    label: const Text('Change Remote'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CommitCard extends StatelessWidget {
  final Map<String, dynamic> commit;

  const _CommitCard({required this.commit});

  @override
  Widget build(BuildContext context) {
    final hash = (commit['hash'] as String?)?.substring(0, 7) ?? '';
    final message = commit['message'] as String? ?? '';
    final author = commit['author'] as String? ?? '';
    final timestamp = commit['timestamp'] as int?;
    final date = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                hash,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$author${date != null ? ' - ${_formatDate(date)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
