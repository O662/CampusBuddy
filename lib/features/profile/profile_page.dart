import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/widgets/entry_dialogs.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';
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
  late int _focus;
  late int _breakLen;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _name = TextEditingController(text: p.name);
    _school = TextEditingController(text: p.school);
    _major = TextEditingController(text: p.major);
    _goal = p.dailyGoalMinutes;
    _focus = p.focusLengthMinutes;
    _breakLen = p.breakLengthMinutes;
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    _major.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(profileProvider.notifier).save(UserProfile(
          name: _name.text.trim().isEmpty ? 'Student' : _name.text.trim(),
          school: _school.text.trim(),
          major: _major.text.trim(),
          dailyGoalMinutes: _goal,
          focusLengthMinutes: _focus,
          breakLengthMinutes: _breakLen,
        ));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved 🌟')));
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
                _Stepper(
                  label: 'Focus session length',
                  value: _focus,
                  suffix: 'min',
                  step: 5,
                  min: 5,
                  onChanged: (v) => setState(() => _focus = v),
                ),
                _Stepper(
                  label: 'Break length',
                  value: _breakLen,
                  suffix: 'min',
                  step: 1,
                  min: 1,
                  onChanged: (v) => setState(() => _breakLen = v),
                ),
              ],
            ),
          ),
          const _InstitutionsCard(),
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
