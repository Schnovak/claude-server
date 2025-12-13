import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onCreateProject;
  final VoidCallback onOpenSettings;

  const WelcomeScreen({
    super.key,
    required this.onCreateProject,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.rocket_launch_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to Dev Platform',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'AI-powered development with Claude Code',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              _StepCard(
                number: '1',
                title: 'Create a Project',
                description: 'Start by creating your first project to organize your code.',
                icon: Icons.folder_outlined,
                action: FilledButton.icon(
                  onPressed: onCreateProject,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Project'),
                ),
              ),
              const SizedBox(height: 16),
              _StepCard(
                number: '2',
                title: 'Chat with Claude',
                description: 'Ask Claude to help you write code, fix bugs, or explain concepts.',
                icon: Icons.chat_outlined,
              ),
              const SizedBox(height: 16),
              _StepCard(
                number: '3',
                title: 'Manage & Deploy',
                description: 'Run builds, manage files, and use git - all from one place.',
                icon: Icons.build_outlined,
              ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Configure Claude Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final IconData icon;
  final Widget? action;

  const _StepCard({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
