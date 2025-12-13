import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../providers/projects_provider.dart';

class CreateProjectDialog extends StatefulWidget {
  final void Function(Project)? onCreated;

  const CreateProjectDialog({super.key, this.onCreated});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _nameController = TextEditingController();
  ProjectType _selectedType = ProjectType.python;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a project name');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final project = await context.read<ProjectsProvider>().createProject(
            _nameController.text.trim(),
            _selectedType,
          );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated?.call(project);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Project'),
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
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              autofocus: true,
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 16),
            Text(
              'Project Type',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ProjectType.values.map((type) {
                final isSelected = type == _selectedType;
                return ChoiceChip(
                  label: Text(type.name.toUpperCase()),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedType = type);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _create,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
