import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/api_client.dart';

class JobDetailScreen extends StatefulWidget {
  final Job job;

  const JobDetailScreen({super.key, required this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  String _logs = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _logs = await apiClient.getJobLogs(widget.job.id);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Job: ${widget.job.type.displayName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JobInfoHeader(job: widget.job),
          const Divider(height: 1),
          Expanded(
            child: _buildLogsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsView() {
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
              onPressed: _loadLogs,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text('No logs available'),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black87,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _logs,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Colors.white,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _JobInfoHeader extends StatelessWidget {
  final Job job;

  const _JobInfoHeader({required this.job});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _StatusBadge(status: job.status),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.command != null)
                  Text(
                    job.command!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _buildTimeInfo(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          if (job.status == JobStatus.success || job.status == JobStatus.failed)
            Chip(
              label: Text(job.status == JobStatus.success ? 'Success' : 'Failed'),
              backgroundColor: job.status == JobStatus.success
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
            ),
        ],
      ),
    );
  }

  String _buildTimeInfo() {
    final parts = <String>[];
    parts.add('Created: ${_formatTime(job.createdAt)}');
    if (job.startedAt != null) {
      parts.add('Started: ${_formatTime(job.startedAt!)}');
    }
    if (job.finishedAt != null) {
      parts.add('Completed: ${_formatTime(job.finishedAt!)}');
      if (job.startedAt != null) {
        final duration = job.finishedAt!.difference(job.startedAt!);
        parts.add('Duration: ${_formatDuration(duration)}');
      }
    }
    return parts.join(' | ');
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final JobStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;

    switch (status) {
      case JobStatus.queued:
        color = Colors.grey;
        text = 'Queued';
        break;
      case JobStatus.running:
        color = Colors.blue;
        text = 'Running';
        break;
      case JobStatus.success:
        color = Colors.green;
        text = 'Completed';
        break;
      case JobStatus.failed:
        color = Colors.red;
        text = 'Failed';
        break;
      case JobStatus.cancelled:
        color = Colors.orange;
        text = 'Cancelled';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == JobStatus.running) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
