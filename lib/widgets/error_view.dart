import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'empty_view.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GlassMessage(
      icon: Icons.folder_off_rounded,
      error: true,
      message: message,
      actionLabel: AppLocalizations.of(context).retry,
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
    );
  }
}
