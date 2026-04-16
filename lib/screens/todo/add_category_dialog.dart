import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/todo_category.dart';

class AddCategoryDialog extends StatefulWidget {
  final TodoCategory? existing;
  const AddCategoryDialog({super.key, this.existing});

  @override
  State<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late int _selectedColor;
  late String _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _selectedColor =
        widget.existing?.colorValue ?? TodoCategory.palette.first;
    _selectedIcon = widget.existing?.iconKey ?? 'school';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final cat = TodoCategory(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      colorValue: _selectedColor,
      iconKey: _selectedIcon,
    );
    Navigator.of(context).pop(cat);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(isEdit ? 'Edit Category' : 'New Category'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  hintText: 'e.g. Calculus, Physics Lab',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name' : null,
              ),
              const SizedBox(height: 20),
              Text('Color', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TodoCategory.palette.map((c) {
                  final selected = c == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color: Color(c).withValues(alpha: 0.4),
                                    blurRadius: 6)
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text('Icon', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TodoCategory.icons.entries.map((e) {
                  final selected = e.key == _selectedIcon;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? Color(_selectedColor).withValues(alpha: 0.2)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? Color(_selectedColor)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(e.value,
                          size: 20,
                          color: selected
                              ? Color(_selectedColor)
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6)),
                    ),
                  );
                }).toList(),
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
          style: FilledButton.styleFrom(
              backgroundColor: Color(_selectedColor)),
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
