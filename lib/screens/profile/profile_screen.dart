import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

class ProfileScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const ProfileScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AvatarSection(),
                const SizedBox(height: 32),
                _NameSection(),
                const SizedBox(height: 16),
                _AppearanceSection(
                  themeMode: themeMode,
                  onToggleTheme: onToggleTheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            _Avatar(size: 110, user: user),
            GestureDetector(
              onTap: () => _pickImage(context, user),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: theme.colorScheme.surface, width: 2),
                ),
                child: const Icon(Icons.camera_alt,
                    size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          user.name,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _pickImage(context, user),
              icon: const Icon(Icons.upload_outlined, size: 16),
              label: const Text('Change Photo'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
            if (user.profileImagePath != null) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => user.setProfileImage(null),
                icon: Icon(Icons.delete_outline,
                    size: 16, color: theme.colorScheme.error),
                label: Text('Remove',
                    style: TextStyle(color: theme.colorScheme.error)),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ],
        ),
        // Avatar color picker (only when no image)
        if (user.profileImagePath == null) ...[
          const SizedBox(height: 8),
          _AvatarColorPicker(user: user),
        ],
      ],
    );
  }

  Future<void> _pickImage(BuildContext context, UserProvider user) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      await user.setProfileImage(result.files.single.path);
    }
  }
}

class _Avatar extends StatelessWidget {
  final double size;
  final UserProvider user;

  const _Avatar({required this.size, required this.user});

  @override
  Widget build(BuildContext context) {
    final imagePath = user.profileImagePath;
    final color = user.avatarColor;
    final theme = Theme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.2),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: 3,
        ),
      ),
      child: ClipOval(
        child: imagePath != null && File(imagePath).existsSync()
            ? Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                width: size,
                height: size,
              )
            : Center(
                child: Text(
                  user.initials,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );
  }
}

// Small version used in the nav bar
class UserAvatar extends StatelessWidget {
  final double size;
  const UserAvatar({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    return _Avatar(size: size, user: user);
  }
}

class _AvatarColorPicker extends StatelessWidget {
  final UserProvider user;
  const _AvatarColorPicker({required this.user});

  static const _colors = [
    0xFF5C6BC0, // indigo
    0xFFEF5350, // red
    0xFFEC407A, // pink
    0xFFAB47BC, // purple
    0xFF42A5F5, // blue
    0xFF26A69A, // teal
    0xFF66BB6A, // green
    0xFFFFA726, // orange
    0xFF8D6E63, // brown
    0xFF78909C, // grey-blue
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('Avatar Color',
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _colors.map((c) {
            final selected = user.avatarColor.toARGB32() == c ||
                (c == _colors[0] &&
                    user.avatarColor == const Color(0xFF5C6BC0));
            return GestureDetector(
              onTap: () => user.setAvatarColor(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Name ──────────────────────────────────────────────────────────────────────

class _NameSection extends StatefulWidget {
  @override
  State<_NameSection> createState() => _NameSectionState();
}

class _NameSectionState extends State<_NameSection> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: context.read<UserProvider>().name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<UserProvider>().setName(_ctrl.text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<UserProvider>();

    if (!_editing) {
      _ctrl.text = user.name;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Profile',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            Text('Display Name',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onTap: () => setState(() => _editing = true),
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Enter your name',
                      suffixIcon: _editing
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  onPressed: _save,
                                  tooltip: 'Save',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined),
                                  onPressed: () {
                                    _ctrl.text = user.name;
                                    setState(() => _editing = false);
                                  },
                                  tooltip: 'Cancel',
                                ),
                              ],
                            )
                          : const Icon(Icons.edit_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Appearance ────────────────────────────────────────────────────────────────

class _AppearanceSection extends StatelessWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const _AppearanceSection({
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = themeMode == ThemeMode.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Appearance',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dark Mode',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      Text(
                        isDark ? 'Currently on' : 'Currently off',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isDark,
                  onChanged: (_) => onToggleTheme(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
