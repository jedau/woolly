import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'api.dart';
import 'mark.dart';
import 'models.dart';
import 'project_dialog.dart';
import 'summary_dialog.dart';
import 'task_dialog.dart';
import 'theme.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.api, required this.person});

  final WoollyApi api;
  final Person person;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

const unassignedWorker = 'unassigned';

enum _Screen { board, settings, manage }

class _WorkspacePageState extends State<WorkspacePage> {
  Workspace? _workspace;
  Set<String> _projectIds = {};
  Set<String> _iterationIds = {};
  Set<String> _workerIds = {};
  Set<String> _statusIds = {};
  String? _openFilter;
  String? _error;
  String? _busy;
  bool _loading = true;
  _Screen _screen = _Screen.board;

  bool get _isClient => widget.person.isClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workspace = await widget.api.workspace(widget.person.id);
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _loading = false;
        _pruneFilters(workspace);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _pruneFilters(Workspace workspace) {
    final projects = _visible(workspace);
    final projectIds = projects.map((project) => project.id).toSet();
    _projectIds.removeWhere((id) => !projectIds.contains(id));
    final allowedIterations = {
      for (final project in projects)
        if (_projectIds.isEmpty || _projectIds.contains(project.id))
          for (final iteration in project.iterations) iteration.id,
    };
    _iterationIds.removeWhere((id) => !allowedIterations.contains(id));
    final workerIds = {
      unassignedWorker,
      ...workspace.workers.map((worker) => worker.id),
    };
    _workerIds.removeWhere((id) => !workerIds.contains(id));
  }

  List<Project> _visible(Workspace workspace) => workspace.projects;

  void _onProjects(Set<String> ids) {
    setState(() {
      _projectIds = ids;
      if (_workspace != null) _pruneFilters(_workspace!);
    });
  }

