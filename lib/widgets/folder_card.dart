import 'dart:io';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../library.dart';
import '../metadata_cache.dart';
import '../utils/format_utils.dart';
import '../utils/song_actions.dart';
import 'glass.dart';
import 'glass_sheet.dart';

enum _FolderAction { delete, share, details }

class FolderCard extends StatelessWidget {
  final String label;
  final String folderPath;

  /// The audio files of this folder shown in the library.
  final List<File> files;
  final VoidCallback onTap;

  const FolderCard({
    super.key,
    required this.label,
    required this.folderPath,
    required this.files,
    required this.onTap,
  });

  List<String> get _paths => files.map((f) => f.path).toList();

  Future<void> _showOptionsSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final action = await showGlassSheet<_FolderAction>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSheetHeader(
            leading: _FolderIcon(colors: [cs.primary, cs.tertiary]),
            title: label,
            subtitle: l10n.filesCount(files.length),
          ),
          GlassQuickActions(
            actions: [
              GlassQuickAction(
                icon: Icons.ios_share_rounded,
                label: l10n.share,
                onTap: () => Navigator.pop(ctx, _FolderAction.share),
              ),
              GlassQuickAction(
                icon: Icons.info_outline_rounded,
                label: l10n.details,
                onTap: () => Navigator.pop(ctx, _FolderAction.details),
              ),
            ],
          ),
          GlassMenuGroup(
            children: [
              GlassMenuItem(
                icon: Icons.delete_outline_rounded,
                label: l10n.delete,
                value: '${files.length}',
                destructive: true,
                onTap: () => Navigator.pop(ctx, _FolderAction.delete),
              ),
            ],
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _FolderAction.delete:
        if (files.isEmpty) {
          // An empty folder created in the app: just remove the folder.
          await Library().removeCreatedFolder(folderPath);
        } else {
          await confirmAndDeleteSongs(context, _paths, folderPath: folderPath);
        }
      case _FolderAction.share:
        await shareSongs(_paths, text: label);
      case _FolderAction.details:
        _showDetails(context);
    }
  }

  void _showDetails(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Future<List<(String, String)>> rows() async {
      final sizes = await Future.wait(
        files.map((f) => MetadataCache().getFileSize(f.path)),
      );
      final totalSize = sizes.fold<int>(0, (sum, s) => sum + (s ?? 0));
      return [
        (l10n.name, label),
        (l10n.files, '${files.length}'),
        if (totalSize > 0) (l10n.size, formatSize(totalSize)),
        (l10n.path, ltrIsolate(folderPath)),
      ];
    }

    showInfoDialog(context, l10n.folderInfo, rows());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1.0 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassTile(
          onTap: onTap,
          onLongPress: () => _showOptionsSheet(context),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _FolderIcon(colors: [cs.primary, cs.tertiary]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${files.length}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderIcon extends StatelessWidget {
  final List<Color> colors;

  const _FolderIcon({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.folder_rounded, size: 26, color: Colors.white),
    );
  }
}
