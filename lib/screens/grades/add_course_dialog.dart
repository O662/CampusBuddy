import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/course.dart';
import '../../models/institution.dart';
import '../../models/semester.dart';
import '../../providers/grades_provider.dart';

class AddCourseDialog extends StatefulWidget {
  final Course? existing;
  const AddCourseDialog({super.key, this.existing});

  @override
  State<AddCourseDialog> createState() => _AddCourseDialogState();
}

class _AddCourseDialogState extends State<AddCourseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _creditsCtrl;
  late final TextEditingController _gradeCtrl;

  String? _selectedInstitutionId;
  String? _selectedSemesterId;
  bool _includeInGpa = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _creditsCtrl =
        TextEditingController(text: e?.credits.toString() ?? '3');
    _gradeCtrl =
        TextEditingController(text: e?.gradePercent.toString() ?? '');
    _selectedInstitutionId = e?.institutionId;
    _selectedSemesterId = e?.semesterId;
    _includeInGpa = e?.includeInGpa ?? true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-select institution if there is only one and none is pre-selected.
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
    _creditsCtrl.dispose();
    _gradeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final course = Course(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      credits: double.parse(_creditsCtrl.text),
      gradePercent: double.parse(_gradeCtrl.text),
      institutionId: _selectedInstitutionId,
      semesterId: _selectedSemesterId,
      includeInGpa: _includeInGpa,
    );
    Navigator.of(context).pop(course);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final provider = context.watch<GradesProvider>();
    final institutions = provider.institutions;

    // Semesters filtered to selected institution
    final semesters = _selectedInstitutionId != null
        ? provider.semestersForInstitution(_selectedInstitutionId!)
        : <Semester>[];

    // If selected semester no longer belongs to the new institution, clear it.
    if (_selectedSemesterId != null &&
        !semesters.any((s) => s.id == _selectedSemesterId)) {
      _selectedSemesterId = null;
    }

    return AlertDialog(
      title: Text(isEdit ? 'Edit Course' : 'Add Course'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Course name ──────────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Course Name',
                    hintText: 'e.g. Calculus II',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty
                          ? 'Enter a course name'
                          : null,
                ),
                const SizedBox(height: 16),

                // ── Credits & Grade in a row ──────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _creditsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Credit Hours',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'))
                        ],
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0) {
                            return 'Enter valid credit hours';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _gradeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Grade (%)',
                          hintText: 'e.g. 87.5',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'))
                        ],
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n < 0 || n > 100) {
                            return '0 – 100';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Institution ───────────────────────────────────────────
                if (institutions.isEmpty)
                  _NoInstitutionHint(
                    onAdd: () async {
                      Navigator.of(context).pop();
                    },
                  )
                else ...[
                  _InstitutionDropdown(
                    institutions: institutions,
                    selectedId: _selectedInstitutionId,
                    onChanged: (id) => setState(() {
                      _selectedInstitutionId = id;
                      _selectedSemesterId = null;
                    }),
                  ),
                  const SizedBox(height: 16),

                  // ── Semester ────────────────────────────────────────────
                  _SemesterDropdown(
                    semesters: semesters,
                    selectedId: _selectedSemesterId,
                    enabled: _selectedInstitutionId != null,
                    onChanged: (id) =>
                        setState(() => _selectedSemesterId = id),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Include in GPA toggle ─────────────────────────────────
                _GpaToggle(
                  value: _includeInGpa,
                  onChanged: (v) => setState(() => _includeInGpa = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _InstitutionDropdown extends StatelessWidget {
  final List<Institution> institutions;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _InstitutionDropdown({
    required this.institutions,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      decoration: const InputDecoration(
        labelText: 'Institution',
        prefixIcon: Icon(Icons.account_balance_outlined),
        border: OutlineInputBorder(),
      ),
      items: [
        ...institutions.map((i) => DropdownMenuItem(
              value: i.id,
              child: Text(i.name),
            )),
        const DropdownMenuItem(
          value: null,
          child: Text('None'),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _SemesterDropdown extends StatelessWidget {
  final List<Semester> semesters;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _SemesterDropdown({
    required this.semesters,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      decoration: InputDecoration(
        labelText: 'Semester',
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        border: const OutlineInputBorder(),
        enabled: enabled,
        hintText: enabled
            ? (semesters.isEmpty ? 'No semesters — add one in Manage' : null)
            : 'Select an institution first',
      ),
      items: enabled
          ? [
              ...semesters.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name),
                  )),
              const DropdownMenuItem(
                value: null,
                child: Text('None'),
              ),
            ]
          : [],
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _GpaToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GpaToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: SwitchListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Count toward GPA'),
        subtitle: Text(
          value
              ? 'Included in cumulative GPA'
              : 'Excluded — e.g. transfer credit, audit',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _NoInstitutionHint extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoInstitutionHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Add institutions & semesters via the Manage button on the Grades screen.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
