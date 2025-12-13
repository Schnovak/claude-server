enum JobType {
  buildApk,
  buildWeb,
  devServer,
  test,
  customCommand;

  static JobType fromString(String value) {
    switch (value) {
      case 'build_apk':
        return JobType.buildApk;
      case 'build_web':
        return JobType.buildWeb;
      case 'dev_server':
        return JobType.devServer;
      case 'test':
        return JobType.test;
      case 'custom_command':
        return JobType.customCommand;
      default:
        return JobType.customCommand;
    }
  }

  String toApiString() {
    switch (this) {
      case JobType.buildApk:
        return 'build_apk';
      case JobType.buildWeb:
        return 'build_web';
      case JobType.devServer:
        return 'dev_server';
      case JobType.test:
        return 'test';
      case JobType.customCommand:
        return 'custom_command';
    }
  }

  String get displayName {
    switch (this) {
      case JobType.buildApk:
        return 'Build APK';
      case JobType.buildWeb:
        return 'Build Web';
      case JobType.devServer:
        return 'Dev Server';
      case JobType.test:
        return 'Run Tests';
      case JobType.customCommand:
        return 'Custom Command';
    }
  }
}

enum JobStatus {
  queued,
  running,
  success,
  failed,
  cancelled;

  static JobStatus fromString(String value) {
    return JobStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => JobStatus.queued,
    );
  }
}

class Job {
  final String id;
  final String projectId;
  final String ownerId;
  final JobType type;
  final JobStatus status;
  final String? command;
  final String? logPath;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final Map<String, dynamic>? metadata;

  Job({
    required this.id,
    required this.projectId,
    required this.ownerId,
    required this.type,
    required this.status,
    this.command,
    this.logPath,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.metadata,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'],
      projectId: json['project_id'],
      ownerId: json['owner_id'],
      type: JobType.fromString(json['type']),
      status: JobStatus.fromString(json['status']),
      command: json['command'],
      logPath: json['log_path'],
      createdAt: DateTime.parse(json['created_at']),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'])
          : null,
      finishedAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'])
          : null,
      metadata: json['metadata_json'],
    );
  }

  bool get isActive => status == JobStatus.queued || status == JobStatus.running;
}
