import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../models/course.dart';

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

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _creditsCtrl = TextEditingController(
        text: widget.existing?.credits.toString() ?? '3');
    _gradeCtrl = TextEditingController(
        text: widget.existing?.gradePercent.toString() ?? '');
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
    );
    Navigator.of(context).pop(course);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Course' : 'Add Course'),
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
                  labelText: 'Course Name',
                  hintText: 'e.g. Calculus II',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a course name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _creditsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Credit Hours',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                ],
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter valid credit hours';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gradeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Grade (%)',
                  hintText: 'e.g. 87.5',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                ],
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 0 || n > 100) {
                    return 'Enter a grade between 0 and 100';
                  }
                  return null;
                },
              ),
            ],
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
