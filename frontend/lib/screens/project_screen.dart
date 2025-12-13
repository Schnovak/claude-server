import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../providers/projects_provider.dart';
import '../providers/claude_provider.dart';
import 'project_chat_screen.dart';
import 'files_screen.dart';
import 'project_jobs_screen.dart';
import 'git_screen.dart';
import 'settings_screen.dart';

class ProjectScreen extends StatefulWidget {
  final Project project;

  const ProjectScreen({super.key, required this.project});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load jobs for this project
      final provider = context.read<ProjectsProvider>();
      provider.selectProject(widget.project);
      provider.loadJobs(widget.project.id);

      // Load Claude settings
      context.read<ClaudeProvider>().loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              _getProjectIcon(widget.project.type),
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(widget.project.name),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ProjectChatScreen(project: widget.project),
          FilesScreen(project: widget.project),
          ProjectJobsScreen(project: widget.project),
          GitScreen(project: widget.project),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code),
            label: 'Git',
          ),
        ],
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
}
