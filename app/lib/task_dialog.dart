import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.description,
    required this.status,
    required this.iterationId,
    required this.assigneeIds,
    required this.shares,
    required this.decision,
    required this.proofSummary,
    required this.proofUrl,
    required this.files,
  });

  final String title;
  final String description;
  final String status;
  final String iterationId;
  final List<String> assigneeIds;
  final List<({String taskId, int percent})> shares;
  final String decision;
  final String proofSummary;
  final String proofUrl;
  final List<({String filename, String contentType, String fileBase64})> files;
}

class TaskDialog extends StatefulWidget {
  const TaskDialog({
    super.key,
    required this.isClient,
    required this.task,
    required this.project,
    required this.cycle,
    required this.projects,
    required this.workers,
    required this.onSave,
  });

  final bool isClient;
  final TaskItem task;
  final Project project;
  final Iteration cycle;
  final List<Project> projects;
  final List<Person> workers;
  final Future<String?> Function(TaskDraft draft) onSave;

  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _Share {
  _Share(this.taskId, this.title, this.percent);
  final String taskId;
  final String title;
  int percent;
}

class _Attachment {
  _Attachment(this.filename, this.contentType, this.bytes);
  final String filename;
  final String contentType;
  final List<int> bytes;
}

class _TaskDialogState extends State<TaskDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _summary;
  late final TextEditingController _link;
  late String _status;
  late String _projectId;
  late String _cycleId;
  late Set<String> _assignees;
  late List<_Share> _shares;
  final List<_Attachment> _files = [];
  var _saving = false;
  String? _error;

