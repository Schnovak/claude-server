import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/projects_provider.dart';
import '../models/project.dart';
import 'welcome_screen.dart';
import 'project_screen.dart';
import 'settings_screen.dart';
import 'create_project_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectsProvider>().loadProjects();
    });
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  void _showCreateProjectDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateProjectDialog(
        onCreated: (project) {
          _openProject(project);
        },
      ),
    );
  }

  void _openProject(Project project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.projects.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (provider.projects.isEmpty) {
          return WelcomeScreen(
            onCreateProject: _showCreateProjectDialog,
            onOpenSettings: _openSettings,
          );
        }

        return _ProjectListScreen(
          projects: provider.projects,
          onProjectTap: _openProject,
          onCreateProject: _showCreateProjectDialog,
          onOpenSettings: _openSettings,
          onRefresh: () => provider.loadProjects(),
          onDeleteProject: (project) => _confirmDelete(project),
        );
      },
    );
  }

  void _confirmDelete(Project project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Delete "${project.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<ProjectsProvider>().deleteProject(project.id);
              Navigator.pop(context);
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

class _ProjectListScreen extends StatelessWidget {
  final List<Project> projects;
  final void Function(Project) onProjectTap;
  final VoidCallback onCreateProject;
  final VoidCallback onOpenSettings;
  final VoidCallback onRefresh;
  final void Function(Project) onDeleteProject;

  const _ProjectListScreen({
    required this.projects,
    required this.onProjectTap,
    required this.onCreateProject,
    required this.onOpenSettings,
    required this.onRefresh,
    required this.onDeleteProject,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: onOpenSettings,
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => PopupMenuButton(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        auth.user?.displayName.substring(0, 1).toUpperCase() ?? '?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              itemBuilder: (context) => <PopupMenuEntry<dynamic>>[
                PopupMenuItem(
                  enabled: false,
                  child: Text(auth.user?.email ?? ''),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  onTap: () => auth.logout(),
                  child: const Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 8),
                      Text('Logout'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          childAspectRatio: 1.3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          return _ProjectCard(
            project: project,
            onTap: () => onProjectTap(project),
            onDelete: () => onDeleteProject(project),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onCreateProject,
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getProjectIcon(project.type),
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton(
                    iconSize: 20,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: onDelete,
                        child: const Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                project.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      project.type.name.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(project.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getProjectIcon(ProjectType type) {
    switch (type) {
      case ProjectType.flutter:
        return Icons.flutter_dash;
      case ProjectType.web:
        return Icons.web;
      case ProjectType.node:
        return Icons.javascript;
      case ProjectType.python:
        return Icons.code;
      case ProjectType.other:
        return Icons.folder;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}';
    }
  }
}
