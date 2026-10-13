import 'package:flutter/material.dart';

/// App-wide messenger so a SnackBar can still be shown after the widget that
/// triggered it (e.g. a page popped after deleting its last file) is gone.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppMessage(String text) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Closes the route hosting [context], even when it is not the top-most one.
void closeRouteOf(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null) return;
  if (route.isCurrent) {
    Navigator.of(context).pop();
  } else if (route.isActive) {
    Navigator.of(context).removeRoute(route);
  }
}
