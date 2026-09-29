import 'package:flutter/foundation.dart';

class ProfileNotifier {
  static final ValueNotifier<String?> nameNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> imagePathNotifier = ValueNotifier<String?>(null);
}
