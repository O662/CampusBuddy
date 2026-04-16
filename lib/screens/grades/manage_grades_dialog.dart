import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/institution.dart';
import '../../models/semester.dart';
import '../../providers/grades_provider.dart';

/// Bottom sheet for managing institutions and semesters.
Future<void> showManageGradesDialog(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ManageGradesSheet(),
  );
}

class _ManageGradesSheet extends StatefulWidget {
  const _ManageGradesSheet();

  @override
  State<_ManageGradesSheet> createState() => _ManageGradesSheetState();
}

class _ManageGradesSheetState extends State<_ManageGradesSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text('Manage',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Institutions'),
              Tab(text: 'Semesters'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _InstitutionsTab(scrollController: scrollController),
                _SemestersTab(scrollController: scrollController),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Institutions Tab ──────────────────────────────────────────────────────────

class _InstitutionsTab extends StatelessWidget {
  final ScrollController scrollController;
  const _InstitutionsTab({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GradesProvider>();
    final institutions = provider.institutions;

    return Column(
      children: [
        Expanded(
          child: institutions.isEmpty
              ? _EmptyHint(
                  icon: Icons.account_balance_outlined,
                  message: 'No institutions yet',
                  hint: 'Add a school, community college, or dual-enrollment program',
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: institutions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final inst = institutions[i];
                    final courseCount = provider.courses
                        .where((c) => c.institutionId == inst.id)
                        .length;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor: Theme.of(ctx).colorScheme.surfaceContainerLow,
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(inst.name),
                      subtitle: Text(
                          '${inst.gpaScale.toStringAsFixed(1)} GPA scale  •  $courseCount course${courseCount == 1 ? '' : 's'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () =>
                                _showInstitutionDialog(ctx, inst),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: Theme.of(ctx).colorScheme.error),
                            tooltip: 'Delete',
                            onPressed: () =>
                                _confirmDeleteInstitution(ctx, inst, provider),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Institution'),
            onPressed: () => _showInstitutionDialog(context, null),
          ),
        ),
      ],
    );
  }

  void _showInstitutionDialog(BuildContext context, Institution? existing) {
    showDialog(
      context: context,
      builder: (_) => _InstitutionDialog(existing: existing),
    );
  }

  void _confirmDeleteInstitution(
      BuildContext context, Institution inst, GradesProvider provider) {
    final courseCount =
        provider.courses.where((c) => c.institutionId == inst.id).length;
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Institution'),
        content: Text(courseCount > 0
            ? 'Delete "${inst.name}"? The $courseCount associated course${courseCount == 1 ? '' : 's'} will be moved to Uncategorized.'
            : 'Delete "${inst.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        context.read<GradesProvider>().removeInstitution(inst.id);
      }
    });
  }
}

class _InstitutionDialog extends StatefulWidget {
  final Institution? existing;
  const _InstitutionDialog({this.existing});

  @override
  State<_InstitutionDialog> createState() => _InstitutionDialogState();
}

class _InstitutionDialogState extends State<_InstitutionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  double _gpaScale = 4.0;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.name ?? '');
    _gpaScale = widget.existing?.gpaScale ?? 4.0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<GradesProvider>();
    final inst = Institution(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      gpaScale: _gpaScale,
    );
    if (widget.existing != null) {
      provider.updateInstitution(inst);
    } else {
      provider.addInstitution(inst);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Institution' : 'Add Institution'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Institution Name',
                  hintText: 'e.g. State University',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 20),
              Text('GPA Scale',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 4.0, label: Text('4.0')),
                  ButtonSegment(value: 5.0, label: Text('5.0')),
                ],
                selected: {_gpaScale},
                onSelectionChanged: (s) =>
                    setState(() => _gpaScale = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                _gpaScale == 5.0
                    ? 'Use 5.0 for weighted GPA (e.g. honors/dual enrollment)'
                    : 'Standard college GPA scale',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _submit, child: Text(isEdit ? 'Save' : 'Add')),
      ],
    );
  }
}

// ── Semesters Tab ─────────────────────────────────────────────────────────────

