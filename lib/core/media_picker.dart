import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../features/admin/data/cms_models.dart';

/// Pemilih gambar untuk CMS. Unggahan tetap lewat `AdminRepository`
/// (`uploadMedia` / `replaceSchoolPhoto`); kelas ini hanya mengambil berkasnya.
abstract interface class MediaPicker {
  /// Membuka pemilih gambar; null bila pengguna membatalkan.
  Future<PickedImage?> pick();
}

class DeviceMediaPicker implements MediaPicker {
  DeviceMediaPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedImage?> pick() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
    if (file == null) return null;
    return PickedImage(name: file.name, bytes: await file.readAsBytes());
  }
}

final mediaPickerProvider = Provider<MediaPicker>((ref) => DeviceMediaPicker());
