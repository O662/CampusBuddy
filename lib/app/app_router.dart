import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/focus/focus_page.dart';
import '../features/grades/grades_page.dart';
import '../features/planner/planner_page.dart';
import '../features/pomodoro/pomodoro_page.dart';
import '../features/profile/profile_page.dart';
import '../features/study/study_page.dart';
import '../features/timer/timer_page.dart';
import '../features/todo/todo_page.dart';
import 'app_shell.dart';

CustomTransitionPage<void> _fade(Widget child) => CustomTransitionPage(
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => _fade(const DashboardPage()),
        ),
        GoRoute(
          path: '/planner',
          pageBuilder: (context, state) => _fade(const PlannerPage()),
        ),
        GoRoute(
          path: '/study',
          pageBuilder: (context, state) => _fade(const StudyPage()),
        ),
        GoRoute(
          path: '/todo',
          pageBuilder: (context, state) => _fade(const TodoPage()),
        ),
        GoRoute(
          path: '/timer',
          pageBuilder: (context, state) => _fade(const TimerPage()),
        ),
        GoRoute(
          path: '/pomodoro',
          pageBuilder: (context, state) => _fade(const PomodoroPage()),
        ),
        GoRoute(
          path: '/grades',
          pageBuilder: (context, state) => _fade(const GradesPage()),
        ),
        GoRoute(
          path: '/focus',
          pageBuilder: (context, state) => _fade(const FocusPage()),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => _fade(const ProfilePage()),
        ),
      ],
    ),
  ],
);