class _SemestersTab extends StatelessWidget {
  final ScrollController scrollController;
  const _SemestersTab({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GradesProvider>();
    final institutions = provider.institutions;
    final semesters = provider.semesters;

    if (institutions.isEmpty) {
      return const _EmptyHint(
        icon: Icons.school_outlined,
        message: 'Add an institution first',
        hint: 'Semesters belong to an institution',
      );
    }

    return Column(
      children: [
        Expanded(
          child: semesters.isEmpty
              ? const _EmptyHint(
                  icon: Icons.calendar_today_outlined,
                  message: 'No semesters yet',
                  hint: 'Add Fall, Spring, or Summer semesters',
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: semesters.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final sem = semesters[i];
                    final instName = institutions
                        .where((i) => i.id == sem.institutionId)
                        .map((i) => i.name)
                        .firstOrNull ?? 'Unknown Institution';
                    final courseCount = provider
                        .coursesForSemester(sem.id)
                        .length;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor:
                          Theme.of(ctx).colorScheme.surfaceContainerLow,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(sem.name),
                      subtitle: Text(
                          '$instName  •  $courseCount course${courseCount == 1 ? '' : 's'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () =>
                                _showSemesterDialog(ctx, sem),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: Theme.of(ctx).colorScheme.error),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDeleteSemester(
                                ctx, sem, provider),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Semester'),
            onPressed: () => _showSemesterDialog(context, null),
          ),
        ),
      ],
    );
  }

  void _showSemesterDialog(BuildContext context, Semester? existing) {
    showDialog(
      context: context,
      builder: (_) => _SemesterDialog(existing: existing),
    );
  }

  void _confirmDeleteSemester(
      BuildContext context, Semester sem, GradesProvider provider) {
    final courseCount = provider.coursesForSemester(sem.id).length;
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Semester'),
        content: Text(courseCount > 0
            ? 'Delete "${sem.name}"? The $courseCount course${courseCount == 1 ? '' : 's'} will be moved to Unsorted within their institution.'
            : 'Delete "${sem.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        context.read<GradesProvider>().removeSemester(sem.id);
      }
    });
  }
}

class _SemesterDialog extends StatefulWidget {
  final Semester? existing;
  const _SemesterDialog({this.existing});

  @override
  State<_SemesterDialog> createState() => _SemesterDialogState();
}

class _SemesterDialogState extends State<_SemesterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _sortCtrl;
  String? _selectedInstitutionId;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _sortCtrl = TextEditingController(
        text: widget.existing?.sortOrder.toString() ?? '0');
    _selectedInstitutionId = widget.existing?.institutionId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-select when there is only one institution and none is pre-selected.
    if (_selectedInstitutionId == null) {
      final institutions = context.read<GradesProvider>().institutions;
      if (institutions.length == 1) {
        _selectedInstitutionId = institutions.first.id;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstitutionId == null) return;
    final provider = context.read<GradesProvider>();
    final sem = Semester(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      institutionId: _selectedInstitutionId!,
      sortOrder: int.tryParse(_sortCtrl.text) ?? 0,
    );
    if (widget.existing != null) {
      provider.updateSemester(sem);
    } else {
      provider.addSemester(sem);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final institutions = context.watch<GradesProvider>().institutions;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Semester' : 'Add Semester'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Semester Name',
                  hintText: 'e.g. Fall 2024',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedInstitutionId,
                decoration: const InputDecoration(
                  labelText: 'Institution',
                  border: OutlineInputBorder(),
                ),
                items: institutions
                    .map((i) => DropdownMenuItem(
                          value: i.id,
                          child: Text(i.name),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedInstitutionId = v),
                validator: (v) =>
                    v == null ? 'Select an institution' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sortCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sort Order',
                  hintText: '0 = first',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _submit, child: Text(isEdit ? 'Save' : 'Add')),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;

  const _EmptyHint({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(message,
                style: theme.textTheme.titleMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 8),
            Text(hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.4))),
          ],
        ),
      ),
    );
  }
}
