import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class TaskProposal {
  const TaskProposal({
    required this.title,
    required this.description,
    required this.projectId,
    required this.iterationId,
    this.note = '',
    this.review = 'open',
  });

  final String title;
  final String description;
  final String projectId;
  final String iterationId;
  final String note;
  final String review;

  factory TaskProposal.fromJson(Map<String, dynamic> json) {
    return TaskProposal(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      iterationId: json['iterationId'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }
}

class CycleInput {
  const CycleInput({this.id, required this.title, required this.allocation});

  final String? id;
  final String title;
  final double allocation;
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WoollyApi {
  WoollyApi({http.Client? client, this.base = 'http://localhost:8787'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String base;

  Future<List<Person>> people() async {
    final body = await _send('GET', '/api/people');
    return (body['people'] as List)
        .map((item) => Person.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> workspace(String personId) async {
    final body = await _send('GET', '/api/workspace?personId=$personId');
    return Workspace.fromJson(body['workspace'] as Map<String, dynamic>);
  }

  Future<Workspace> createProject({
    required String personId,
    required String title,
    required String description,
    String? startsOn,
    String? endsOn,
    required double budget,
    List<CycleInput> cycles = const [],
  }) {
    return _workspace('POST', '/api/projects', {
      'personId': personId,
      'title': title,
      'description': description,
      'startsOn': startsOn,
      'endsOn': endsOn,
      'budget': budget,
      'cycles': [
        for (final cycle in cycles)
          {
            if (cycle.id != null) 'id': cycle.id,
            'title': cycle.title,
            'allocation': cycle.allocation,
          },
      ],
    });
  }

  Future<Workspace> updateProject(
    String projectId, {
    required String personId,
    required String title,
    required String description,
    String? startsOn,
    String? endsOn,
    required double budget,
    List<CycleInput> cycles = const [],
    List<String> removedCycleIds = const [],
  }) {
    return _workspace('PATCH', '/api/projects/$projectId', {
      'personId': personId,
      'title': title,
      'description': description,
      'startsOn': startsOn,
      'endsOn': endsOn,
      'budget': budget,
      'removedCycleIds': removedCycleIds,
      'cycles': [
        for (final cycle in cycles)
          {
            if (cycle.id != null) 'id': cycle.id,
            'title': cycle.title,
            'allocation': cycle.allocation,
          },
      ],
    });
  }

  Future<Workspace> deleteProject(
    String projectId, {
    required String personId,
  }) {
    return _workspace('DELETE', '/api/projects/$projectId?personId=$personId');
  }

  Future<Workspace> createIteration(
    String projectId, {
    required String title,
    required double pay,
    String? deadline,
    String brief = '',
  }) {
    return _workspace('POST', '/api/projects/$projectId/iterations', {
      'title': title,
      'pay': pay,
      'deadline': deadline,
      'brief': brief,
    });
  }

  Future<Workspace> draft(String iterationId, String brief) {
    return _workspace('POST', '/api/iterations/$iterationId/draft', {
      'brief': brief,
    });
  }

  Future<List<TaskProposal>> proposeTasks(
    String personId,
    String summary,
  ) async {
    final body = await _send('POST', '/api/tasks/propose', {
      'personId': personId,
      'summary': summary,
    });
    return (body['proposals'] as List)
        .map((item) => TaskProposal.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> acceptTasks(String personId, List<TaskProposal> tasks) {
    return _workspace('POST', '/api/tasks/accept', {
      'personId': personId,
      'tasks': [
        for (final task in tasks)
          {
            'title': task.title,
            'description': task.description,
            'iterationId': task.iterationId,
            'review': task.review,
          },
      ],
    });
  }

  Future<Workspace> addTask(
    String iterationId, {
    required String title,
    required String description,
    String? link,
  }) {
    return _workspace('POST', '/api/iterations/$iterationId/tasks', {
      'title': title,
      'description': description,
      'links': link == null || link.isEmpty
          ? const []
          : [
              {'url': link, 'label': ''},
            ],
    });
  }

  Future<Workspace> addSubtask(
    String taskId, {
    required String title,
    required String description,
    required double effort,
    required double value,
    String? link,
  }) {
    return _workspace('POST', '/api/tasks/$taskId/subtasks', {
      'title': title,
      'description': description,
      'effort': effort,
      'value': value,
      'links': link == null || link.isEmpty
          ? const []
          : [
              {'url': link, 'label': ''},
            ],
    });
  }

  Future<Workspace> updateTask(
    String taskId, {
    required String personId,
    required String title,
    required String description,
    required String status,
    required String iterationId,
    required List<String> assigneeIds,
    required List<Map<String, dynamic>> shares,
    String decision = '',
    String proofSummary = '',
    String proofUrl = '',
    List<Map<String, String>> files = const [],
  }) {
    return _workspace('PATCH', '/api/tasks/$taskId', {
      'personId': personId,
      'title': title,
      'description': description,
      'status': status,
      'iterationId': iterationId,
      'assigneeIds': assigneeIds,
      'shares': shares,
      'decision': decision,
      'proofSummary': proofSummary,
      'proofUrl': proofUrl,
      'files': files,
    });
  }

  Future<Workspace> updateSubtask(
    String subtaskId, {
    required String title,
    required String description,
    required double effort,
    required double value,
  }) {
    return _workspace('PATCH', '/api/subtasks/$subtaskId', {
      'title': title,
      'description': description,
      'effort': effort,
      'value': value,
    });
  }

  Future<Workspace> deleteTask(String taskId) =>
      _workspace('DELETE', '/api/tasks/$taskId');

  Future<Workspace> deleteSubtask(String subtaskId) =>
      _workspace('DELETE', '/api/subtasks/$subtaskId');

  Future<Workspace> lock(String iterationId) =>
      _workspace('POST', '/api/iterations/$iterationId/lock');

  Future<Workspace> submitProof(
    String subtaskId, {
    required String summary,
    String? link,
    String? filename,
    String? contentType,
    String? fileBase64,
  }) {
    return _workspace('POST', '/api/subtasks/$subtaskId/completion', {
      'summary': summary,
      'link': link ?? '',
      'filename': filename,
      'contentType': contentType,
      'fileBase64': fileBase64,
    });
  }

  Future<Workspace> review(String completionId) =>
      _workspace('POST', '/api/completions/$completionId/review');

  Future<Workspace> decide(String completionId, {required String outcome}) {
    return _workspace('POST', '/api/completions/$completionId/decide', {
      'outcome': outcome,
    });
  }

  Future<Workspace> _workspace(
    String method,
    String path, [
    Map<String, dynamic>? jsonBody,
  ]) async {
    final body = await _send(method, path, jsonBody);
    return Workspace.fromJson(body['workspace'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? jsonBody,
  ]) async {
    final uri = Uri.parse('$base$path');
    final headers = {'content-type': 'application/json'};
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
      case 'POST':
        response = await _client.post(
          uri,
          headers: headers,
          body: jsonEncode(jsonBody ?? const {}),
        );
      case 'PATCH':
        response = await _client.patch(
          uri,
          headers: headers,
          body: jsonEncode(jsonBody ?? const {}),
        );
      case 'DELETE':
        response = await _client.delete(uri, headers: headers);
      default:
        throw ApiException('Unsupported method $method');
    }
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected response from the server.');
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        decoded['error'] as String? ??
            'Request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }
}
