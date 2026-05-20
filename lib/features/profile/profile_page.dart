import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
import '../../data/backup_service.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late TextEditingController _name;
  late TextEditingController _school;
  late TextEditingController _major;
  late int _goal;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _name = TextEditingController(text: p.name);
    _school = TextEditingController(text: p.school);
    _major = TextEditingController(text: p.major);
    _goal = p.dailyGoalMinutes;
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    _major.dispose();
    super.dispose();
  }

  void _save() {
    // Focus / break lengths used to live in Profile; they're now per-preset
    // on the Pomodoro board. Preserve any legacy value already on disk so
    // existing backups round-trip cleanly even though no UI sets it.
    final current = ref.read(profileProvider);
    ref.read(profileProvider.notifier).save(UserProfile(
          name: _name.text.trim().isEmpty ? 'Student' : _name.text.trim(),
          school: _school.text.trim(),
          major: _major.text.trim(),
          dailyGoalMinutes: _goal,
          focusLengthMinutes: current.focusLengthMinutes,
          breakLengthMinutes: current.breakLengthMinutes,
        ));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved 🌟')));
  }

  /// Push a freshly imported profile back into the on-screen fields (they're
  /// seeded once in [initState], so a backup restore must refresh them).
  void _reloadFromProfile(UserProfile p) {
    _name.text = p.name;
    _school.text = p.school;
    _major.text = p.major;
    setState(() => _goal = p.dailyGoalMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Profile & Settings',
      subtitle: 'Make CampusBuddy yours.',
      actions: [
        SoftButton(
            label: 'Save', filled: true, icon: Icons.check_rounded, onTap: _save),
      ],
      child: CardGrid(
        children: [
          GlassCard(
            title: 'About you',
            icon: Icons.person_rounded,
            child: Column(
              children: [
                _LabeledField(label: 'Name', controller: _name),
                _LabeledField(label: 'School', controller: _school),
                _LabeledField(label: 'Major', controller: _major),
              ],
            ),
          ),
          GlassCard(
            title: 'Study preferences',
            icon: Icons.tune_rounded,
            child: Column(
              children: [
                _Stepper(
                  label: 'Daily study goal',
                  value: _goal,
                  suffix: 'min',
                  step: 15,
                  min: 15,
                  onChanged: (v) => setState(() => _goal = v),
                ),
              ],
            ),
          ),
          const _InstitutionsCard(),
          const _BackupCard(),
          GlassCard(
            title: 'About CampusBuddy',
            icon: Icons.info_outline_rounded,
            child: const Text(
              'CampusBuddy keeps your coursework, planner and study tools in '
              'one calm place. All data is stored locally on this device.\n\n'
              'Version 1.0.0',
              style: TextStyle(color: AppPalette.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppPalette.textSecondary)),
          const SizedBox(height: 6),
          TextField(controller: controller),
        ],
      ),
    );
  }
}

/// Manage institutions and the grading system each one uses. The chosen
/// system flows down to every current course filed under that institution.
class _InstitutionsCard extends ConsumerWidget {
  const _InstitutionsCard();

  String _systemLabel(Institution i) {
    switch (i.gradeSystem) {
      case GradeSystem.percent:
        return 'Percentage';
      case GradeSystem.points:
        final m = i.effectiveGpaMax;
        final s = m == m.roundToDouble()
            ? m.toStringAsFixed(1)
            : m.toString();
        return 'GPA $s · ${i.gpaComplex ? 'complex' : 'simple'}'
            '${i.weighted ? ' · weighted' : ''}';
      case GradeSystem.letter:
        return 'Letter${i.usePlusMinus ? ' (+/−)' : ''}';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final institutions = [...ref.watch(institutionsProvider)]
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return GlassCard(
      title: 'Institutions & grading',
      icon: Icons.account_balance_rounded,
      trailing: SoftButton(
        label: 'Add',
        onTap: () async {
          final i = await showInstitutionDialog(context);
          if (i != null) {
            ref.read(institutionsProvider.notifier).upsert(i);
          }
        },
      ),
      child: institutions.isEmpty
          ? const EmptyHint(
              'Add your school to choose how it grades — that style '
              'carries to its current courses.')
          : Column(
              children: [
                for (final inst in institutions)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final e = await showInstitutionDialog(context,
                          existing: inst);
                      if (e != null) {
                        ref
                            .read(institutionsProvider.notifier)
                            .upsert(e);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_rounded,
                              size: 18, color: AppPalette.lavender),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(inst.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          GlassChip(
                              label: _systemLabel(inst),
                              color: AppPalette.mint),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_rounded,
                              size: 16,
                              color: AppPalette.textSecondary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.suffix,
    required this.step,
    required this.min,
    required this.onChanged,
  });

  final String label;
  final int value;
  final String suffix;
  final int step;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: AppPalette.textSecondary,
            onPressed: () => onChanged((value - step).clamp(min, 999)),
          ),
          SizedBox(
            width: 70,
            child: Text('$value $suffix',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppPalette.textSecondary,
            onPressed: () => onChanged(value + step),
          ),
        ],
      ),
    );
  }
}

/// Export selected data to a JSON file the user picks, and restore from one.
/// Import is a *merge*: items are upserted by id, so nothing already on the
/// device is deleted.
class _BackupCard extends ConsumerStatefulWidget {
  const _BackupCard();

