import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/local_store.dart';
import 'features/notes/note_window.dart';
import 'features/notes/note_window_bridge.dart';
import 'state/app_state.dart';

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();

    // Every engine (main window + each popped-out note) runs this same
    // main(). Ask the plugin which window we are; a pop-out launches with
    // note arguments and runs a tiny editor app with no Hive/Riverpod.
    try {
      final wc = await WindowController.fromCurrentEngine();
      final popout = parseNoteWindowArguments(wc.arguments);
      if (popout != null) {
        runNoteWindow(wc, popout.noteId);
        return;
      }
    } catch (_) {
      // Plugin unavailable — fall through and run as the normal app.
    }

    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(960, 640),
      center: true,
      title: 'CampusBuddy',
      titleBarStyle: TitleBarStyle.normal,
      backgroundColor: Color(0xFF15132B),
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final store = await LocalStore.init();

  final container = ProviderContainer(
    overrides: [localStoreProvider.overrideWithValue(store)],
  );

  // Main window only: own the note pop-out channel + push live updates.
  NotePopoutHost.instance.attach(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CampusBuddyApp(),
    ),
  );
}

class CampusBuddyApp extends StatelessWidget {
  const CampusBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CampusBuddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
