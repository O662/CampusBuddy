import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/local_store.dart';

/// On-disk store for flashcard image attachments. Pictures live under
/// `<appSupport>/campus_buddy/card_images/<uuid>.<ext>`, the same root
/// Hive uses for everything else so backups stay co-located. The
/// `Flashcard` model only ever stores the bare filename — absolute paths
/// would break the second the OS moved the support dir.
class CardImageStore {
  CardImageStore._();

  static const _subdir = 'card_images';
  static const _allowedExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  /// Resolves (creating if needed) the directory all card images live in.
  /// Mirrors [LocalStore.init]'s choice of `getApplicationSupportDirectory`
  /// so we share its OneDrive-safe location.
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/campus_buddy/$_subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Absolute file for a stored filename — call after a non-null lookup so
  /// `Image.file` has a real path. Doesn't check that the file exists;
  /// callers using `Image.file` get a frame error if it's missing, which
  /// is exactly the right signal (we surface it as a broken-image icon).
  static Future<File> fileFor(String name) async {
    final dir = await _dir();
    return File('${dir.path}/$name');
  }

  /// Synchronous-ish convenience: many UI sites already have the absolute
  /// support dir cached via [_dir]; this just rebuilds the path so callers
  /// can construct an `Image.file` inside a sync `build` once they have
  /// the directory in hand.
  static String pathFor(Directory dir, String name) =>
      '${dir.path}/$name';

  /// Opens the OS picker, copies the chosen file into the card-images dir
  /// under a fresh uuid, and returns the stored filename. Returns null if
  /// the user cancelled or picked a file with an unsupported extension.
  static Future<String?> pickAndStore() async {
    const group = XTypeGroup(
      label: 'Image',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    );
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked == null) return null;

    final ext = _extOf(picked.name).toLowerCase();
    if (!_allowedExt.contains(ext)) return null;

    final dir = await _dir();
    final dest = File('${dir.path}/${newId()}.$ext');
    final bytes = await picked.readAsBytes();
    await dest.writeAsBytes(bytes, flush: true);
    return dest.uri.pathSegments.last;
  }

  /// Best-effort delete — missing files are silently ignored so card
  /// deletion never fails just because an image was already gone (manual
  /// cleanup, restored backup, etc.).
  static Future<void> deleteByName(String? name) async {
    if (name == null || name.isEmpty) return;
    try {
      final file = await fileFor(name);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Swallow — the user-visible action (deleting the card) shouldn't
      // surface filesystem hiccups.
    }
  }

  static String _extOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1);
  }
}
