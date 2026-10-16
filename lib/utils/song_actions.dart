import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../audio_manager.dart';
import '../device_utils.dart';
import '../l10n/app_localizations.dart';
import '../library.dart';
import '../metadata_cache.dart';
import '../pages/player_page.dart';
import '../smooth_page_route.dart';
import '../widgets/cover_art.dart';
import '../widgets/glass.dart';
import '../widgets/glass_sheet.dart';
import 'app_messenger.dart';
import 'format_utils.dart';
import 'layout.dart';

/// Shared song actions (options sheet, delete, ringtone, share, details,
/// play) used by every list and by the player screen.

enum _SongAction { delete, ringtone, share, details, move }

bool _openingPlayer = false;

void openPlayerPage(BuildContext context) {
  Navigator.push(context, SmoothPageRoute(builder: (_) => const PlayerPage()));
}

/// Plays `files[index]` (queueing its folder) and opens the player. Tapping
/// the track that is already loaded just opens the player. In the wide layout
/// it only plays, since the player panel is already visible.
Future<void> playAndOpenPlayer(
  BuildContext context,
  List<File> files,
  int index,
) async {
  if (_openingPlayer || index < 0 || index >= files.length) return;
  _openingPlayer = true;
  try {
    final manager = AudioManager();
    final wide = isWideLayout(context);
    if (manager.currentPath.value != files[index].path) {
      final ok = await manager.playFiles(files, index);
      if (!ok) return;
    } else if (wide) {
      // The player is already on screen next to the list: just resume.
      await manager.resume();
    }
    // In the wide layout the player panel is always visible.
    if (!wide && context.mounted) openPlayerPage(context);
  } finally {
    _openingPlayer = false;
  }
}

