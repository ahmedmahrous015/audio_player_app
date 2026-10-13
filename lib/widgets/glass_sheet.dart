import 'package:flutter/material.dart';
import 'glass.dart';

/// Floating frosted-glass bottom sheet, detached from the screen edges like
/// the latest iOS sheets.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.25),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: GlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(34)),
            blur: 40,
            tint: cs.surface.withValues(alpha: dark ? 0.62 : 0.78),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    builder(ctx),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Artwork/icon + title + subtitle at the top of a sheet.
class GlassSheetHeader extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;

  const GlassSheetHeader({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered sheet title (for pickers such as speed or sleep timer).
class GlassSheetTitle extends StatelessWidget {
  final String text;

  const GlassSheetTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class GlassQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const GlassQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Row of equal-width icon tiles for the most common actions.
class GlassQuickActions extends StatelessWidget {
  final List<GlassQuickAction> actions;

  const GlassQuickActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(18));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GlassSurface(
                blur: 0,
                shadow: false,
                borderRadius: radius,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: a.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(a.icon, color: cs.primary, size: 24),
                          const SizedBox(height: 6),
                          Text(
                            a.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// iOS-style grouped list: rows inside one rounded glass panel, separated by
/// hairlines.
class GlassMenuGroup extends StatelessWidget {
  final List<Widget> children;

  const GlassMenuGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassSurface(
        blur: 0,
        shadow: false,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 56,
                    color: cs.onSurface.withValues(alpha: 0.10),
                  ),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GlassMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Current value shown at the trailing edge (e.g. "1.5x").
  final String? value;
  final bool destructive;
  final bool checked;

  /// Highlights the icon with the accent (e.g. an enabled toggle).
  final bool active;
  final VoidCallback onTap;

  const GlassMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.destructive = false,
    this.checked = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    final iconColor = destructive
        ? cs.error
        : (active || checked ? cs.primary : cs.onSurfaceVariant);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withValues(alpha: 0.14),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            if (checked) Icon(Icons.check_rounded, color: cs.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Centered frosted-glass dialog that scales in, replacing [AlertDialog].
Future<T?> showGlassDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.3),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassSurface(
                borderRadius: const BorderRadius.all(Radius.circular(30)),
                blur: 40,
                tint: cs.surface.withValues(alpha: dark ? 0.62 : 0.80),
                child: Material(
                  type: MaterialType.transparency,
                  child: builder(ctx),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 1.08, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class GlassDialogAction {
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool primary;

  const GlassDialogAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.primary = false,
  });
}

/// Icon, title, message/body and capsule buttons for [showGlassDialog].
class GlassDialogContent extends StatelessWidget {
  final IconData? icon;
  final bool destructive;
  final String title;
  final String? message;
  final Widget? body;
  final List<GlassDialogAction> actions;

  const GlassDialogContent({
    super.key,
    this.icon,
    this.destructive = false,
    required this.title,
    this.message,
    this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = destructive ? cs.error : cs.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null)
            Center(
              child: Container(
                width: 52,
                height: 52,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
            ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (body != null)
            Padding(padding: const EdgeInsets.only(top: 14), child: body),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final (i, a) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _GlassDialogButton(action: a)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassDialogButton extends StatelessWidget {
  final GlassDialogAction action;

  const _GlassDialogButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = action.destructive || action.primary;
    final color = action.destructive ? cs.error : cs.primary;
    const radius = BorderRadius.all(Radius.circular(22));
    return GlassSurface(
      blur: 0,
      shadow: false,
      borderRadius: radius,
      tint: filled ? color.withValues(alpha: 0.85) : null,
      height: 46,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: action.onTap,
          child: Center(
            child: Text(
              action.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
