import 'package:file_picker/file_picker.dart';

/// Abstract service wrapping file picking capabilities for production and testability.
abstract class FilePickerService {
  Future<PlatformFile?> pickFile({List<String>? allowedExtensions});
}

/// Default production implementation using [FilePicker.platform].
class DefaultFilePickerService implements FilePickerService {
  const DefaultFilePickerService();

  @override
  Future<PlatformFile?> pickFile({List<String>? allowedExtensions}) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null && allowedExtensions.isNotEmpty
          ? FileType.custom
          : FileType.any,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    return result.files.first;
  }
}
