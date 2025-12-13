import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/job.dart';
import '../providers/projects_provider.dart';
import 'jobs_screen.dart';

class ProjectJobsScreen extends StatelessWidget {
  final Project project;

  const ProjectJobsScreen({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectsProvider>(
      builder: (context, provider, _) {
        final jobs = provider.jobs;

        return Scaffold(
          body: jobs.isEmpty
              ? _EmptyJobsView(onRunJob: () => _showRunJobDialog(context))
              : RefreshIndicator(
                  onRefresh: () => provider.loadJobs(project.id),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return _JobCard(
                        job: job,
                        onTap: () => _openJobDetails(context, job),
                        onCancel: job.isActive
                            ? () => provider.cancelJob(job.id)
                            : null,
                      );
                    },
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showRunJobDialog(context),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run Job'),
          ),
        );
      },
    );
  }

  void _openJobDetails(BuildContext context, Job job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JobDetailScreen(job: job),
      ),
    );
  }

  void _showRunJobDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _RunJobDialog(project: project),
    );
  }
}

class _EmptyJobsView extends StatelessWidget {
  final VoidCallback onRunJob;

  const _EmptyJobsView({required this.onRunJob});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No jobs yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Run builds, tests, or custom commands',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRunJob,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run First Job'),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  const _JobCard({
    required this.job,
    required this.onTap,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _StatusIcon(status: job.status),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.type.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (job.command != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        job.command!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(job),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              if (onCancel != null)
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: onCancel,
                  tooltip: 'Cancel',
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(Job job) {
    final time = job.finishedAt ?? job.startedAt ?? job.createdAt;
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatusIcon extends StatelessWidget {
  final JobStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case JobStatus.queued:
        color = Colors.grey;
        icon = Icons.schedule;
        break;
      case JobStatus.running:
        color = Colors.blue;
        icon = Icons.sync;
        break;
      case JobStatus.success:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case JobStatus.failed:
        color = Colors.red;
        icon = Icons.error;
        break;
      case JobStatus.cancelled:
        color = Colors.orange;
        icon = Icons.cancel;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: status == JobStatus.running
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            )
          : Icon(icon, color: color),
    );
  }
}

class _RunJobDialog extends StatefulWidget {
  final Project project;

  const _RunJobDialog({required this.project});

  @override
  State<_RunJobDialog> createState() => _RunJobDialogState();
}

class _RunJobDialogState extends State<_RunJobDialog> {
  JobType _selectedType = JobType.buildApk;
  final _commandController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_selectedType == JobType.customCommand &&
        _commandController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a command');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await context.read<ProjectsProvider>().createJob(
            _selectedType,
            command: _selectedType == JobType.customCommand
                ? _commandController.text.trim()
                : null,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Run Job'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Job Type',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: JobType.values.map((type) {
                final isSelected = type == _selectedType;
                return ChoiceChip(
                  label: Text(type.displayName),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedType = type);
                  },
                );
              }).toList(),
            ),
            if (_selectedType == JobType.customCommand) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., npm run lint',
                  prefixIcon: Icon(Icons.terminal),
                ),
                onSubmitted: (_) => _run(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isLoading ? null : _run,
          icon: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Run'),
        ),
      ],
    );
  }
}