  @override
  ConsumerState<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<_BackupCard> {
  // Everything is ticked for export by default.
  final Set<BackupCategory> _selected = {...BackupCategory.values};
  bool _busy = false;

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  String _two(int v) => v.toString().padLeft(2, '0');

  Future<void> _export() async {
    if (_busy) return;
    if (_selected.isEmpty) {
      _toast('Pick at least one thing to export.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final jsonText = ref.read(backupServiceProvider).buildJson(_selected);
      final now = DateTime.now();
      final name = 'campusbuddy-backup-'
          '${now.year}-${_two(now.month)}-${_two(now.day)}.json';
      final bytes = Uint8List.fromList(utf8.encode(jsonText));
      final file =
          XFile.fromData(bytes, mimeType: 'application/json', name: name);

      final isMobile = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

      if (isMobile) {
        // No native save dialog on mobile — hand the file to the OS share
        // sheet (Save to Files, Drive, email…). `fileNameOverrides` because
        // cross_file ignores XFile.name off the web.
        final result = await SharePlus.instance.share(ShareParams(
          files: [file],
          fileNameOverrides: [name],
          subject: name,
        ));
        if (result.status == ShareResultStatus.dismissed) return;
        messenger.showSnackBar(
            const SnackBar(content: Text('Backup shared 💾')));
      } else {
        // Desktop + web: native save dialog (file_selector_web returns a
        // dummy path and the browser downloads instead).
        const group = XTypeGroup(label: 'JSON backup', extensions: ['json']);
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [group],
        );
        if (location == null) return; // cancelled
        await file.saveTo(location.path);
        messenger.showSnackBar(
            const SnackBar(content: Text('Backup exported 💾')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      const group = XTypeGroup(label: 'JSON backup', extensions: ['json']);
      final picked = await openFile(acceptedTypeGroups: const [group]);
      if (picked == null) return; // cancelled
      final text = await picked.readAsString();
      final ParsedBackup backup;
      try {
        backup = BackupService.parse(text);
      } on BackupFormatException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
      if (!mounted) return;
      final chosen = await _chooseImport(backup);
      if (chosen == null || chosen.isEmpty) return;
      final applied =
          await ref.read(backupServiceProvider).applyMerge(backup, chosen);
      // The merge writes straight to Hive; rebuild the notifiers it touched
      // so every open page reflects the restored data immediately.
      refreshAfterImport(ref, applied);
      if (applied.contains(BackupCategory.profile) && mounted) {
        context
            .findAncestorStateOfType<_ProfilePageState>()
            ?._reloadFromProfile(ref.read(profileProvider));
      }
      final n = applied.length;
      messenger.showSnackBar(SnackBar(
          content: Text('Imported $n section${n == 1 ? '' : 's'} ✨')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Lets the user confirm/trim which of the file's categories to restore.
  Future<Set<BackupCategory>?> _chooseImport(ParsedBackup backup) {
    final sel = {...backup.categories};
    final when = backup.exportedAt;
    return showGlassDialog<Set<BackupCategory>>(
      context,
      title: 'Import backup',
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${when == null ? '' : 'From ${relativeDay(when)}. '}'
              'Choose what to restore. Matching items are added or '
              'updated — nothing already on this device is removed.',
              style: const TextStyle(
                  color: AppPalette.textSecondary,
                  fontSize: 13,
                  height: 1.4),
            ),
            const SizedBox(height: 14),
            for (final c in BackupCategory.values)
              if (backup.categories.contains(c))
                _CategoryRow(
                  category: c,
                  value: sel.contains(c),
                  onChanged: (v) =>
                      setLocal(() => v ? sel.add(c) : sel.remove(c)),
                ),
            if (sel.contains(BackupCategory.todos) &&
                !sel.contains(BackupCategory.coursesGrades) &&
                backup.categories.contains(BackupCategory.coursesGrades))
              const _GradeLinkHint(),
          ],
        ),
      ),
      actions: (dctx) => [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: const Color(0xFF15132B)),
          onPressed: () => Navigator.pop(dctx, sel),
          child: const Text('Import'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      title: 'Backup & restore',
      icon: Icons.cloud_sync_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Save your data to a file you control, or restore it from one. '
            'Importing merges by item — nothing already here is deleted.',
            style: TextStyle(
                color: AppPalette.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          for (final c in BackupCategory.values)
            _CategoryRow(
              category: c,
              value: _selected.contains(c),
              onChanged: _busy
                  ? null
                  : (v) => setState(
                      () => v ? _selected.add(c) : _selected.remove(c)),
            ),
          if (_selected.contains(BackupCategory.todos) &&
              !_selected.contains(BackupCategory.coursesGrades))
            const _GradeLinkHint(),
          const SizedBox(height: 18),
          Row(
            children: [
              SoftButton(
                label: 'Export',
                filled: true,
                icon: Icons.file_download_outlined,
                onTap: _export,
              ),
              const SizedBox(width: 10),
              SoftButton(
                label: 'Import',
                icon: Icons.file_upload_outlined,
                onTap: _import,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tappable icon + label row with a trailing checkbox, used both for the
/// export selection and the import confirm dialog.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.value,
    required this.onChanged,
  });

  final BackupCategory category;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(category.icon,
                size: 18,
                color: enabled
                    ? AppPalette.lavender
                    : AppPalette.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(category.label,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                activeColor: AppPalette.accent,
                side:
                    const BorderSide(color: AppPalette.textSecondary),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when To-dos are (de)selected without Courses & grades: assignment
/// placeholder grades are mirrored from the grades box, so to-dos alone
/// don't carry them ([TaskNotifier] rebuilds the link only on next edit).
class _GradeLinkHint extends StatelessWidget {
  const _GradeLinkHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppPalette.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: AppPalette.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add “Courses & grades” too — assignment grades are linked to '
              'their tasks, so to-dos on their own won’t bring those grades '
              'back until each task is edited.',
              style: TextStyle(
                  color: AppPalette.textSecondary,
                  fontSize: 12,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
