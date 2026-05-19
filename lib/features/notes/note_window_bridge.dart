import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';

/// Inter-window bridge for popped-out notes.
///
/// `desktop_multi_window` gives every pop-out its own Flutter engine /
/// isolate, so a pop-out has **no** Hive and **no** Riverpod state. The main
/// window stays the single owner of the data; pop-outs talk to it over the
/// channels defined here:
///
/// * sub → main: one shared *unidirectional* [WindowMethodChannel]
///   ([kHostChannel]) — many pop-outs invoke, the main window is the sole
///   handler. Carries `load`, `save`, `closed`.
/// * main → sub: each pop-out's own per-window controller channel — the main
///   window pushes `noteUpdated` / `noteDeleted` to a specific pop-out.
///
/// The whole thing is desktop-only; on web/Android there are no OS windows
/// and the Notes page falls back to the in-app `/note/:id` editor.

/// businessId tag put in a pop-out window's launch arguments.
const String kNoteBusinessId = 'note_popout';

/// Shared sub→main channel. Unidirectional: the main window registers the
/// only handler, every pop-out may invoke it.
const String kHostChannel = 'campusbuddy/notes_host';

// Method names.
const String _mLoad = 'load'; // sub→main: {windowId, noteId} → note JSON|null
const String _mSave = 'save'; // sub→main: note JSON
const String _mClosed = 'closed'; // sub→main: {windowId}
const String mNoteUpdated = 'noteUpdated'; // main→sub: note JSON
const String mNoteDeleted = 'noteDeleted'; // main→sub: noteId

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Parsed pop-out launch arguments. Returns null for the main window (which
/// launches with empty arguments) or any non-pop-out window.
({String noteId})? parseNoteWindowArguments(String arguments) {
  if (arguments.isEmpty) return null;
  try {
    final m = jsonDecode(arguments) as Map<String, dynamic>;
    if (m['businessId'] != kNoteBusinessId) return null;
    final id = m['noteId'] as String?;
    if (id == null || id.isEmpty) return null;
    return (noteId: id);
  } catch (_) {
    return null;
  }
}

/// Pop a note out. On desktop this opens (or refocuses) a real always-on-top
/// OS window for the note; everywhere else it falls back to the in-app
/// `/note/:id` editor (no OS windows on web/Android). Use this from every
/// "Pop out" affordance so the behaviour stays consistent.
void popOutNote(BuildContext context, String noteId) {
  if (_isDesktop) {
    unawaited(NotePopoutHost.instance.openOrFocus(noteId));
  } else {
    context.go('/note/$noteId');
  }
}

/// Lives in the **main** window. Owns the channel handler + the
/// note→window registry, and pushes note changes out to open pop-outs.
class NotePopoutHost {
  NotePopoutHost._();
  static final NotePopoutHost instance = NotePopoutHost._();

  static const _channel =
      WindowMethodChannel(kHostChannel, mode: ChannelMode.unidirectional);

  ProviderContainer? _container;
  ProviderSubscription<List<Note>>? _sub;
  StreamSubscription<void>? _windowsSub;
  bool _attached = false;

  // noteId ↔ windowId, kept in lock-step.
  final Map<String, String> _windowByNote = {};
  final Map<String, String> _noteByWindow = {};

  /// Wire the host to the app's [ProviderContainer]. Call once from the main
  /// window's `main()` (desktop only) before `runApp`.
  void attach(ProviderContainer container) {
    if (!_isDesktop || _attached) return;
    _attached = true;
    _container = container;

    _channel.setMethodCallHandler(_onSubCall);

    // Push every notes change to whichever pop-outs are showing them.
    _sub = container.listen<List<Note>>(
      notesProvider,
      (_, notes) => _broadcast(notes),
      fireImmediately: false,
    );

    // Backstop: prune windows that vanished without a clean `closed`.
    _windowsSub = onWindowsChanged.listen((_) => _pruneClosedWindows());
  }

  /// Tear the host down (the main window is going away). The singleton
  /// normally lives for the whole process, so this is mostly for tests /
  /// hot-restart hygiene.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    _sub?.close();
    await _windowsSub?.cancel();
    await _channel.setMethodCallHandler(null);
    _sub = null;
    _windowsSub = null;
    _container = null;
    _windowByNote.clear();
    _noteByWindow.clear();
  }

  Future<dynamic> _onSubCall(MethodCall call) async {
    final container = _container;
    if (container == null) return null;
    switch (call.method) {
      case _mLoad:
        final args = _decodeArgs(call.arguments);
        final windowId = args['windowId'] as String?;
        final noteId = args['noteId'] as String?;
        if (windowId != null && noteId != null) {
          _register(noteId, windowId);
        }
        final note = _find(noteId);
        return note == null ? null : jsonEncode(note.toJson());
      case _mSave:
        final map = _decodeArgs(call.arguments);
        final note = Note.fromJson(map);
        await container.read(notesProvider.notifier).upsert(note);
        return null;
      case _mClosed:
        final args = _decodeArgs(call.arguments);
        _unregister(args['windowId'] as String?);
        return null;
    }
    return null;
  }

  Map<String, dynamic> _decodeArgs(dynamic raw) {
    if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  Note? _find(String? id) {
    if (id == null) return null;
    for (final n in _container!.read(notesProvider)) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _register(String noteId, String windowId) {
    // Drop any stale mapping for either side first.
    final prevWindow = _windowByNote.remove(noteId);
    if (prevWindow != null) _noteByWindow.remove(prevWindow);
    final prevNote = _noteByWindow.remove(windowId);
    if (prevNote != null) _windowByNote.remove(prevNote);
    _windowByNote[noteId] = windowId;
    _noteByWindow[windowId] = noteId;
  }

  void _unregister(String? windowId) {
    if (windowId == null) return;
    final noteId = _noteByWindow.remove(windowId);
    if (noteId != null) _windowByNote.remove(noteId);
  }

  void _broadcast(List<Note> notes) {
    if (_noteByWindow.isEmpty) return;
    final byId = {for (final n in notes) n.id: n};
    // Copy: a push may mutate the registry via a later `closed`.
    for (final entry in _noteByWindow.entries.toList()) {
      final windowId = entry.key;
      final noteId = entry.value;
      final note = byId[noteId];
      final target = WindowController.fromWindowId(windowId);
      if (note == null) {
        unawaited(_safePush(target, mNoteDeleted, noteId));
      } else {
        unawaited(
            _safePush(target, mNoteUpdated, jsonEncode(note.toJson())));
      }
    }
  }

  Future<void> _safePush(
      WindowController target, String method, dynamic args) async {
    try {
      await target.invokeMethod(method, args);
    } catch (_) {
      // Window went away mid-push; the backstop prune will clean up.
    }
  }

  Future<void> _pruneClosedWindows() async {
    try {
      final live = (await WindowController.getAll())
          .map((c) => c.windowId)
          .toSet();
      final gone =
          _noteByWindow.keys.where((id) => !live.contains(id)).toList();
      for (final id in gone) {
        _unregister(id);
      }
    } catch (_) {}
  }

  /// Open a pop-out OS window for [noteId], or focus the existing one if
  /// that note is already popped out (one window per note).
  Future<void> openOrFocus(String noteId) async {
    if (!_isDesktop) return;
    final existing = _windowByNote[noteId];
    if (existing != null) {
      try {
        await WindowController.fromWindowId(existing).show();
        return;
      } catch (_) {
        // Stale entry — the window was gone. Fall through and recreate.
        _unregister(existing);
      }
    }
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode(
            {'businessId': kNoteBusinessId, 'noteId': noteId}),
      ),
    );
    _register(noteId, controller.windowId);
    // The pop-out sizes + pins + shows itself once its engine is ready
    // (see runNoteWindow); nothing else to do here.
  }
}

/// Client side helper used by the pop-out window to reach the main window.
class NoteHostClient {
  const NoteHostClient(this.windowId);

  /// This pop-out's own window id (from `WindowController.fromCurrentEngine`).
  final String windowId;

  static const _channel =
      WindowMethodChannel(kHostChannel, mode: ChannelMode.unidirectional);

  /// Fetch the note's current state from the main window (null = deleted).
  Future<Note?> load(String noteId) async {
    final raw = await _channel.invokeMethod<String>(
        _mLoad, jsonEncode({'windowId': windowId, 'noteId': noteId}));
    if (raw == null) return null;
    return Note.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Persist an edit through the main window's Hive/Riverpod.
  Future<void> save(Note note) =>
      _channel.invokeMethod(_mSave, jsonEncode(note.toJson()));

  /// Tell the main window this pop-out is closing so it stops pushing.
  Future<void> notifyClosed() =>
      _channel.invokeMethod(_mClosed, jsonEncode({'windowId': windowId}));
}
