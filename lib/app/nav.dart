import 'package:flutter/material.dart';

/// A single navigable destination.
class NavItem {
  const NavItem(this.route, this.label, this.icon);
  final String route;
  final String label;
  final IconData icon;
}

/// Primary menu — the persistent vertical rail on the left.
const primaryNav = <NavItem>[
  NavItem('/dashboard', 'Dashboard', Icons.dashboard_rounded),
  NavItem('/planner', 'Planner', Icons.calendar_month_rounded),
  NavItem('/study', 'Study', Icons.style_rounded),
];

/// Secondary menu — the horizontal menu at the top-right.
const secondaryNav = <NavItem>[
  NavItem('/todo', 'To-do', Icons.checklist_rounded),
  NavItem('/timer', 'Timer', Icons.timer_outlined),
  NavItem('/pomodoro', 'Pomodoro', Icons.av_timer_rounded),
  NavItem('/grades', 'Grades', Icons.school_rounded),
  NavItem('/focus', 'Focus', Icons.center_focus_strong_rounded),
];

const profileNav = NavItem('/profile', 'Profile', Icons.person_rounded);

String titleForRoute(String location) {
  for (final n in [...primaryNav, ...secondaryNav, profileNav]) {
    if (location.startsWith(n.route)) {
      return n.route == '/profile' ? 'Profile & Settings' : n.label;
    }
  }
  return 'CampusBuddy';
}