Future<void> showSongOptions(BuildContext context, String path) async {
  final l10n = AppLocalizations.of(context);
  final info = MetadataCache().peek(path);
  final subtitle = [
    if (info != null && info.artist.isNotEmpty) info.artist,
    if (info?.duration != null) formatDuration(info!.duration),
  ].join(' • ');
  final action = await showGlassSheet<_SongAction>(
    context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSheetHeader(
          leading: CoverArt(path: path, size: 52, borderRadius: 12),
          title: formatName(path),
          subtitle: subtitle,
        ),
        GlassQuickActions(
          actions: [
            GlassQuickAction(
              icon: Icons.ios_share_rounded,
              label: l10n.share,
              onTap: () => Navigator.pop(ctx, _SongAction.share),
            ),
            if (Platform.isAndroid)
              GlassQuickAction(
                icon: Icons.ring_volume_rounded,
                label: l10n.ringtone,
                onTap: () => Navigator.pop(ctx, _SongAction.ringtone),
              ),
            GlassQuickAction(
              icon: Icons.drive_file_move_outline,
              label: l10n.move,
              onTap: () => Navigator.pop(ctx, _SongAction.move),
            ),
            GlassQuickAction(
              icon: Icons.info_outline_rounded,
              label: l10n.details,
              onTap: () => Navigator.pop(ctx, _SongAction.details),
            ),
          ],
        ),
        GlassMenuGroup(
          children: [
            GlassMenuItem(
              icon: Icons.delete_outline_rounded,
              label: l10n.delete,
              destructive: true,
              onTap: () => Navigator.pop(ctx, _SongAction.delete),
            ),
          ],
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _SongAction.delete:
      await confirmAndDeleteSongs(context, [path]);
    case _SongAction.ringtone:
      await setAsRingtone(context, path);
    case _SongAction.share:
      await shareSongs([path]);
    case _SongAction.move:
      await moveSongsToFolder(context, [path]);
    case _SongAction.details:
      showSongDetails(context, path);
  }
}

/// Asks for confirmation, deletes [paths] and notifies the whole app.
/// Pass [folderPath] when deleting a folder's contents.
Future<bool> confirmAndDeleteSongs(
  BuildContext context,
  List<String> paths, {
  String? folderPath,
}) async {
  if (paths.isEmpty) return false;
  final l10n = AppLocalizations.of(context);
  final isFolder = folderPath != null;
  final single = !isFolder && paths.length == 1;
  // On macOS files go to the Trash (recoverable); elsewhere it is permanent.
  final trash = Platform.isMacOS;

  final String title;
  final String message;
  if (isFolder) {
    title = l10n.deleteFolder;
    message = trash
        ? l10n.moveFolderToTrashMsg(ltrIsolate(folderPath), paths.length)
        : l10n.deleteFolderMsg(ltrIsolate(folderPath), paths.length);
  } else if (single) {
    title = l10n.deleteFile;
    message = trash
        ? l10n.moveToTrashMsg(ltrIsolate(paths.first))
        : l10n.deleteFileMsg(ltrIsolate(paths.first));
  } else {
    title = l10n.deleteFiles(paths.length);
    message = trash
        ? l10n.moveFilesToTrashMsg(paths.length)
        : l10n.deleteFilesMsg(paths.length);
  }

  final ok = await showGlassDialog<bool>(
    context,
    builder: (ctx) => GlassDialogContent(
      icon: Icons.delete_outline_rounded,
      destructive: true,
      title: title,
      message: message,
      actions: [
        GlassDialogAction(
          label: l10n.cancel,
          onTap: () => Navigator.pop(ctx, false),
        ),
        GlassDialogAction(
          label: trash ? l10n.moveToTrash : l10n.delete,
          destructive: true,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (ok != true) return false;

  final result = await DeviceUtils.deleteFiles(paths);
  final deleted = result.deleted;
  AudioManager().onFilesDeleted(deleted);
  // The user tapped "Deny" in Android's own confirmation: nothing to report.
  if (result.cancelled && deleted.isEmpty) return false;

  final failed = paths.length - deleted.length;
  if (deleted.isEmpty) {
    showAppMessage(l10n.failedDelete);
  } else if (failed > 0) {
    showAppMessage(l10n.filesDeletedPartial(deleted.length, failed));
  } else if (trash) {
    showAppMessage(
      paths.length == 1
          ? l10n.movedToTrash
          : l10n.filesMovedToTrash(deleted.length),
    );
  } else {
    showAppMessage(
      paths.length == 1 ? l10n.fileDeleted : l10n.filesDeleted(deleted.length),
    );
  }
  return deleted.isNotEmpty;
}

Future<void> setAsRingtone(BuildContext context, String path) async {
  final l10n = AppLocalizations.of(context);
  final result = await DeviceUtils.setRingtone(path);
  showAppMessage(switch (result) {
    RingtoneResult.success => l10n.ringtoneSuccess,
    RingtoneResult.permissionRequired => l10n.ringtonePermission,
    RingtoneResult.failed => l10n.ringtoneFailed,
  });
}

Future<void> shareSongs(List<String> paths, {String? text}) async {
  if (paths.isEmpty) return;
  try {
    await Share.shareXFiles(
      paths.map((p) => XFile(p)).toList(),
      text: text ?? (paths.length == 1 ? formatName(paths.first) : null),
    );
  } catch (_) {}
}

String _formatDate(BuildContext context, DateTime date) {
  try {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMd(locale).add_jm().format(date);
  } catch (_) {
    return date.toLocal().toString().split('.').first;
  }
}

void showSongDetails(BuildContext context, String path) {
  final l10n = AppLocalizations.of(context);
  Future<List<(String, String)>> rows() async {
    final info = await MetadataCache().getMetadataInfo(path);
    DateTime? modified;
    try {
      modified = await File(path).lastModified();
    } catch (_) {}
    return [
      (l10n.name, formatName(path)),
      if (info.artist.isNotEmpty) (l10n.artist, info.artist),
      if (info.duration != null) (l10n.duration, formatDuration(info.duration)),
      if (info.fileSize != null) (l10n.size, formatSize(info.fileSize!)),
      if (modified != null && context.mounted)
        (l10n.modified, _formatDate(context, modified)),
      (l10n.path, ltrIsolate(path)),
    ];
  }

  showInfoDialog(context, l10n.fileInfo, rows());
}

/// Dialog listing label/value pairs that are computed asynchronously.
void showInfoDialog(
  BuildContext context,
  String title,
  Future<List<(String, String)>> rows,
) {
  final l10n = AppLocalizations.of(context);
  showGlassDialog<void>(
    context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return GlassDialogContent(
        icon: Icons.info_outline_rounded,
        title: title,
        body: FutureBuilder<List<(String, String)>>(
          future: rows,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
              ),
              child: SingleChildScrollView(
                child: GlassMenuGroup(
                  children: [
                    for (final (label, value) in snap.data!)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              value,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          GlassDialogAction(
            label: l10n.close,
            primary: true,
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      );
    },
  );
}

/// Asks for a new folder name and creates it under the music folder.
/// Returns the new folder's path, or null if cancelled / failed.
Future<String?> showNewFolderDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  String? error;

  final name = await showGlassDialog<String>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final cs = Theme.of(ctx).colorScheme;
        void submit() {
          final value = controller.text.trim();
          if (!Library.isValidFolderName(value)) {
            setDialogState(() => error = l10n.invalidFolderName);
          } else if (Library.folderExists(value)) {
            setDialogState(() => error = l10n.folderAlreadyExists);
          } else {
            Navigator.pop(ctx, value);
          }
        }

        return GlassDialogContent(
          icon: Icons.create_new_folder_outlined,
          title: l10n.newFolder,
          body: GlassSurface(
            blur: 0,
            shadow: false,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              decoration: InputDecoration(
                hintText: l10n.folderName,
                errorText: error,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          actions: [
            GlassDialogAction(
              label: l10n.cancel,
              onTap: () => Navigator.pop(ctx),
            ),
            GlassDialogAction(label: l10n.create, primary: true, onTap: submit),
          ],
        );
      },
    ),
  );
  controller.dispose();
  if (name == null) return null;

  final path = await Library().createFolder(name);
  showAppMessage(path != null ? l10n.folderCreated : l10n.folderCreateFailed);
  return path;
}

const _kNewFolderChoice = '\u0000new-folder';

/// Lets the user pick (or create) a folder and moves [paths] into it.
/// Returns true if anything moved.
Future<bool> moveSongsToFolder(BuildContext context, List<String> paths) async {
  if (paths.isEmpty) return false;
  final l10n = AppLocalizations.of(context);
  final sources = paths.map((p) => File(p).parent.path).toSet();
  final folders = [
    for (final f in Library().allFolders)
      // Hide the folder the songs are already in.
      if (!(sources.length == 1 && sources.contains(f))) f,
  ];

  var target = await showGlassSheet<String>(
    context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSheetTitle(l10n.moveToFolder),
        GlassMenuGroup(
          children: [
            GlassMenuItem(
              icon: Icons.create_new_folder_outlined,
              label: l10n.newFolder,
              active: true,
              onTap: () => Navigator.pop(ctx, _kNewFolderChoice),
            ),
          ],
        ),
        if (folders.isNotEmpty)
          GlassMenuGroup(
            children: [
              for (final f in folders)
                GlassMenuItem(
                  icon: Icons.folder_rounded,
                  label: f.split('/').last,
                  onTap: () => Navigator.pop(ctx, f),
                ),
            ],
          ),
      ],
    ),
  );
  if (target == null || !context.mounted) return false;
  if (target == _kNewFolderChoice) {
    target = await showNewFolderDialog(context);
    if (target == null) return false;
  }

  final result = await DeviceUtils.moveFiles(paths, target);
  // The user tapped "Deny" in Android's own confirmation: nothing to report.
  if (result.cancelled && result.moved.isEmpty) return false;
  AudioManager().onFilesMoved(result.moved);

  final folderName = target.split('/').last;
  final moved = result.moved.length;
  final failed = paths.length - moved;
  if (moved == 0) {
    showAppMessage(l10n.moveFailed);
  } else if (failed > 0) {
    showAppMessage(
      '${l10n.filesMoved(moved, folderName)} — ${l10n.moveFailed} ($failed)',
    );
  } else {
    showAppMessage(
      moved == 1
          ? l10n.fileMoved(folderName)
          : l10n.filesMoved(moved, folderName),
    );
  }
  return moved > 0;
}
