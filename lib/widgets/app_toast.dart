import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _displayChannel =
    MethodChannel('page.puzzak.gol/display');

/// Shows a native Android toast on Android, or a floating [SnackBar] fallback
/// on Web, desktop, and widget tests.
void showAppToast(
  BuildContext context,
  String message, {
  bool long = false,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_showAndroidToast(context, message, long));
    return;
  }
  _showSnackBarFallback(context, message, long: long);
}

Future<void> _showAndroidToast(
  BuildContext context,
  String message,
  bool long,
) async {
  try {
    await _displayChannel.invokeMethod<void>(
      'showToast',
      <String, dynamic>{
        'message': message,
        'long': long,
      },
    );
  } on MissingPluginException {
    if (context.mounted) {
      _showSnackBarFallback(context, message, long: long);
    }
  } on PlatformException {
    if (context.mounted) {
      _showSnackBarFallback(context, message, long: long);
    }
  }
}

void _showSnackBarFallback(
  BuildContext context,
  String message, {
  required bool long,
}) {
  if (!context.mounted) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration:
            long ? const Duration(seconds: 4) : const Duration(seconds: 2),
      ),
    );
}
