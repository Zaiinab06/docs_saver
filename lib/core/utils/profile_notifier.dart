import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileNotifier {
  static final ValueNotifier<String> nameNotifier = ValueNotifier<String>('');
  static final ValueNotifier<String?> imagePathNotifier = ValueNotifier<String?>(null);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    nameNotifier.value = prefs.getString('user_full_name') ?? prefs.getString('user_custom_name') ?? '';
    imagePathNotifier.value = prefs.getString('user_profile_image');
  }

  // Alias for backward compatibility with settings_screen and main.dart
  static Future<void> loadProfile() async => await init();

  static Future<void> setName(String newName) async {
    nameNotifier.value = newName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_full_name', newName);
    await prefs.setString('user_custom_name', newName);
  }

  static Future<void> setImagePath(String? newPath) async {
    imagePathNotifier.value = newPath;
    final prefs = await SharedPreferences.getInstance();
    if (newPath == null || newPath.isEmpty) {
      await prefs.remove('user_profile_image');
    } else {
      await prefs.setString('user_profile_image', newPath);
    }
  }

  // Alias for backward compatibility
  static Future<void> clearImage() async => await setImagePath(null);
}
