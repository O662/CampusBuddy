import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animated_gradient_background.dart';
import '../../core/widgets/note_editing.dart';
import '../../data/models.dart';
import 'note_window_bridge.dart';

/// Entry point for a popped-out note's own OS window. Runs in its own
/// Flutter engine with **no** Hive/Riverpod — every read/write round-trips
/// to the main window via [NoteHostClient]. Sizing + always-on-top are
/// driven through `window_manager`, which resolves this engine's own native
/// window (per-registrar), so the pin only affects this pop-out.
void runNoteWindow(WindowController controller, String noteId) {
  const options = WindowOptions(
    size: Size(460, 580),
    minimumSize: Size(320, 360),
    center: true,
    title: 'Note · CampusBuddy',
    titleBarStyle: TitleBarStyle.normal,
    backgroundColor: Color(0xFF15132B),
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(NoteWindowApp(controller: controller, noteId: noteId));
}

class NoteWindowApp extends StatelessWidget {
  const NoteWindowApp({
    super.key,
    required this.controller,
    required this.noteId,
  });

  final WindowController controller;
  final String noteId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: NoteWindowPage(controller: controller, noteId: noteId),
    );
  }
}

class NoteWindowPage extends StatefulWidget {
  const NoteWindowPage({
    super.key,
    required this.controller,
    required this.noteId,
  });

  final WindowController controller;
  final String noteId;

  @override
  State<NoteWindowPage> createState() => _NoteWindowPageState();
}

class _NoteWindowPageState extends State<NoteWindowPage>
    with WindowListener {
  late final NoteHostClient _client =
      NoteHostClient(widget.controller.windowId);

  Note? _note;
  bool _loading = true;
  bool _deleted = false;
  bool _pinned = true;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Intercept the OS close button so we can tell the main window to stop
    // pushing to this (now gone) pop-out before the window is destroyed.
    unawaited(windowManager.setPreventClose(true));
    unawaited(widget.controller.setWindowMethodHandler(_onMainCall));
    unawaited(_load());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final note = await _client.load(widget.noteId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (note == null) {
          _deleted = true;
        } else {
          _note = note;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _deleted = true; // main window unreachable — nothing to edit.
      });
    }
  }

  /// Handles main→sub pushes on this window's dedicated channel.
  Future<dynamic> _onMainCall(MethodCall call) async {
    switch (call.method) {
      case mNoteUpdated:
        final note = Note.fromJson(
            _asMap(call.arguments) ?? const {});
        if (note.id == widget.noteId && mounted) {
          setState(() {
            _note = note;
            _deleted = false;
            _loading = false;
          });
        }
        return null;
      case mNoteDeleted:
        if (mounted) setState(() => _deleted = true);
        return null;
      case 'window_close':
        await _close();
        return null;
    }
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      final decoded = _tryJson(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  dynamic _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  void _onSave(Note next) {
    setState(() => _note = next); // optimistic — keep the editor responsive
    unawaited(_client.save(next));
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    setState(() => _pinned = next);
    try {
      await windowManager.setAlwaysOnTop(next);
    } catch (_) {}
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      await _client.notifyClosed();
    } catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // OS window-close button.
  @override
  void onWindowClose() {
    unawaited(_close());
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return Scaffold(
      backgroundColor: AppPalette.scaffoldBase,
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_deleted || note == null)
                    ? NoteDeletedView(onClose: _close)
                    : NoteEditorView(
                        note: note,
                        onSave: _onSave,
                        onClose: _close,
                        pinned: _pinned,
                        onTogglePin: _togglePin,
                      ),
          ),
        ),
      ),
    );
  }
}
