import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends ChangeNotifier {
  static const _nameKey = 'user_name';
  static const _imageKey = 'profile_image_path';
  static const _avatarColorKey = 'avatar_color';

  String _name = 'Student';
  String? _profileImagePath;
  int _avatarColorValue = 0xFF5C6BC0; // default indigo

  String get name => _name;
  String? get profileImagePath => _profileImagePath;
  Color get avatarColor => Color(_avatarColorValue);

  String get initials {
    final parts = _name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _name.isNotEmpty ? _name[0].toUpperCase() : '?';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_nameKey) ?? 'Student';
    _profileImagePath = prefs.getString(_imageKey);
    _avatarColorValue =
        prefs.getInt(_avatarColorKey) ?? 0xFF5C6BC0;
    notifyListeners();
  }

  Future<void> setName(String name) async {
    _name = name.trim().isEmpty ? 'Student' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _name);
    notifyListeners();
  }

  Future<void> setProfileImage(String? path) async {
    _profileImagePath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_imageKey, path);
    } else {
      await prefs.remove(_imageKey);
    }
    notifyListeners();
  }

  Future<void> setAvatarColor(int colorValue) async {
    _avatarColorValue = colorValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_avatarColorKey, colorValue);
    notifyListeners();
  }
}
