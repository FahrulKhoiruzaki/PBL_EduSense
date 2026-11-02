import 'package:flutter/material.dart';

import '../data/web_auth_models.dart';
import '../screens/web_login_screen.dart';

void openWebLogin(BuildContext context, WebRole role) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => WebLoginScreen(role: role)),
  );
}