  Future<void> _openTask(TaskItem task, Project project, Iteration cycle) {
    final workspace = _workspace;
    if (workspace == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (context) => TaskDialog(
        isClient: _isClient,
        task: task,
        project: project,
        cycle: cycle,
        projects: workspace.projects,
        workers: workspace.workers,
        onSave: (draft) => _apply(
          'Saving the task',
          () => widget.api.updateTask(
            task.id,
            personId: widget.person.id,
            title: draft.title,
            description: draft.description,
            status: draft.status,
            iterationId: draft.iterationId,
            assigneeIds: draft.assigneeIds,
            shares: [
              for (final share in draft.shares)
                {'taskId': share.taskId, 'percent': share.percent},
            ],
            decision: draft.decision,
            proofSummary: draft.proofSummary,
            proofUrl: draft.proofUrl,
            files: [
              for (final file in draft.files)
                {
                  'filename': file.filename,
                  'contentType': file.contentType,
                  'fileBase64': file.fileBase64,
                },
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSummary(List<Project> projects) {
    return showDialog<void>(
      context: context,
      builder: (context) => SummaryDialog(
        projects: projects,
        onPropose: (summary) =>
            widget.api.proposeTasks(widget.person.id, summary),
        onAccept: (tasks) async {
          final workspace = await widget.api.acceptTasks(
            widget.person.id,
            tasks,
          );
          if (!mounted) return;
          setState(() {
            _workspace = workspace;
            _pruneFilters(workspace);
          });
        },
      ),
    );
  }

  Future<String?> _apply(
    String label,
    Future<Workspace> Function() action,
  ) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      await action();
      final workspace = await widget.api.workspace(widget.person.id);
      if (!mounted) return null;
      setState(() {
        _workspace = workspace;
        _busy = null;
        _pruneFilters(workspace);
      });
      return null;
    } catch (error) {
      if (!mounted) return '$error';
      setState(() {
        _error = '$error';
        _busy = null;
      });
      return '$error';
    }
  }

  Future<void> _openProject() {
    return showDialog<void>(
      context: context,
      builder: (context) => ProjectDialog(
        onSave: (draft) => _apply(
          'Adding project',
          () => widget.api.createProject(
            personId: widget.person.id,
            title: draft.title,
            description: draft.description,
            startsOn: draft.startsOn,
            endsOn: draft.endsOn,
            budget: draft.budget,
            cycles: draft.cycles,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = _workspace == null
        ? const <Project>[]
        : _visible(_workspace!);
    final workers = _workspace?.workers ?? const <Person>[];
    return Scaffold(
      floatingActionButton:
          !_loading &&
              _isClient &&
              (_screen == _Screen.board || _screen == _Screen.manage)
          ? FloatingActionButton(
              onPressed: _screen == _Screen.board
                  ? () => _openSummary(projects)
                  : _openProject,
              backgroundColor: amber,
              foregroundColor: bg,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: amber))
          : Column(
              children: [
                _TopBar(
                  person: widget.person,
                  screen: _screen,
                  onBoard: () => setState(() => _screen = _Screen.board),
                  onSettings: () => setState(() {
                    _screen = _Screen.settings;
                    _openFilter = null;
                  }),
                  onManage: () => setState(() {
                    _screen = _Screen.manage;
                    _openFilter = null;
                  }),
                  onSignOut: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: switch (_screen) {
                    _Screen.board => _Board(
                      isClient: _isClient,
                      projects: projects,
                      workers: workers,
                      projectIds: _projectIds,
                      iterationIds: _iterationIds,
                      workerIds: _workerIds,
                      statusIds: _statusIds,
                      openFilter: _openFilter,
                      error: _error,
                      busy: _busy,
                      onProjects: _onProjects,
                      onIterations: (ids) =>
                          setState(() => _iterationIds = ids),
                      onWorkers: (ids) => setState(() => _workerIds = ids),
                      onStatuses: (ids) => setState(() => _statusIds = ids),
                      onOpenFilter: (source, open) => setState(() {
                        if (open) {
                          _openFilter = source;
                        } else if (_openFilter == source) {
                          _openFilter = null;
                        }
                      }),
                      onOpenTask: _openTask,
                    ),
                    _Screen.settings => _SettingsView(
                      person: widget.person,
                      onSignOut: () => Navigator.of(context).pop(),
                    ),
                    _Screen.manage => _ManageView(
                      api: widget.api,
                      person: widget.person,
                      projects: projects,
                      busy: _busy != null,
                      error: _error,
                      onApply: _apply,
                    ),
                  },
                ),
              ],
            ),
    );
  }
}

class _FilterMenu extends StatefulWidget {
  const _FilterMenu({
    required this.label,
    required this.options,
    required this.selected,
    required this.open,
    required this.onOpened,
    required this.onClosed,
    required this.onChanged,
  });

  final String label;
  final List<({String id, String label})> options;
  final Set<String> selected;
  final bool open;
  final VoidCallback onOpened;
  final VoidCallback onClosed;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_FilterMenu> createState() => _FilterMenuState();
}

class _FilterMenuState extends State<_FilterMenu> {
  final _link = LayerLink();
  final _query = TextEditingController();
  OverlayEntry? _entry;

  @override
  void didUpdateWidget(covariant _FilterMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    final opened = !oldWidget.open && widget.open;
    final closed = oldWidget.open && !widget.open;
    final changed =
        widget.open &&
        (oldWidget.selected != widget.selected ||
            oldWidget.options != widget.options);
    if (!opened && !closed && !changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.open) {
        _show();
      } else {
        _hide();
      }
    });
  }

  void _show() {
    final existing = _entry;
    if (existing != null) {
      existing.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(builder: _panel);
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  void _hide() {
    final entry = _entry;
    _entry = null;
    entry?.remove();
    if (_query.text.isNotEmpty) _query.clear();
  }

  Widget _panel(BuildContext overlayContext) {
    final width = (MediaQuery.sizeOf(overlayContext).width - 40).clamp(
      220.0,
      320.0,
    );
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 6),
        child: SizedBox(
          width: width,
          child: TapRegion(
            groupId: _link,
            onTapOutside: (_) {
              if (widget.open) widget.onClosed();
            },
            child: _FilterPanel(
              query: _query,
              options: widget.options,
              selected: widget.selected,
              onToggle: _toggle,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    final entry = _entry;
    _entry = null;
    entry?.remove();
    _query.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    final next = Set<String>.of(widget.selected);
    if (!next.add(id)) next.remove(id);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.open || widget.selected.isNotEmpty;
    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _link,
        child: OutlinedButton(
          onPressed: () {
            if (widget.open) {
              widget.onClosed();
            } else {
              widget.onOpened();
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: active ? amber : ink,
            backgroundColor: active
                ? amber.withValues(alpha: 0.12)
                : Colors.transparent,
            side: BorderSide(color: active ? amber : line),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label),
              if (widget.selected.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '${widget.selected.length}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              Icon(
                widget.open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.query,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final TextEditingController query;
  final List<({String id, String label})> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  @override
  void initState() {
    super.initState();
    widget.query.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant _FilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      oldWidget.query.removeListener(_rebuild);
      widget.query.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.query.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query.text.trim().toLowerCase();
    final matches = widget.options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
    final width = (MediaQuery.sizeOf(context).width - 40).clamp(220.0, 320.0);
    return Material(
      color: panel,
      elevation: 8,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 340),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: line),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.query,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search',
                prefixIcon: Icon(Icons.search, size: 16, color: muted),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: matches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No matches',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final option in matches)
                          InkWell(
                            onTap: () => widget.onToggle(option.id),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                children: [
                                  IgnorePointer(
                                    child: Checkbox(
                                      value: widget.selected.contains(
                                        option.id,
                                      ),
                                      onChanged: (_) {},
                                      activeColor: amber,
                                      checkColor: bg,
                                      side: const BorderSide(color: muted),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.isClient,
    required this.projects,
    required this.workers,
    required this.projectIds,
    required this.iterationIds,
    required this.workerIds,
    required this.statusIds,
    required this.openFilter,
    required this.error,
    required this.busy,
    required this.onProjects,
    required this.onIterations,
    required this.onWorkers,
    required this.onStatuses,
    required this.onOpenFilter,
    required this.onOpenTask,
  });

  final bool isClient;
  final List<Project> projects;
  final List<Person> workers;
  final Set<String> projectIds;
  final Set<String> iterationIds;
  final Set<String> workerIds;
  final Set<String> statusIds;
  final String? openFilter;
  final String? error;
  final String? busy;
  final ValueChanged<Set<String>> onProjects;
  final ValueChanged<Set<String>> onIterations;
  final ValueChanged<Set<String>> onWorkers;
  final ValueChanged<Set<String>> onStatuses;
  final void Function(String source, bool open) onOpenFilter;
  final void Function(TaskItem task, Project project, Iteration cycle)
  onOpenTask;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return const ColoredBox(
        color: bg,
        child: Center(
          child: Text('No projects yet.', style: TextStyle(color: muted)),
        ),
      );
    }
    final visibleProjects = projectIds.isEmpty
        ? projects
        : projects.where((project) => projectIds.contains(project.id)).toList();
    final cycleOptions = [
      for (final project in visibleProjects)
        for (final iteration in project.iterations)
          (
            id: iteration.id,
            label: visibleProjects.length > 1
                ? '${project.title} · ${iteration.title}'
                : iteration.title,
          ),
    ];
    final sections = <({Project project, List<Iteration> cycles})>[
      for (final project in visibleProjects)
        (
          project: project,
          cycles: project.iterations
              .where(
                (item) =>
                    iterationIds.isEmpty || iterationIds.contains(item.id),
              )
              .toList(),
        ),
    ].where((section) => section.cycles.isNotEmpty).toList();
    final cards = [
      for (final section in sections)
        for (final cycle in section.cycles)
          for (final task in cycle.tasks)
            if ((!isClient || _matchesWorkers(task, workerIds)) &&
                _matchesStatus(task, statusIds, cycle.deadline))
              (task: task, project: section.project, cycle: cycle),
    ];
    return ColoredBox(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterMenu(
                  label: 'Project',
                  open: openFilter == 'project',
                  selected: projectIds,
                  options: [
                    for (final project in projects)
                      (id: project.id, label: project.title),
                  ],
                  onOpened: () => onOpenFilter('project', true),
                  onClosed: () => onOpenFilter('project', false),
                  onChanged: onProjects,
                ),
                if (isClient)
                  _FilterMenu(
                    label: 'Workers',
                    open: openFilter == 'workers',
                    selected: workerIds,
                    options: [
                      (id: unassignedWorker, label: 'Unassigned'),
                      for (final worker in workers)
                        (id: worker.id, label: worker.name),
                    ],
                    onOpened: () => onOpenFilter('workers', true),
                    onClosed: () => onOpenFilter('workers', false),
                    onChanged: onWorkers,
                  ),
                _FilterMenu(
                  label: 'Cycle',
                  open: openFilter == 'cycle',
                  selected: iterationIds,
                  options: cycleOptions,
                  onOpened: () => onOpenFilter('cycle', true),
                  onClosed: () => onOpenFilter('cycle', false),
                  onChanged: onIterations,
                ),
                _FilterMenu(
                  label: 'Status',
                  open: openFilter == 'status',
                  selected: statusIds,
                  options: [
                    for (final status in _taskStatuses)
                      (id: status, label: status),
                  ],
                  onOpened: () => onOpenFilter('status', true),
                  onClosed: () => onOpenFilter('status', false),
                  onChanged: onStatuses,
                ),
              ],
            ),
          ),
          if (error != null || busy != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    Text(error!, style: const TextStyle(color: dispute)),
                  if (busy != null)
                    Text('$busy…', style: const TextStyle(color: muted)),
                ],
              ),
            ),
          Expanded(
            child: cards.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(28, 12, 28, 48),
                    child: Text(
                      'No tasks match this filter.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : _CardPages(
                    items: cards,
                    resetToken: (
                      projectIds,
                      iterationIds,
                      workerIds,
                      statusIds,
                      cards.length,
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 72),
                    itemBuilder: (card) => _TaskCard(
                      title: card.task.title,
                      description: card.task.description,
                      status: _taskStatus(card.task, card.cycle.deadline),
                      assignees: [
                        for (final person in card.task.assignees) person.name,
                      ],
                      project: card.project.title,
                      cycle: card.cycle.title,
                      onTap: () =>
                          onOpenTask(card.task, card.project, card.cycle),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

const _pagerExtent = 40.0;

enum _PageFit { pending, fits, overflows }

class _CardPages<T> extends StatefulWidget {
  const _CardPages({
    required this.items,
    required this.resetToken,
    required this.itemBuilder,
    required this.padding,
  });

  final List<T> items;
  final Object resetToken;
  final Widget Function(T item) itemBuilder;
  final EdgeInsets padding;

  @override
  State<_CardPages<T>> createState() => _CardPagesState<T>();
}

class _CardPagesState<T> extends State<_CardPages<T>> {
  int _first = 0;
  int? _widthKey;
  List<double?> _heights = [];
  bool _posted = false;

  @override
  void didUpdateWidget(covariant _CardPages<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _first = 0;
      _heights = List<double?>.filled(widget.items.length, null);
    }
  }

  int get _total => widget.items.length;

  void _remember(int index, double height, int widthKey) {
    if (!mounted || widthKey != _widthKey || index >= _heights.length) return;
    final previous = _heights[index];
    if (previous != null && (previous - height).abs() < 0.5) return;
    _heights[index] = height;
    if (_posted) return;
    _posted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _posted = false;
      if (mounted) setState(() {});
    });
  }

  /// How many cards from [start] fit in [budget]. Null while a height is
  /// still unknown. A card taller than the window still counts as one.
  int? _count(int start, double budget) {
    var used = 0.0;
    var count = 0;
    for (var index = start; index < _total; index++) {
      final height = _heights[index];
      if (height == null) return null;
      if (count > 0 && used + height > budget) return count;
      used += height;
      count++;
      if (used > budget) return count;
    }
    return count;
  }

  _PageFit _fitAll(double budget) {
    var used = 0.0;
    for (var index = 0; index < _total; index++) {
      final height = _heights[index];
      if (height == null) return _PageFit.pending;
      if (index > 0 && used + height > budget) return _PageFit.overflows;
      used += height;
      if (used > budget) {
        return _total == 1 ? _PageFit.fits : _PageFit.overflows;
      }
    }
    return _PageFit.fits;
  }

  /// Every page start. Null until each card's height is known.
  List<int>? _pageStarts(double budget) {
    if (_heights.any((height) => height == null)) return null;
    final starts = <int>[0];
    var index = 0;
    while (index < _total) {
      final count = _count(index, budget);
      if (count == null || count < 1) break;
      final next = index + count;
      if (next <= index || next >= _total) break;
      starts.add(next);
      index = next;
    }
    return starts;
  }

  List<int> _toMeasure() {
    final found = <int>[];
    for (var index = 0; index < _total && found.length < 12; index++) {
      if (_heights[index] == null) found.add(index);
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    if (_total == 0) return const SizedBox.shrink();
    if (_first >= _total) _first = 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite) {
          return Column(
            children: [
              for (final item in widget.items) widget.itemBuilder(item),
            ],
          );
        }
        final cardWidth = constraints.maxWidth - widget.padding.horizontal;
        final widthKey = (cardWidth * 10).round();
        if (_widthKey != widthKey) {
          _widthKey = widthKey;
          _heights = List<double?>.filled(_total, null);
        } else if (_heights.length != _total) {
          final next = List<double?>.filled(_total, null);
          for (
            var index = 0;
            index < _heights.length && index < _total;
            index++
          ) {
            next[index] = _heights[index];
          }
          _heights = next;
        }
        final cardBudget = (constraints.maxHeight - widget.padding.vertical)
            .clamp(1.0, double.infinity);
        final fit = _fitAll(cardBudget);
        final showPager = fit == _PageFit.overflows;
        final budget = showPager
            ? (cardBudget - _pagerExtent).clamp(1.0, double.infinity)
            : cardBudget;
        final measuring = _toMeasure();
        final starts = fit == _PageFit.pending ? null : _pageStarts(budget);
        final page = _pageOf(starts);
        var start = 0;
        var end = 0;
        if (fit == _PageFit.pending) {
          var used = 0.0;
          for (var index = 0; index < _total; index++) {
            final height = _heights[index];
            if (height == null) break;
            if (end > 0 && used + height > cardBudget) break;
            used += height;
            end++;
            if (used > cardBudget) break;
          }
        } else if (starts != null) {
          start = starts[page];
          end = page + 1 < starts.length ? starts[page + 1] : _total;
        }
        final visible = <Widget>[
          for (var index = start; index < end; index++)
            widget.itemBuilder(widget.items[index]),
        ];
        var used = 0.0;
        for (var index = start; index < end; index++) {
          used += _heights[index] ?? 0;
        }
        final scroll = visible.isNotEmpty && used > budget;
        return ClipRect(
          child: SizedBox(
            height: constraints.maxHeight,
            width: constraints.maxWidth,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showPager && starts != null)
                      Padding(
                        padding: EdgeInsets.only(
                          left: widget.padding.left,
                          right: widget.padding.right,
                        ),
                        child: _pager(starts, page),
                      ),
                    if (scroll)
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey(start),
                          child: Padding(
                            padding: widget.padding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: visible,
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: widget.padding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: visible,
                        ),
                      ),
                  ],
                ),
                if (measuring.isNotEmpty && cardWidth > 0)
                  Positioned(
                    left: widget.padding.left,
                    top: 0,
                    width: cardWidth,
                    height: 0,
                    child: Offstage(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: cardWidth,
                        maxWidth: cardWidth,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final index in measuring)
                              _ReportSize(
                                onSize: (size) =>
                                    _remember(index, size.height, widthKey),
                                child: widget.itemBuilder(widget.items[index]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _pageOf(List<int>? starts) {
    if (starts == null || starts.isEmpty) return 0;
    var page = 0;
    for (var index = 0; index < starts.length; index++) {
      if (starts[index] <= _first) page = index;
    }
    return page;
  }

  void _go(int first) => setState(() => _first = first);

  Widget _pager(List<int> starts, int page) {
    final last = starts.length - 1;
    return SizedBox(
      height: _pagerExtent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous',
            onPressed: page == 0 ? null : () => _go(starts[page - 1]),
            icon: const Icon(Icons.chevron_left),
            style: IconButton.styleFrom(
              foregroundColor: ink,
              disabledForegroundColor: line,
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(36, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          for (final entry in _pageWindow(starts.length, page))
            if (entry == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('…', style: TextStyle(color: muted)),
              )
            else
              _pageButton(
                entry,
                selected: entry == page,
                onTap: () => _go(starts[entry]),
              ),
          IconButton(
            tooltip: 'Next',
            onPressed: page == last ? null : () => _go(starts[page + 1]),
            icon: const Icon(Icons.chevron_right),
            style: IconButton.styleFrom(
              foregroundColor: ink,
              disabledForegroundColor: line,
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(36, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  List<int?> _pageWindow(int count, int current) {
    if (count <= 5) return [for (var index = 0; index < count; index++) index];
    final window = <int?>[0];
    final near = {
      for (var index = current - 1; index <= current + 1; index++)
        if (index > 0 && index < count - 1) index,
    };
    if (near.isEmpty) {
      window.add(count - 1);
      return window;
    }
    if (near.first > 1) window.add(null);
    window.addAll(near);
    if (near.last < count - 2) window.add(null);
    window.add(count - 1);
    return window;
  }

  Widget _pageButton(
    int index, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final number = '${index + 1}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Page $number',
        child: Material(
          color: selected ? amber : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: selected ? null : onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    color: selected ? bg : ink,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportSize extends SingleChildRenderObjectWidget {
  const _ReportSize({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderReportSize(onSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportSize renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderReportSize extends RenderProxyBox {
  _RenderReportSize(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    final measured = child?.size;
    if (measured == null || measured.height < 1) return;
    final size = measured;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(size));
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.title,
    required this.description,
    required this.status,
    required this.assignees,
    required this.project,
    required this.cycle,
    required this.onTap,
  });

  final String title;
  final String description;
  final String status;
  final List<String> assignees;
  final String project;
  final String cycle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: panel,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MetaBadge(
                      status,
                      fill: statusColor.withValues(alpha: 0.14),
                      foreground: statusColor,
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (assignees.isEmpty)
                      const _MetaBadge(
                        'Unassigned',
                        fill: raised,
                        foreground: muted,
                      )
                    else
                      for (final name in assignees)
                        _MetaBadge(name, fill: raised, foreground: ink),
                    _MetaBadge(
                      project,
                      fill: amber.withValues(alpha: 0.12),
                      foreground: amber,
                    ),
                    _MetaBadge(cycle, foreground: muted, border: line),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(
    this.label, {
    required this.foreground,
    this.fill = Colors.transparent,
    this.border,
  });

  final String label;
  final Color foreground;
  final Color fill;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

const _taskStatuses = [
  'Open',
  'Revision Needed',
  'Overdue',
  'Under Review',
  'Disputed',
  'Complete',
];

String _taskStatus(TaskItem task, String? deadline) {
  switch (task.status) {
    case 'complete':
      return 'Complete';
    case 'under_review':
      return 'Under Review';
    case 'revision_needed':
      return 'Revision Needed';
  }
  final statuses = task.subtasks.map((item) => item.status).toList();
  if (statuses.isNotEmpty && statuses.every((status) => status == 'Credited')) {
    return 'Complete';
  }
  if (statuses.contains('Disputed')) return 'Disputed';
  if (statuses.contains('In review')) return 'Under Review';
  if (task.review == 'needs_revision') return 'Revision Needed';
  if (_isOverdue(deadline)) return 'Overdue';
  return 'Open';
}

bool _isOverdue(String? deadline) {
  if (deadline == null || deadline.isEmpty) return false;
  final parsed = DateTime.tryParse(deadline);
  if (parsed == null) return false;
  final due = DateTime(parsed.year, parsed.month, parsed.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.isAfter(due);
}

Color _statusColor(String status) {
  return switch (status) {
    'Complete' => credit,
    'Disputed' => dispute,
    'Overdue' => dispute,
    'Revision Needed' => amber,
    'Under Review' => amber,
    _ => muted,
  };
}

bool _matchesStatus(TaskItem task, Set<String> statusIds, String? deadline) {
  if (statusIds.isEmpty) return true;
  return statusIds.contains(_taskStatus(task, deadline));
}

bool _matchesWorkers(TaskItem task, Set<String> workerIds) {
  if (workerIds.isEmpty) return true;
  final people = workerIds.where((id) => id != unassignedWorker).toSet();
  if (task.assignees.isEmpty) return workerIds.contains(unassignedWorker);
  return task.assignees.any((person) => people.contains(person.id));
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.person,
    required this.screen,
    required this.onBoard,
    required this.onSettings,
    required this.onManage,
    required this.onSignOut,
  });

  final Person person;
  final _Screen screen;
  final VoidCallback onBoard;
  final VoidCallback onSettings;
  final VoidCallback onManage;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: sidebar,
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          GestureDetector(onTap: onBoard, child: const WoollyBrand()),
          const Spacer(),
          _AccountMenu(
            person: person,
            screen: screen,
            onSettings: onSettings,
            onManage: onManage,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.person,
    required this.screen,
    required this.onSettings,
    required this.onManage,
    required this.onSignOut,
  });

  final Person person;
  final _Screen screen;
  final VoidCallback onSettings;
  final VoidCallback onManage;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      color: panel,
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: line),
      ),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            onSettings();
          case 'manage':
            onManage();
          case 'signout':
            onSignOut();
        }
      },
      itemBuilder: (context) => [
        if (person.isClient) ...[
          _accountItem('settings', 'Settings', screen == _Screen.settings),
          _accountItem('manage', 'Manage', screen == _Screen.manage),
          const PopupMenuDivider(height: 1),
        ],
        _accountItem('signout', 'Sign out', false, quiet: true),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              person.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.expand_more, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _accountItem(
    String value,
    String label,
    bool selected, {
    bool quiet = false,
  }) {
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Text(
        label,
        style: TextStyle(color: selected ? amber : (quiet ? muted : ink)),
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.person, required this.onSignOut});

  final Person person;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
      children: [
        Text(
          person.name,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          person.isClient ? 'Client' : 'Worker',
          style: const TextStyle(color: amber),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onSignOut,
            child: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

class _ManageView extends StatefulWidget {
  const _ManageView({
    required this.api,
    required this.person,
    required this.projects,
    required this.busy,
    required this.error,
    required this.onApply,
  });

  final WoollyApi api;
  final Person person;
  final List<Project> projects;
  final bool busy;
  final String? error;
  final Future<String?> Function(
    String label,
    Future<Workspace> Function() action,
  )
  onApply;

  @override
  State<_ManageView> createState() => _ManageViewState();
}

class _ManageViewState extends State<_ManageView> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Project> get _shown {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return widget.projects;
    return [
      for (final project in widget.projects)
        if (_matches(project, query)) project,
    ];
  }

  bool _matches(Project project, String query) {
    final haystack = [
      project.title,
      project.description,
      if (project.budgetCents != null) money(project.budgetCents!),
      ...project.iterations.map((cycle) => cycle.title),
    ].join('\n').toLowerCase();
    return haystack.contains(query);
  }

  Future<void> _edit(Project project) {
    return showDialog<void>(
      context: context,
      builder: (context) => ProjectDialog(
        project: project,
        onSave: (draft) => widget.onApply(
          'Saving project',
          () => widget.api.updateProject(
            project.id,
            personId: widget.person.id,
            title: draft.title,
            description: draft.description,
            startsOn: draft.startsOn,
            endsOn: draft.endsOn,
            budget: draft.budget,
            cycles: draft.cycles,
            removedCycleIds: draft.removedCycleIds,
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Project project) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Delete project'),
        content: Text(
          'Delete ${project.title}? Its cycles and tasks go with it.',
        ),
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
    await widget.onApply(
      'Deleting project',
      () => widget.api.deleteProject(project.id, personId: widget.person.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Projects',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Search, edit, or delete a project.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search projects',
                  prefixIcon: const Icon(Icons.search, color: muted, size: 20),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close, size: 18, color: muted),
                        ),
                ),
              ),
              if (widget.error != null) ...[
                const SizedBox(height: 12),
                Text(widget.error!, style: const TextStyle(color: dispute)),
              ],
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 88),
                  child: Text(
                    widget.projects.isEmpty
                        ? 'No projects yet.'
                        : 'No projects match.',
                    style: const TextStyle(color: muted),
                  ),
                )
              : _CardPages(
                  items: shown,
                  resetToken: (
                    _query.text,
                    shown.length,
                    shown.fold<int>(
                      0,
                      (sum, project) => sum + project.iterations.length,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 72),
                  itemBuilder: (project) => _ProjectCard(
                    project: project,
                    busy: widget.busy,
                    onEdit: () => _edit(project),
                    onDelete: () => _delete(project),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final Project project;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dates = dateSpan(project.startsOn, project.endsOn);
    final allocated = project.iterations.fold<int>(
      0,
      (sum, cycle) => sum + cycle.payCents,
    );
    final overBudget =
        project.budgetCents != null && allocated > project.budgetCents!;
    final budget = project.budgetCents == null
        ? 'Budget not set'
        : 'Budget ${money(project.budgetCents!)}';
    final allocation = 'Allocated ${money(allocated)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    project.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18, color: muted),
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: dispute,
                ),
              ),
            ],
          ),
          if (project.description.isNotEmpty)
            Text(
              project.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.35),
            ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13),
              children: [
                TextSpan(text: budget),
                const TextSpan(text: ' · '),
                TextSpan(
                  text: allocation,
                  style: TextStyle(color: overBudget ? dispute : ink),
                ),
                if (dates != null) TextSpan(text: ' · $dates'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (project.iterations.isEmpty)
            const Text(
              'No cycles yet',
              style: TextStyle(color: muted, fontSize: 12),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cycle in project.iterations.take(2))
                  _MetaBadge(
                    '${cycle.title} · ${money(cycle.payCents)}',
                    foreground: muted,
                    border: line,
                  ),
                if (project.iterations.length > 2)
                  _MetaBadge(
                    '${project.iterations.length - 2} more…',
                    foreground: muted,
                    border: line,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
