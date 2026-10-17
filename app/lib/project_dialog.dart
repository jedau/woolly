import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'theme.dart';

class ProjectDraft {
  const ProjectDraft({
    required this.title,
    required this.description,
    required this.startsOn,
    required this.endsOn,
    required this.budget,
    required this.cycles,
    required this.removedCycleIds,
  });

  final String title;
  final String description;
  final String? startsOn;
  final String? endsOn;
  final double budget;
  final List<CycleInput> cycles;
  final List<String> removedCycleIds;
}

class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.project, required this.onSave});

  final Project? project;
  final Future<String?> Function(ProjectDraft draft) onSave;

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _CycleRow {
  _CycleRow({this.id, this.taskCount = 0, String title = '', String allocation = ''})
    : title = TextEditingController(text: title),
      allocation = TextEditingController(text: allocation);

  final String? id;
  final int taskCount;
  final TextEditingController title;
  final TextEditingController allocation;

  void dispose() {
    title.dispose();
    allocation.dispose();
  }
}

class _ProjectDialogState extends State<ProjectDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _budget;
  DateTime? _start;
  DateTime? _end;
  final List<_CycleRow> _cycles = [];
  final List<String> _removed = [];
  var _saving = false;
  String? _error;

  bool get _editing => widget.project != null;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _title = TextEditingController(text: project?.title ?? '');
    _description = TextEditingController(text: project?.description ?? '');
    final cents = project?.budgetCents;
    _budget = TextEditingController(
      text: cents == null ? '' : (cents / 100).toStringAsFixed(2),
    );
    _start = _parseDay(project?.startsOn);
    _end = _parseDay(project?.endsOn);
    for (final cycle in project?.iterations ?? const <Iteration>[]) {
      final row = _CycleRow(
        id: cycle.id,
        taskCount: cycle.tasks.length,
        title: cycle.title,
        allocation: (cycle.payCents / 100).toStringAsFixed(2),
      );
      row.title.addListener(_rebuild);
      row.allocation.addListener(_rebuild);
      _cycles.add(row);
    }
    _title.addListener(_rebuild);
    _budget.addListener(_rebuild);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _budget.dispose();
    for (final cycle in _cycles) {
      cycle.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  DateTime? _parseDay(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String? _iso(DateTime? date) {
    if (date == null) return null;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  int? _cents(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'[\$,]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  bool _blank(_CycleRow cycle) {
    return cycle.id == null &&
        cycle.title.text.trim().isEmpty &&
        cycle.allocation.text.trim().isEmpty;
  }

  int _allocatedCents() {
    var total = 0;
    for (final cycle in _cycles) {
      if (_blank(cycle)) continue;
      total += _cents(cycle.allocation.text) ?? 0;
    }
    return total;
  }

  bool get _showHint {
    if (_editing || _error != null) return true;
    if (_title.text.isNotEmpty || _budget.text.isNotEmpty) return true;
    return _cycles.any((cycle) => !_blank(cycle));
  }

  String? get _blockReason {
    if (_title.text.trim().isEmpty) return 'A project needs a title.';
    final budget = _cents(_budget.text);
    if (budget == null) return 'A project needs a budget.';
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      return 'End date is before the start date.';
    }
    for (final cycle in _cycles) {
      if (_blank(cycle)) continue;
      if (cycle.title.text.trim().isEmpty) return 'Each cycle needs a title.';
      if (_cents(cycle.allocation.text) == null) {
        return 'Each cycle needs an allocation.';
      }
    }
    final allocated = _allocatedCents();
    if (allocated > budget) {
      return 'Allocations are ${money(allocated - budget)} over the budget.';
    }
    return null;
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _start ?? _end ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      if (start) {
        _start = day;
      } else {
        _end = day;
      }
      _error = null;
    });
  }

  Future<void> _removeCycle(int index) async {
    final cycle = _cycles[index];
    if (cycle.id != null) {
      final name = cycle.title.text.trim().isEmpty ? 'this cycle' : cycle.title.text.trim();
      final tasks = cycle.taskCount > 0 ? ' Its tasks go with it.' : '';
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: panel,
          title: const Text('Delete cycle'),
          content: Text('Delete $name?$tasks'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (remove != true || !mounted) return;
      _removed.add(cycle.id!);
    }
    setState(() {
      _cycles.removeAt(index);
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => cycle.dispose());
  }

  Future<void> _save() async {
    if (_saving) return;
    final reason = _blockReason;
    if (reason != null) {
      setState(() => _error = reason);
      return;
    }
    final budgetCents = _cents(_budget.text)!;
    final cycles = <CycleInput>[];
    for (final cycle in _cycles) {
      if (_blank(cycle)) continue;
      cycles.add(
        CycleInput(
          id: cycle.id,
          title: cycle.title.text.trim(),
          allocation: _cents(cycle.allocation.text)! / 100,
        ),
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      ProjectDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        startsOn: _iso(_start),
        endsOn: _iso(_end),
        budget: budgetCents / 100,
        cycles: cycles,
        removedCycleIds: List<String>.from(_removed),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final budget = _cents(_budget.text);
    final allocated = _allocatedCents();
    final over = budget != null && allocated > budget;
    final summary = budget == null
        ? 'Allocated ${money(allocated)}'
        : 'Allocated ${money(allocated)} of ${money(budget)}';
    final reason = _error ?? (_showHint ? _blockReason : null);
    return Dialog(
      backgroundColor: panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width < 560 ? width - 32 : 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85 - 92,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editing ? 'Edit project' : 'New project',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _title,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _description,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _dateField('Start date', _start, true)),
                        const SizedBox(width: 12),
                        Expanded(child: _dateField('End date', _end, false)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _budget,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      decoration: const InputDecoration(
                        labelText: 'Budget',
                        prefixText: '\$ ',
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Cycles',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      style: TextStyle(color: over ? dispute : muted, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The total allocation can\'t exceed the budget.',
                      style: TextStyle(color: muted, fontSize: 13, height: 1.35),
                    ),
                    for (var index = 0; index < _cycles.length; index++) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _cycles[index].title,
                              enabled: !_saving,
                              decoration: const InputDecoration(labelText: 'Cycle'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _cycles[index].allocation,
                              enabled: !_saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Allocation',
                                prefixText: '\$ ',
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Delete cycle',
                            onPressed: _saving ? null : () => _removeCycle(index),
                            icon: const Icon(Icons.delete_outline, size: 18, color: dispute),
                          ),
                        ],
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () {
                                final row = _CycleRow();
                                row.title.addListener(_rebuild);
                                row.allocation.addListener(_rebuild);
                                setState(() => _cycles.add(row));
                              },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add cycle'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_saving) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: amber),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Saving the project.',
                              style: TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else if (reason != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(reason, style: const TextStyle(color: dispute)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _blockReason != null ? null : _save,
                        child: _saving
                            ? const _SavingMark()
                            : Text(_editing ? 'Save' : 'Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, bool start) {
    return InkWell(
      onTap: _saving ? null : () => _pickDate(start: start),
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today, size: 16, color: muted)
              : IconButton(
                  tooltip: 'Clear',
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          if (start) {
                            _start = null;
                          } else {
                            _end = null;
                          }
                        }),
                  icon: const Icon(Icons.close, size: 16, color: muted),
                ),
        ),
        child: SizedBox(
          height: 20,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? '' : formatDay(_iso(value)!),
              style: const TextStyle(height: 1.2),
            ),
          ),
        ),
      ),
    );
  }
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
