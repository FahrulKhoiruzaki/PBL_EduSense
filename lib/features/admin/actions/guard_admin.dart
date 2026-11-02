import '../../../core/user_facing_error.dart';
import '../../../widgets/app_overlays.dart';

Future<T?> guardAdmin<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on UserFacingError catch (e) {
    AppToast.show(e.message);
    return null;
  }
}
