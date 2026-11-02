import 'package:flutter/foundation.dart';

import '../../../models/app_models.dart';

enum WebRole {
  ortu('ortu'),
  admin('admin');

  const WebRole(this.apiValue);
  final String apiValue;
}

@immutable
class WebAuthResult {
  const WebAuthResult({required this.token, required this.user});

  final String token;
  final AuthUser user;
}
