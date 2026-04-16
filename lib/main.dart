import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/flashcard_provider.dart';
import 'providers/grades_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/study_provider.dart';
import 'providers/task_planner_provider.dart';
import 'providers/todo_provider.dart';
import 'providers/user_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final gradesProvider = GradesProvider();
  final todoProvider = TodoProvider();
  final scheduleProvider = ScheduleProvider();
  final studyProvider = StudyProvider();
  final userProvider = UserProvider();
  final taskPlannerProvider = TaskPlannerProvider();
  final flashcardProvider = FlashcardProvider();

  await Future.wait([
    gradesProvider.load(),
    todoProvider.load(),
    scheduleProvider.load(),
    studyProvider.load(),
    userProvider.load(),
    taskPlannerProvider.load(),
    flashcardProvider.load(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gradesProvider),
        ChangeNotifierProvider.value(value: todoProvider),
        ChangeNotifierProvider.value(value: scheduleProvider),
        ChangeNotifierProvider.value(value: studyProvider),
        ChangeNotifierProvider.value(value: userProvider),
        ChangeNotifierProvider.value(value: taskPlannerProvider),
        ChangeNotifierProvider.value(value: flashcardProvider),
      ],
      child: const CampusBuddyApp(),
    ),
  );
}

class CampusBuddyApp extends StatefulWidget {
  const CampusBuddyApp({super.key});

  @override
  State<CampusBuddyApp> createState() => _CampusBuddyAppState();
}

class _CampusBuddyAppState extends State<CampusBuddyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Buddy',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5C6BC0),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5C6BC0),
        brightness: Brightness.dark,
      ),
      home: HomeScreen(
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
