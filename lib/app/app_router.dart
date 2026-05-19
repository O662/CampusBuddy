import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/center/center_page.dart';
import '../features/dashboard/customize_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/grades/course_detail_page.dart';
import '../features/grades/grades_page.dart';
import '../features/notes/note_popout_page.dart';
import '../features/notes/notes_page.dart';
import '../features/planner/planner_page.dart';
import '../features/profile/profile_page.dart';
import '../features/study/study_page.dart';
import '../features/timer/timer_page.dart';
import '../features/todo/todo_page.dart';
import 'app_shell.dart';

CustomTransitionPage<void> _fade(Widget child) => CustomTransitionPage(
      child: child,
      // Snappy: a long fade over the stacked BackdropFilter blurs read as
      // lag, so keep it short in both directions.
      transitionDuration: const Duration(milliseconds: 120),
      reverseTransitionDuration: const Duration(milliseconds: 120),
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
          path: '/customize',
          pageBuilder: (context, state) => _fade(const CustomizePage()),
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
        // Pomodoro merged into the Timer page; keep the old path working.
        GoRoute(
          path: '/pomodoro',
          redirect: (context, state) => '/timer',
        ),
        GoRoute(
          path: '/notes',
          pageBuilder: (context, state) => _fade(const NotesPage()),
        ),
        GoRoute(
          path: '/grades',
          pageBuilder: (context, state) => _fade(const GradesPage()),
        ),
        GoRoute(
          path: '/course/:id',
          pageBuilder: (context, state) => _fade(
              CourseDetailPage(courseId: state.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => _fade(const ProfilePage()),
        ),
      ],
    ),
    // Center lives outside the shell so it fills the whole screen — an
    // immersive breathing space with no rail or top bar.
    GoRoute(
      path: '/center',
      pageBuilder: (context, state) => _fade(const CenterPage()),
    ),
    // "Focus" was renamed to "Center"; keep the old path working.
    GoRoute(
      path: '/focus',
      redirect: (context, state) => '/center',
    ),
    // A single note popped out into a compact, always-on-top window.
    // Outside the shell so it fills the (shrunken) window on its own.
    GoRoute(
      path: '/note/:id',
      pageBuilder: (context, state) =>
          _fade(NotePopoutPage(noteId: state.pathParameters['id']!)),
    ),
  ],
);
