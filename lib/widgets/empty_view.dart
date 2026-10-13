import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'glass.dart';

class EmptyView extends StatelessWidget {
  const EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassMessage(
      icon: Icons.library_music_rounded,
      message: AppLocalizations.of(context).noAudioFiles,
    );
  }
}

/// Centered glass card with an icon bubble, a message and an optional action.
class GlassMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool error;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const GlassMessage({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = error ? cs.error : cs.primary;
    const radius = BorderRadius.all(Radius.circular(24));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassSurface(
          borderRadius: const BorderRadius.all(Radius.circular(30)),
          blur: 0,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: error
                        ? [cs.error, cs.error.withValues(alpha: 0.7)]
                        : [cs.primary, cs.tertiary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, size: 36, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                GlassSurface(
                  borderRadius: radius,
                  blur: 0,
                  shadow: false,
                  tint: cs.primary.withValues(alpha: 0.85),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: radius,
                      onTap: onAction,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (actionIcon != null) ...[
                              Icon(actionIcon, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              actionLabel!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
