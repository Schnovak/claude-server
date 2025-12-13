import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/job.dart';
import '../services/api_client.dart';
import 'auth_provider.dart';

class ProjectsProvider extends ChangeNotifier {
  List<Project> _projects = [];
  Project? _selectedProject;
  List<Job> _jobs = [];
  bool _isLoading = false;
  String? _error;

  List<Project> get projects => _projects;
  Project? get selectedProject => _selectedProject;
  List<Job> get jobs => _jobs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void updateAuth(AuthProvider auth) {
    if (auth.isAuthenticated) {
      loadProjects();
    } else {
      _projects = [];
      _selectedProject = null;
      _jobs = [];
      notifyListeners();
    }
  }

  Future<void> loadProjects() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _projects = await apiClient.getProjects();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Project> createProject(String name, ProjectType type) async {
    final project = await apiClient.createProject(name, type);
    _projects.insert(0, project);
    notifyListeners();
    return project;
  }

  Future<void> deleteProject(String projectId) async {
    await apiClient.deleteProject(projectId);
    _projects.removeWhere((p) => p.id == projectId);
    if (_selectedProject?.id == projectId) {
      _selectedProject = null;
    }
    notifyListeners();
  }

  void selectProject(Project? project) {
    _selectedProject = project;
    if (project != null) {
      loadJobs(project.id);
    } else {
      _jobs = [];
    }
    notifyListeners();
  }

  Future<void> loadJobs(String projectId) async {
    try {
      _jobs = await apiClient.getProjectJobs(projectId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<Job> createJob(JobType type, {String? command}) async {
    if (_selectedProject == null) {
      throw Exception('No project selected');
    }
    final job = await apiClient.createJob(
      _selectedProject!.id,
      type,
      command: command,
    );
    _jobs.insert(0, job);
    notifyListeners();
    return job;
  }

  Future<void> refreshJob(String jobId) async {
    final job = await apiClient.getJob(jobId);
    final index = _jobs.indexWhere((j) => j.id == jobId);
    if (index >= 0) {
      _jobs[index] = job;
      notifyListeners();
    }
  }

  Future<void> cancelJob(String jobId) async {
    await apiClient.cancelJob(jobId);
    await refreshJob(jobId);
  }
}
