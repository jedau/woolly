import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'theme.dart';

class SummaryDialog extends StatefulWidget {
  const SummaryDialog({
    super.key,
    required this.projects,
    required this.onPropose,
    required this.onAccept,
  });

  final List<Project> projects;
  final Future<List<TaskProposal>> Function(String summary) onPropose;
  final Future<void> Function(List<TaskProposal> tasks) onAccept;

  @override
  State<SummaryDialog> createState() => _SummaryDialogState();
}

class _ProposalDraft {
  _ProposalDraft.from(TaskProposal proposal)
    : title = TextEditingController(text: proposal.title),
      description = TextEditingController(text: proposal.description),
      projectId = proposal.projectId,
      iterationId = proposal.iterationId,
      note = proposal.note;

  final TextEditingController title;
  final TextEditingController description;
  String projectId;
  String iterationId;
  final String note;
  String? decision;

  void dispose() {
    title.dispose();
    description.dispose();
  }
}

class _SummaryDialogState extends State<SummaryDialog> {
  final _summary = TextEditingController();
  final List<_ProposalDraft> _drafts = [];
  var _reviewing = false;
  var _busy = false;
  var _index = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _summary.addListener(_rebuild);
  }

  @override
  void dispose() {
    _summary.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  List<Iteration> _cycles(String projectId) {
    final project = widget.projects
        .where((item) => item.id == projectId)
        .firstOrNull;
    if (project == null) return const [];
    return project.iterations;
  }

  void _keep(_ProposalDraft draft) {
    draft.title.addListener(_rebuild);
    draft.description.addListener(_rebuild);
  }

  void _drop(_ProposalDraft draft) {
    draft.title.removeListener(_rebuild);
    draft.description.removeListener(_rebuild);
    draft.dispose();
  }

  Future<void> _propose() async {
    final summary = _summary.text.trim();
    if (summary.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final proposals = await widget.onPropose(summary);
      if (!mounted) return;
      for (final draft in _drafts) {
        _drop(draft);
      }
      _drafts.clear();
      for (final proposal in proposals) {
        final draft = _ProposalDraft.from(proposal);
        final cycles = _cycles(draft.projectId);
        if (!cycles.any((cycle) => cycle.id == draft.iterationId)) {
          draft.iterationId = '';
        }
        _keep(draft);
        _drafts.add(draft);
      }
      if (_drafts.isEmpty) {
        setState(() {
          _error = 'No tasks came back. Try a more specific summary.';
          _busy = false;
        });
        return;
      }
      setState(() {
        _index = 0;
        _reviewing = true;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  bool _placed(_ProposalDraft draft) {
    final cycles = _cycles(draft.projectId);
    return draft.title.text.trim().isNotEmpty &&
        draft.description.text.trim().isNotEmpty &&
        cycles.any((cycle) => cycle.id == draft.iterationId);
  }

  bool get _ready {
    if (_drafts.isEmpty) return false;
    return _drafts.every((draft) => draft.decision != null && _placed(draft));
  }

  int get _marked => _drafts.where((draft) => draft.decision != null).length;

  Future<void> _accept() async {
    if (_busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAccept([
        for (final draft in _drafts)
          TaskProposal(
            title: draft.title.text.trim(),
            description: draft.description.text.trim(),
            projectId: draft.projectId,
            iterationId: draft.iterationId,
            review: draft.decision ?? 'open',
          ),
      ]);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      backgroundColor: panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width < 560 ? width - 32 : 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: _reviewing ? _review() : _ask(),
        ),
      ),
    );
  }

  Widget _ask() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Add tasks',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Describe the work. The project and cycle are read from what you write.',
          style: TextStyle(color: muted, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _summary,
          enabled: !_busy,
          minLines: 5,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Summary'),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: amber),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reading the summary. This can take a minute.',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: dispute, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy || _summary.text.trim().isEmpty ? null : _propose,
              child: const Text('Propose'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _review() {
    final index = _index.clamp(0, _drafts.length - 1);
    final draft = _drafts[index];
    final several = _drafts.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Review tasks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${index + 1} of ${_drafts.length}',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _marked < _drafts.length
              ? '$_marked of ${_drafts.length} marked. Confirm once each task is approved or needs revision.'
              : _ready
              ? 'Each task is marked. Confirm to add them.'
              : 'Each task is marked. Choose a project and cycle before confirming.',
          style: const TextStyle(color: muted, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 12),
        _proposal(draft),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _decision(draft, 'Approve', 'open', credit)),
            const SizedBox(width: 8),
            Expanded(child: _decision(draft, 'Needs revision', 'needs_revision', amber)),
          ],
        ),
        if (several) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _busy || index == 0 ? null : () => setState(() => _index = index - 1),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Previous'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _busy || index == _drafts.length - 1
                    ? null
                    : () => setState(() => _index = index + 1),
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Next'),
                iconAlignment: IconAlignment.end,
              ),
            ],
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: amber),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Saving the tasks.',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: dispute, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _reviewing = false;
                      _error = null;
                    }),
              child: const Text('Back'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: !_ready ? null : _accept,
              child: _busy ? const _SavingMark() : const Text('Confirm'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _decision(_ProposalDraft draft, String label, String value, Color color) {
    final selected = draft.decision == value;
    return OutlinedButton(
      onPressed: _busy ? null : () => setState(() => draft.decision = value),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? color : muted,
        backgroundColor: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        side: BorderSide(color: selected ? color : line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _proposal(_ProposalDraft draft) {
    final cycles = _cycles(draft.projectId);
    final projectKnown = widget.projects.any((item) => item.id == draft.projectId);
    final cycleKnown = cycles.any((cycle) => cycle.id == draft.iterationId);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: raised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: draft.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Task title',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.description,
            minLines: 2,
            maxLines: 3,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Short description',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('project-${draft.projectId}'),
            initialValue: projectKnown ? draft.projectId : null,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Project'),
            items: [
              for (final project in widget.projects)
                DropdownMenuItem(value: project.id, child: Text(project.title)),
            ],
            onChanged: (id) {
              if (id == null) return;
              setState(() {
                draft.projectId = id;
                final open = _cycles(id);
                draft.iterationId = open.length == 1 ? open.first.id : '';
              });
            },
          ),
          if (draft.note.isNotEmpty && !cycleKnown) ...[
            const SizedBox(height: 8),
            Text(
              draft.note,
              style: const TextStyle(color: dispute, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          if (draft.projectId.isEmpty)
            const SizedBox.shrink()
          else if (cycles.isEmpty)
            const Text(
              'This project has no cycle yet.',
              style: TextStyle(color: dispute, fontSize: 13),
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey('cycle-${draft.projectId}-${draft.iterationId}'),
              initialValue: cycleKnown ? draft.iterationId : null,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, labelText: 'Cycle'),
              items: [
                for (final cycle in cycles)
                  DropdownMenuItem(value: cycle.id, child: Text(cycle.title)),
              ],
              onChanged: (id) {
                if (id == null) return;
                setState(() => draft.iterationId = id);
              },
            ),
        ],
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
