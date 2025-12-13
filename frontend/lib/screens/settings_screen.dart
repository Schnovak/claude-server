import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/claude_provider.dart';
import '../models/claude_settings.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Claude'),
              Tab(icon: Icon(Icons.extension_outlined), text: 'Plugins'),
              Tab(icon: Icon(Icons.person_outline), text: 'Account'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ClaudeSettingsTab(),
            _PluginMarketplaceTab(),
            _AccountTab(),
          ],
        ),
      ),
    );
  }
}

// ==================== Claude Settings Tab ====================

class _ClaudeSettingsTab extends StatefulWidget {
  const _ClaudeSettingsTab();

  @override
  State<_ClaudeSettingsTab> createState() => _ClaudeSettingsTabState();
}

class _ClaudeSettingsTabState extends State<_ClaudeSettingsTab> {
  final _systemPromptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _githubTokenController = TextEditingController();
  String? _selectedModel;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _isSavingApiKey = false;
  bool _isSavingGitHubToken = false;
  bool _showApiKey = false;
  bool _showGitHubToken = false;
  bool _hasGitHubToken = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClaudeProvider>().loadSettings();
      _loadCurrentSettings();
      _loadGitHubTokenStatus();
    });
  }

  void _loadCurrentSettings() {
    if (!mounted) return;
    final provider = context.read<ClaudeProvider>();
    final settings = provider.settings;
    if (settings != null) {
      setState(() {
        _systemPromptController.text = settings.systemPrompt ?? '';
        _selectedModel = settings.defaultModel;
      });
    }
  }

  Future<void> _loadGitHubTokenStatus() async {
    try {
      final hasToken = await apiClient.getGitHubTokenStatus();
      if (mounted) {
        setState(() => _hasGitHubToken = hasToken);
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _systemPromptController.dispose();
    _apiKeyController.dispose();
    _githubTokenController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    setState(() => _isSavingApiKey = true);

    try {
      await context.read<ClaudeProvider>().setApiKey(apiKey);
      _apiKeyController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API key saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingApiKey = false);
    }
  }

  Future<void> _saveGitHubToken() async {
    final token = _githubTokenController.text.trim();
    if (token.isEmpty) return;

    setState(() => _isSavingGitHubToken = true);

    try {
      await apiClient.setGitHubToken(token);
      _githubTokenController.clear();
      setState(() {
        _hasGitHubToken = true;
        _showGitHubToken = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GitHub token saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingGitHubToken = false);
    }
  }

  Future<void> _removeGitHubToken() async {
    try {
      await apiClient.removeGitHubToken();
      setState(() {
        _hasGitHubToken = false;
        _showGitHubToken = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GitHub token removed')),
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

  Future<void> _saveSettings() async {
    final provider = context.read<ClaudeProvider>();
    final currentSettings = provider.settings;
    if (currentSettings == null) return;

    setState(() => _isSaving = true);

    try {
      final updated = currentSettings.copyWith(
        defaultModel: _selectedModel ?? currentSettings.defaultModel,
        systemPrompt: _systemPromptController.text.isEmpty
            ? null
            : _systemPromptController.text,
      );

      await provider.updateSettings(updated);
      setState(() => _isDirty = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClaudeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${provider.error}'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => provider.loadSettings(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final settings = provider.settings;
        if (settings == null) {
          return const Center(child: Text('No settings available'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // API Key
              _SettingsCard(
                title: 'API Key',
                subtitle: provider.hasApiKey
                    ? 'API key is configured'
                    : 'Enter your Anthropic API key to use Claude',
                icon: Icons.key,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider.hasApiKey)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('API key is configured'),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _showApiKey = true),
                              child: const Text('Update'),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('API key required'),
                            ),
                          ],
                        ),
                      ),
                    if (!provider.hasApiKey || _showApiKey) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Anthropic API Key',
                          hintText: 'sk-ant-...',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_showApiKey)
                            TextButton(
                              onPressed: () => setState(() => _showApiKey = false),
                              child: const Text('Cancel'),
                            ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _isSavingApiKey ? null : _saveApiKey,
                            child: _isSavingApiKey
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Save API Key'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // GitHub Token
              _SettingsCard(
                title: 'GitHub Token',
                subtitle: _hasGitHubToken
                    ? 'GitHub Personal Access Token is configured'
                    : 'Required for "Create on GitHub" feature',
                icon: Icons.code,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasGitHubToken)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('GitHub token configured'),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _showGitHubToken = true),
                              child: const Text('Update'),
                            ),
                            TextButton(
                              onPressed: _removeGitHubToken,
                              child: Text(
                                'Remove',
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Token needed for GitHub integration'),
                            ),
                          ],
                        ),
                      ),
                    if (!_hasGitHubToken || _showGitHubToken) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _githubTokenController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'GitHub Personal Access Token',
                          hintText: 'ghp_...',
                          helperText: 'Create at GitHub → Settings → Developer settings → Personal access tokens',
                          helperMaxLines: 2,
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_showGitHubToken)
                            TextButton(
                              onPressed: () => setState(() => _showGitHubToken = false),
                              child: const Text('Cancel'),
                            ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _isSavingGitHubToken ? null : _saveGitHubToken,
                            child: _isSavingGitHubToken
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Save Token'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Model Selection
              _SettingsCard(
                title: 'Model',
                subtitle: 'Select the Claude model to use',
                icon: Icons.psychology,
                child: DropdownButtonFormField<String>(
                  value: _selectedModel ?? settings.defaultModel,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: provider.availableModels.isEmpty
                      ? [
                          DropdownMenuItem(
                            value: settings.defaultModel,
                            child: Text(settings.defaultModel),
                          ),
                        ]
                      : provider.availableModels.map((model) {
                          return DropdownMenuItem(
                            value: model,
                            child: Text(model),
                          );
                        }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedModel = value;
                        _isDirty = true;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // System Prompt
              _SettingsCard(
                title: 'System Prompt',
                subtitle: 'Customize Claude\'s behavior and context',
                icon: Icons.description,
                child: TextField(
                  controller: _systemPromptController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter a custom system prompt...',
                  ),
                  maxLines: 6,
                  onChanged: (_) {
                    if (!_isDirty) setState(() => _isDirty = true);
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Save Button
              if (_isDirty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save Changes'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ==================== Plugin Marketplace Tab ====================

class _PluginMarketplaceTab extends StatefulWidget {
  const _PluginMarketplaceTab();

  @override
  State<_PluginMarketplaceTab> createState() => _PluginMarketplaceTabState();
}

class _PluginMarketplaceTabState extends State<_PluginMarketplaceTab> {
  final _searchController = TextEditingController();
  bool _showInstalled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClaudeProvider>().loadPlugins();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and Filter Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search plugins...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (query) {
                    if (query.isNotEmpty) {
                      context.read<ClaudeProvider>().searchPlugins(query);
                      setState(() => _showInstalled = false);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Installed')),
                  ButtonSegment(value: false, label: Text('Browse')),
                ],
                selected: {_showInstalled},
                onSelectionChanged: (selection) {
                  setState(() => _showInstalled = selection.first);
                  if (selection.first) {
                    context.read<ClaudeProvider>().loadPlugins();
                  }
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Plugin List
        Expanded(
          child: Consumer<ClaudeProvider>(
            builder: (context, provider, _) {
              final plugins = _showInstalled
                  ? provider.installedPlugins
                  : provider.searchResults;

              if (plugins.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _showInstalled
                            ? Icons.extension_off
                            : Icons.search_off,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _showInstalled
                            ? 'No plugins installed'
                            : 'No plugins found',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _showInstalled
                            ? 'Search for plugins to install'
                            : 'Try a different search term',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: plugins.length,
                itemBuilder: (context, index) {
                  final plugin = plugins[index];
                  return _PluginCard(
                    plugin: plugin,
                    onInstall: plugin.installed
                        ? null
                        : () => provider.installPlugin(plugin.name),
                    onUninstall: plugin.installed
                        ? () => _confirmUninstall(context, plugin.name)
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmUninstall(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall Plugin'),
        content: Text('Uninstall "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<ClaudeProvider>().uninstallPlugin(name);
              Navigator.pop(context);
            },
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  final ClaudePlugin plugin;
  final VoidCallback? onInstall;
  final VoidCallback? onUninstall;

  const _PluginCard({
    required this.plugin,
    this.onInstall,
    this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.extension,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plugin.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (plugin.version != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'v${plugin.version}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (plugin.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      plugin.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onInstall != null)
              FilledButton(
                onPressed: onInstall,
                child: const Text('Install'),
              )
            else if (onUninstall != null)
              OutlinedButton(
                onPressed: onUninstall,
                child: const Text('Uninstall'),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== Account Tab ====================

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.user;
        if (user == null) {
          return const Center(child: Text('Not logged in'));
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // User Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          user.displayName.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(user.role.toUpperCase()),
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Account Actions
              _SettingsCard(
                title: 'Account',
                icon: Icons.person,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Logout'),
                      subtitle: const Text('Sign out of your account'),
                      onTap: () {
                        auth.logout();
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==================== Shared Widgets ====================

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  const _SettingsCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