  static const _statusOptions = [
    ('open', 'Open'),
    ('revision_needed', 'Revision Needed'),
    ('under_review', 'Under Review'),
    ('complete', 'Complete'),
  ];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task.title);
    _description = TextEditingController(text: widget.task.description);
    _summary = TextEditingController(text: widget.task.proofSummary);
    _link = TextEditingController(text: widget.task.proofUrl);
    _status = _shownStatus(widget.task);
    _projectId = widget.project.id;
    _cycleId = widget.cycle.id;
    _assignees = {for (final person in widget.task.assignees) person.id};
    _shares = _sharesFor(_projectId);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _summary.dispose();
    _link.dispose();
    super.dispose();
  }

  Project? get _project {
    for (final project in widget.projects) {
      if (project.id == _projectId) return project;
    }
    return null;
  }

  int get _poolCents =>
      _project?.iterations.fold<int>(0, (sum, cycle) => sum + cycle.payCents) ??
      0;

  bool get _needsProof => _status == 'complete';

  bool get _canReview => widget.isClient && _shownStatus(widget.task) == 'under_review';

  String? get _blockReason {
    if (_title.text.trim().isEmpty) return 'A task needs a title.';
    if (_cycleId.isEmpty) return 'Choose a cycle.';
    if (_needsProof && _summary.text.trim().isEmpty) {
      return 'A summary of the proof is required.';
    }
    return null;
  }

  List<_Share> _sharesFor(String projectId) {
    Project? project;
    for (final item in widget.projects) {
      if (item.id == projectId) project = item;
    }
    final rows = <({String id, String title, int? bps})>[];
    if (project != null) {
      for (final cycle in project.iterations) {
        for (final task in cycle.tasks) {
          if (task.id == widget.task.id) continue;
          rows.add((id: task.id, title: task.title, bps: task.shareBps));
        }
      }
    }
    rows.add((
      id: widget.task.id,
      title: widget.task.title,
      bps: projectId == widget.project.id ? widget.task.shareBps : null,
    ));
    final percents = _startingPercents([for (final row in rows) row.bps]);
    return [
      for (var index = 0; index < rows.length; index++)
        _Share(rows[index].id, rows[index].title, percents[index]),
    ];
  }

  void _useProject(String projectId) {
    final project = widget.projects.cast<Project?>().firstWhere(
      (item) => item?.id == projectId,
      orElse: () => null,
    );
    final cycles = project?.iterations ?? const <Iteration>[];
    setState(() {
      _projectId = projectId;
      if (!cycles.any((cycle) => cycle.id == _cycleId)) {
        _cycleId = cycles.isEmpty ? '' : cycles.first.id;
      }
      _shares = _sharesFor(projectId);
    });
  }

  void _setShare(int index, int next) {
    if (_shares.length <= 1) {
      if (_shares.isNotEmpty) _shares[0].percent = 100;
      return;
    }
    next = next.clamp(0, 100);
    final weights = [
      for (var i = 0; i < _shares.length; i++)
        i == index ? 0 : _shares[i].percent,
    ];
    final others = [
      for (var i = 0; i < _shares.length; i++)
        if (i != index) i,
    ];
    final scaled = weights.where((value) => value > 0).isEmpty
        ? _equal(others.length, 100 - next)
        : _scale([for (final i in others) _shares[i].percent], 100 - next);
    setState(() {
      _shares[index].percent = next;
      for (var k = 0; k < others.length; k++) {
        _shares[others[k]].percent = scaled[k];
      }
    });
  }

  Future<void> _addFiles() async {
    final picked = await FilePicker.pickFiles();
    if (!mounted || picked.isEmpty) return;
    final added = <_Attachment>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      added.add(_Attachment(file.name, _mime(file.name), bytes));
    }
    if (!mounted) return;
    setState(() => _files.addAll(added));
  }

  Future<void> _submit({String decision = ''}) async {
    if (_saving) return;
    final proofRequired = decision.isEmpty && _needsProof;
    if (_title.text.trim().isEmpty || _cycleId.isEmpty) return;
    if (proofRequired && _summary.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      TaskDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        status: _status,
        iterationId: _cycleId,
        assigneeIds: _assignees.toList(),
        shares: [
          for (final share in _shares)
            (taskId: share.taskId, percent: share.percent),
        ],
        decision: decision,
        proofSummary: _summary.text.trim(),
        proofUrl: _link.text.trim(),
        files: [
          for (final file in _files)
            (
              filename: file.filename,
              contentType: file.contentType,
              fileBase64: base64Encode(file.bytes),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final cycles = project?.iterations ?? const <Iteration>[];
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      backgroundColor: panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SizedBox(
          width: width > 600 ? 560 : width - 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'Edit task',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _title,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _description,
                      enabled: !_saving,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      dropdownColor: panel,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final option in _statusOptions)
                          DropdownMenuItem(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _status = value);
                            },
                    ),
                    if (_needsProof) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.isClient
                            ? 'Marking this complete needs proof.'
                            : 'Sending proof puts this task under review.',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _summary,
                        enabled: !_saving,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Summary',
                          helperText: 'Required to mark the task complete.',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _link,
                        enabled: !_saving,
                        decoration: const InputDecoration(labelText: 'Link'),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _addFiles,
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: const Text('Add attachments'),
                        ),
                      ),
                      if (_files.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final file in _files)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              file.filename,
                              style: const TextStyle(color: ink, fontSize: 13),
                            ),
                          ),
                      ],
                    ] else if (widget.task.proofSummary.isNotEmpty ||
                        widget.task.files.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Proof',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.task.proofSummary,
                        style: const TextStyle(height: 1.35),
                      ),
                      if (widget.task.proofUrl.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.task.proofUrl,
                          style: const TextStyle(color: amber, fontSize: 13),
                        ),
                      ],
                      for (final file in widget.task.files)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            file.filename,
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Assigned to',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (widget.workers.isEmpty)
                      const Text(
                        'No workers yet.',
                        style: TextStyle(color: muted),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final worker in widget.workers)
                            FilterChip(
                              label: Text(worker.name),
                              selected: _assignees.contains(worker.id),
                              showCheckmark: false,
                              selectedColor: amber.withValues(alpha: 0.18),
                              backgroundColor: raised,
                              side: BorderSide(
                                color: _assignees.contains(worker.id)
                                    ? amber
                                    : line,
                              ),
                              labelStyle: TextStyle(
                                color: _assignees.contains(worker.id)
                                    ? amber
                                    : ink,
                              ),
                              onSelected: _saving
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected) {
                                        _assignees.add(worker.id);
                                      } else {
                                        _assignees.remove(worker.id);
                                      }
                                    }),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue:
                          widget.projects.any((item) => item.id == _projectId)
                          ? _projectId
                          : null,
                      dropdownColor: panel,
                      decoration: const InputDecoration(labelText: 'Project'),
                      items: [
                        for (final item in widget.projects)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.title),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              _useProject(value);
                            },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey('$_projectId|$_cycleId'),
                      initialValue: cycles.any((cycle) => cycle.id == _cycleId)
                          ? _cycleId
                          : null,
                      dropdownColor: panel,
                      decoration: const InputDecoration(labelText: 'Cycle'),
                      items: [
                        for (final cycle in cycles)
                          DropdownMenuItem(
                            value: cycle.id,
                            child: Text(cycle.title),
                          ),
                      ],
                      onChanged: _saving || cycles.isEmpty
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _cycleId = value);
                            },
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Allocation',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'These tasks share ${money(_poolCents)}. The shares add up to 100%.',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < _shares.length; index++) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _shares[index].taskId == widget.task.id
                                  ? (_title.text.trim().isEmpty
                                        ? widget.task.title
                                        : _title.text.trim())
                                  : _shares[index].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight:
                                    _shares[index].taskId == widget.task.id
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${_shares[index].percent}% · ${money((_poolCents * _shares[index].percent / 100).round())}',
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                      Slider(
                        value: _shares[index].percent.toDouble(),
                        max: 100,
                        divisions: 100,
                        activeColor: amber,
                        inactiveColor: line,
                        onChanged: _saving || _shares.length <= 1
                            ? null
                            : (value) => _setShare(index, value.round()),
                      ),
                    ],
                    if (_canReview) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _submit(decision: 'revise'),
                              child: const Text('Ask to revise'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => _submit(decision: 'approve'),
                              style: FilledButton.styleFrom(
                                backgroundColor: amber,
                                foregroundColor: bg,
                              ),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_saving)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: amber,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Saving the task.',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      )
                    else if (_error != null || _blockReason != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _error ?? _blockReason!,
                          style: const TextStyle(color: dispute, height: 1.35),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saving || _blockReason != null
                              ? null
                              : () => _submit(),
                          style: FilledButton.styleFrom(
                            backgroundColor: amber,
                            foregroundColor: bg,
                            disabledBackgroundColor: raised,
                            disabledForegroundColor: muted,
                          ),
                          child: _saving
                              ? const _SavingMark()
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _shownStatus(TaskItem task) {
  switch (task.status) {
    case 'complete':
    case 'under_review':
    case 'revision_needed':
      return task.status;
  }
  final statuses = task.subtasks.map((item) => item.status).toList();
  if (statuses.isNotEmpty && statuses.every((item) => item == 'Credited')) {
    return 'complete';
  }
  if (statuses.contains('In review')) return 'under_review';
  if (task.review == 'needs_revision') return 'revision_needed';
  return 'open';
}

List<int> _startingPercents(List<int?> bps) {
  if (bps.isEmpty) return const [];
  if (bps.every((value) => value == null)) return _equal(bps.length, 100);
  if (bps.every((value) => value != null)) {
    return _scale([for (final value in bps) value!], 100);
  }
  final newcomers = bps.where((value) => value == null).length;
  final reserved = (100 * newcomers / bps.length).round().clamp(0, 100);
    final known = _scale([for (final value in bps) ?value], 100 - reserved);
  final eachNew = newcomers == 0 ? 0 : reserved ~/ newcomers;
  final result = <int>[];
  var knownIndex = 0;
  for (final value in bps) {
    if (value == null) {
      result.add(eachNew);
    } else {
      result.add(known[knownIndex]);
      knownIndex += 1;
    }
  }
  return _fix(result, 100);
}

List<int> _equal(int count, int whole) {
  if (count <= 0) return const [];
  final base = whole ~/ count;
  final extra = whole - base * count;
  return [
    for (var index = 0; index < count; index++)
      base + (index >= count - extra ? 1 : 0),
  ];
}

List<int> _scale(List<int> weights, int target) {
  if (weights.isEmpty) return const [];
  if (target <= 0) return List.filled(weights.length, 0);
  final total = weights.fold<int>(0, (sum, value) => sum + value);
  if (total <= 0) return _equal(weights.length, target);
  final raw = [for (final weight in weights) weight * target / total];
  final floors = [for (final value in raw) value.floor()];
  final order = List.generate(weights.length, (index) => index)
    ..sort((a, b) => (raw[b] - floors[b]).compareTo(raw[a] - floors[a]));
  var left = target - floors.fold<int>(0, (sum, value) => sum + value);
  for (final index in order) {
    if (left <= 0) break;
    floors[index] += 1;
    left -= 1;
  }
  return floors;
}

List<int> _fix(List<int> values, int target) {
  if (values.isEmpty) return values;
  final next = [...values];
  next[0] += target - next.fold<int>(0, (sum, value) => sum + value);
  return next;
}

String _mime(String name) {
  final extension = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  return switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

class _SavingMark extends StatelessWidget {
  const _SavingMark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: bg),
        ),
        SizedBox(width: 8),
        Text('Saving…'),
      ],
    );
  }
}
