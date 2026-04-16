import 'package:flutter/material.dart';
import 'focus/focus_overlay.dart';
import 'grades/grades_screen.dart';
import 'home/home_dashboard.dart';
import 'planner/planner_screen.dart';
import 'profile/profile_screen.dart';
import 'study/study_screen.dart';
import 'todo/todo_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 0=Home, 1=Planner, 2=Study, 3=Todo, 4=Grades, 5=Profile
  int _selectedIndex = 0;

  void _navigate(int index) => setState(() => _selectedIndex = index);

  Widget _currentPage() {
    switch (_selectedIndex) {
      case 0:
        return HomeDashboard(
          onGoToPlanner: () => _navigate(1),
          onGoToGrades: () => _navigate(4),
          onGoToTodo: () => _navigate(3),
        );
      case 1:
        return const PlannerScreen();
      case 2:
        return const StudyScreen();
      case 3:
        return const TodoScreen();
      case 4:
        return const GradesScreen();
      case 5:
        return ProfileScreen(
          themeMode: widget.themeMode,
          onToggleTheme: widget.onToggleTheme,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  static const _pageTitles = {
    0: 'Home',
    1: 'Planner',
    2: 'Study',
    3: 'Todo',
    4: 'Grades',
    5: 'Profile',
  };

  void _showFocusOverlay() => showFocusOverlay(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _TopNavBar(
            selectedIndex: _selectedIndex,
            onNavigate: _navigate,
            onFocus: _showFocusOverlay,
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          // Page title bar (shown for non-home pages)
          if (_selectedIndex != 0) ...[
            _PageHeader(title: _pageTitles[_selectedIndex] ?? ''),
          ],
          Expanded(child: _currentPage()),
        ],
      ),
    );
  }
}

// ── Page title bar ────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final String title;
  const _PageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ── Top navigation bar ────────────────────────────────────────────────────────

class _TopNavBar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onNavigate;
  final VoidCallback onFocus;

  const _TopNavBar({
    required this.selectedIndex,
    required this.onNavigate,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // Logo
          Icon(Icons.menu_book_rounded,
              color: theme.colorScheme.primary, size: 26),
          const SizedBox(width: 8),
          Text('Campus Buddy',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 32),
          // Main nav tabs: Home | Planner | Study
          _NavTab(label: 'Home',    index: 0, selected: selectedIndex == 0, onTap: onNavigate),
          const SizedBox(width: 4),
          _NavTab(label: 'Planner', index: 1, selected: selectedIndex == 1, onTap: onNavigate),
          const SizedBox(width: 4),
          _NavTab(label: 'Study',   index: 2, selected: selectedIndex == 2, onTap: onNavigate),
          const Spacer(),
          // Quick-action icon buttons
          _QuickActionButton(
            icon: Icons.checklist_rounded,
            label: 'Todo',
            active: selectedIndex == 3,
            onTap: () => onNavigate(3),
          ),
          _QuickActionButton(
            icon: Icons.timer_outlined,
            label: 'Timer',
            active: selectedIndex == 2,
            onTap: () => onNavigate(2),
          ),
          _QuickActionButton(
            icon: Icons.trending_up_rounded,
            label: 'Grades',
            active: selectedIndex == 4,
            onTap: () => onNavigate(4),
          ),
          _QuickActionButton(
            icon: Icons.psychology_outlined,
            label: 'Focus',
            active: false,
            onTap: onFocus,
          ),
          const SizedBox(width: 12),
          // Profile avatar button
          Tooltip(
            message: 'Profile & Settings',
            child: GestureDetector(
              onTap: () => onNavigate(5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectedIndex == 5
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: const UserAvatar(size: 36),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final int index;
  final bool selected;
  final void Function(int) onTap;

  const _NavTab({
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface
                          .withValues(alpha: 0.6)),
              const SizedBox(height: 2),
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                      fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}
