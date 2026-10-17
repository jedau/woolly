class Person {
  const Person({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;

  bool get isClient => role == 'client';

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }
}

class WoollyLink {
  const WoollyLink({required this.url, required this.label});

  final String url;
  final String label;

  factory WoollyLink.fromJson(Map<String, dynamic> json) {
    return WoollyLink(
      url: json['url'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

class Decision {
  const Decision({required this.outcome, required this.note});

  final String outcome;
  final String note;

  factory Decision.fromJson(Map<String, dynamic> json) {
    return Decision(
      outcome: json['outcome'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }
}

class Completion {
  const Completion({
    required this.id,
    required this.summary,
    required this.links,
    required this.modelOutcome,
    required this.modelReason,
    required this.decision,
  });

  final String id;
  final String summary;
  final List<WoollyLink> links;
  final String? modelOutcome;
  final String? modelReason;
  final Decision? decision;

  factory Completion.fromJson(Map<String, dynamic> json) {
    return Completion(
      id: json['id'] as String,
      summary: json['summary'] as String? ?? '',
      links: (json['links'] as List? ?? const [])
          .map((item) => WoollyLink.fromJson(item as Map<String, dynamic>))
          .toList(),
      modelOutcome: json['modelOutcome'] as String?,
      modelReason: json['modelReason'] as String?,
      decision: json['decision'] == null
          ? null
          : Decision.fromJson(json['decision'] as Map<String, dynamic>),
    );
  }
}

class Subtask {
  const Subtask({
    required this.id,
    required this.title,
    required this.description,
    required this.effort,
    required this.value,
    required this.links,
    required this.completion,
  });

  final String id;
  final String title;
  final String description;
  final double effort;
  final double value;
  final List<WoollyLink> links;
  final Completion? completion;

  String get status {
    final decision = completion?.decision?.outcome;
    if (decision == 'credit') return 'Credited';
    if (decision == 'dispute') return 'Disputed';
    if (completion != null) return 'In review';
    return 'Open';
  }

  factory Subtask.fromJson(Map<String, dynamic> json) {
    return Subtask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      effort: (json['effort'] as num?)?.toDouble() ?? 1,
      value: (json['value'] as num?)?.toDouble() ?? 1,
      links: (json['links'] as List? ?? const [])
          .map((item) => WoollyLink.fromJson(item as Map<String, dynamic>))
          .toList(),
      completion: json['completion'] == null
          ? null
          : Completion.fromJson(json['completion'] as Map<String, dynamic>),
    );
  }
}

class TaskFile {
  const TaskFile({required this.filename, required this.url});

  final String filename;
  final String url;

  factory TaskFile.fromJson(Map<String, dynamic> json) {
    return TaskFile(
      filename: json['filename'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.review,
    required this.status,
    required this.shareBps,
    required this.proofSummary,
    required this.proofUrl,
    required this.links,
    required this.files,
    required this.assignees,
    required this.subtasks,
  });

  final String id;
  final String title;
  final String description;
  final String review;
  final String status;
  final int? shareBps;
  final String proofSummary;
  final String proofUrl;
  final List<WoollyLink> links;
  final List<TaskFile> files;
  final List<Person> assignees;
  final List<Subtask> subtasks;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    return TaskItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      review: json['review'] as String? ?? 'open',
      status: json['status'] as String? ?? 'open',
      shareBps: (json['shareBps'] as num?)?.toInt(),
      proofSummary: json['proofSummary'] as String? ?? '',
      proofUrl: json['proofUrl'] as String? ?? '',
      links: (json['links'] as List? ?? const [])
          .map((item) => WoollyLink.fromJson(item as Map<String, dynamic>))
          .toList(),
      files: (json['files'] as List? ?? const [])
          .map((item) => TaskFile.fromJson(item as Map<String, dynamic>))
          .toList(),
      assignees: (json['assignees'] as List? ?? const [])
          .map(
            (item) => Person.fromJson({
              ...item as Map<String, dynamic>,
              'role': 'worker',
            }),
          )
          .toList(),
      subtasks: (json['subtasks'] as List? ?? const [])
          .map((item) => Subtask.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Iteration {
  const Iteration({
    required this.id,
    required this.title,
    required this.payCents,
    required this.deadline,
    required this.brief,
    required this.status,
    required this.acceptedCents,
    required this.projectedCents,
    required this.tasks,
  });

  final String id;
  final String title;
  final int payCents;
  final String? deadline;
  final String brief;
  final String status;
  final int acceptedCents;
  final int projectedCents;
  final List<TaskItem> tasks;

  bool get locked => status == 'locked';

  factory Iteration.fromJson(Map<String, dynamic> json) {
    return Iteration(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      payCents: (json['payCents'] as num?)?.round() ?? 0,
      deadline: json['deadline'] as String?,
      brief: json['brief'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      acceptedCents: (json['acceptedCents'] as num?)?.round() ?? 0,
      projectedCents: (json['projectedCents'] as num?)?.round() ?? 0,
      tasks: (json['tasks'] as List? ?? const [])
          .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Project {
  const Project({
    required this.id,
    required this.title,
    required this.description,
    required this.startsOn,
    required this.endsOn,
    required this.budgetCents,
    required this.clientName,
    required this.workerId,
    required this.workerName,
    required this.iterations,
  });

  final String id;
  final String title;
  final String description;
  final String? startsOn;
  final String? endsOn;
  final int? budgetCents;
  final String clientName;
  final String workerId;
  final String workerName;
  final List<Iteration> iterations;

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      startsOn: json['startsOn'] as String?,
      endsOn: json['endsOn'] as String?,
      budgetCents: (json['budgetCents'] as num?)?.round(),
      clientName: json['clientName'] as String? ?? '',
      workerId: json['workerId'] as String? ?? '',
      workerName: json['workerName'] as String? ?? '',
      iterations: (json['iterations'] as List? ?? const [])
          .map((item) => Iteration.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Workspace {
  const Workspace({
    required this.person,
    required this.workers,
    required this.projects,
  });

  final Person person;
  final List<Person> workers;
  final List<Project> projects;

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      person: Person.fromJson(json['person'] as Map<String, dynamic>),
      workers: (json['workers'] as List? ?? const [])
          .map(
            (item) => Person.fromJson({
              ...item as Map<String, dynamic>,
              'role': 'worker',
            }),
          )
          .toList(),
      projects: (json['projects'] as List? ?? const [])
          .map((item) => Project.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

String money(int cents) {
  final absolute = cents.abs();
  final dollars = absolute ~/ 100;
  final remainder = (absolute % 100).toString().padLeft(2, '0');
  return '\$$dollars.$remainder';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDay(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  return '${parsed.day} ${_months[parsed.month - 1]} ${parsed.year}';
}

String? dateSpan(String? start, String? end) {
  final startLabel = start == null || start.isEmpty ? null : formatDay(start);
  final endLabel = end == null || end.isEmpty ? null : formatDay(end);
  if (startLabel != null && endLabel != null) return '$startLabel – $endLabel';
  return startLabel ?? endLabel;
}
