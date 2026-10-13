import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../audio_manager.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_messenger.dart';
import '../utils/format_utils.dart';
import '../utils/layout.dart';
import '../utils/song_actions.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_card.dart';
import 'player_page.dart';

/// Approximate height of one [SongCard] row, used to scroll to the current track.
const double _kSongRowExtent = 76;

class FolderSongsPage extends StatefulWidget {
  final String folderLabel;
  final List<File> files;

  /// Overrides the default "queue this folder and open the player" tap action.
  final void Function(BuildContext context, List<File> files, int index)?
  onSongTap;
  final bool scrollToCurrent;
  final bool showMiniPlayer;

  const FolderSongsPage({
    super.key,
    required this.folderLabel,
    required this.files,
    this.onSongTap,
    this.scrollToCurrent = false,
    this.showMiniPlayer = true,
  });

  @override
  State<FolderSongsPage> createState() => _FolderSongsPageState();
}

class _FolderSongsPageState extends State<FolderSongsPage> {
  late List<File> _files;
  final _scrollController = ScrollController();
  StreamSubscription<Set<String>>? _deletedSub;

  @override
  void initState() {
    super.initState();
    _files = _sorted(widget.files);
    _deletedSub = AudioManager().deletedFilesStream.listen(_onFilesDeleted);
    if (widget.scrollToCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void didUpdateWidget(FolderSongsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.files != widget.files) _files = _sorted(widget.files);
  }

  @override
  void dispose() {
    _deletedSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  List<File> _sorted(List<File> files) =>
      List.of(files)
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

  // ---- Multi-select (long-press a song) ----
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _toggleSelectAll() {
    final all = _files.map((f) => f.path).toSet();
    setState(() {
      if (_selected.containsAll(all)) {
        _selected.clear();
      } else {
        _selected.addAll(all);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final deleted = await confirmAndDeleteSongs(context, _selected.toList());
    if (deleted && mounted) _clearSelection();
  }

  void _onFilesDeleted(Set<String> paths) {
    _selected.removeAll(paths);
    if (!mounted) return;
    setState(() => _files.removeWhere((f) => paths.contains(f.path)));
    if (_files.isEmpty) closeRouteOf(context);
  }

  void _scrollToCurrent() {
    final current = AudioManager().currentPath.value;
    final index = _files.indexWhere((f) => f.path == current);
    if (index < 0 || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final offset =
        index * _kSongRowExtent -
        position.viewportDimension / 2 +
        _kSongRowExtent / 2;
    _scrollController.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
  }

  void _onTap(int index) {
    final custom = widget.onSongTap;
    if (custom != null) {
      custom(context, _files, index);
    } else {
      playAndOpenPlayer(context, _files, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // The queue opened from the player keeps its single-column layout.
    final wide = isWideLayout(context) && widget.onSongTap == null;
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final allSelected =
        _files.isNotEmpty && _selected.containsAll(_files.map((f) => f.path));
    // One shared backdrop for the app bar and mini player blurs.
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _clearSelection();
      },
      child: BackdropGroup(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            flexibleSpace: const GlassBarBackground(),
            automaticallyImplyLeading: false,
            leadingWidth: 68,
            leading: Center(
              child: _selecting
                  ? GlassIconButton(
                      blur: 0,
                      icon: Icons.close_rounded,
                      size: 42,
                      tooltip: l10n.cancelSelection,
                      onPressed: _clearSelection,
                    )
                  : GlassIconButton(
                      blur: 0,
                      icon: Icons.arrow_back_ios_new_rounded,
                      size: 42,
                      iconSize: 20,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () => Navigator.maybePop(context),
                    ),
            ),
            titleSpacing: 4,
            actions: _selecting
                ? [
                    GlassIconButton(
                      blur: 0,
                      icon: allSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 42,
                      tooltip: allSelected ? l10n.deselectAll : l10n.selectAll,
                      onPressed: _toggleSelectAll,
                    ),
                    const SizedBox(width: 10),
                    GlassIconButton(
                      blur: 0,
                      icon: Icons.ios_share_rounded,
                      size: 42,
                      tooltip: l10n.share,
                      onPressed: () => shareSongs(_selected.toList()),
                    ),
                    const SizedBox(width: 10),
                    GlassIconButton(
                      blur: 0,
                      icon: Icons.delete_outline_rounded,
                      size: 42,
                      tooltip: l10n.deleteSelected,
                      iconColor: Colors.white,
                      tint: cs.error.withValues(alpha: 0.85),
                      onPressed: _deleteSelected,
                    ),
                    const SizedBox(width: 16),
                  ]
                : null,
            title: Text(
              _selecting
                  ? l10n.selectedCount(_selected.length)
                  : widget.folderLabel,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: GlassScrollWatcher(
            child: Stack(
              children: [
                const Positioned.fill(child: AmbientBackground()),
                Builder(
                  builder: (bodyContext) {
                    final top = MediaQuery.paddingOf(bodyContext).top;
                    final list = ValueListenableBuilder<String?>(
                      valueListenable: AudioManager().currentPath,
                      builder: (context, currentPath, _) => ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          top + 8,
                          16,
                          (widget.showMiniPlayer && !wide ? 120 : 20) +
                              bottomInset,
                        ),
                        itemCount: _files.length,
                        itemBuilder: (_, i) {
                          final file = _files[i];
                          return SongCard(
                            key: ValueKey(file.path),
                            name: formatName(file.path),
                            filePath: file.path,
                            isActive: file.path == currentPath,
                            selectionMode: _selecting,
                            selected: _selected.contains(file.path),
                            onLongPress: () => _toggleSelect(file.path),
                            onTap: _selecting
                                ? () => _toggleSelect(file.path)
                                : () => _onTap(i),
                          );
                        },
                      ),
                    );
                    if (!wide) return list;
                    return Row(
                      children: [
                        Expanded(child: list),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            0,
                            top + 8,
                            16,
                            16,
                          ),
                          child: SizedBox(
                            width: nowPlayingPanelWidth(context),
                            child: const NowPlayingPanel(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (widget.showMiniPlayer && !wide)
                  const Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: SafeArea(top: false, child: MiniPlayer()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
