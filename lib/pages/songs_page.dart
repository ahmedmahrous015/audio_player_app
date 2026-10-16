import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../audio_manager.dart';
import '../audio_scanner.dart';
import '../library.dart';
import '../metadata_cache.dart';
import '../smooth_page_route.dart';
import '../l10n/app_localizations.dart';
import '../utils/format_utils.dart';
import '../utils/layout.dart';
import '../utils/song_actions.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_card.dart';
import '../widgets/folder_card.dart';
import '../widgets/glass.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/error_view.dart';
import '../widgets/empty_view.dart';
import 'folder_songs_page.dart';
import 'player_page.dart';

enum SortMode { dateNewest, dateOldest, nameAZ, nameZA }

class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> with WidgetsBindingObserver {
  static const _kSortMode = 'sort_mode';
  static const _autoRefreshInterval = Duration(seconds: 60);

  /// Every file, newest first (the scan/cache order).
  List<File> _allFiles = [];

  /// [_allFiles] in the user's chosen sort order.
  List<File> _sortedFiles = [];
  Map<String, List<File>> _groupedFiles = {};
  List<String> _folderKeys = [];
  SortMode _sortMode = SortMode.dateNewest;

  bool _isLoading = true;
  Future<List<File>>? _pendingScan;
  String? _errorMessage;
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollAll = ScrollController();
  final _scrollFolders = ScrollController();
  Timer? _autoRefreshTimer;
  StreamSubscription<Set<String>>? _deletedSub;
  StreamSubscription<Map<String, String>>? _movedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AudioManager().currentPath.addListener(_onTrackChanged);
    _deletedSub = AudioManager().deletedFilesStream.listen(_onFilesDeleted);
    _movedSub = AudioManager().movedFilesStream.listen(_onFilesMoved);
    Library().createdFolders.addListener(_onCreatedFoldersChanged);
    Library().loadCreatedFolders();
    _initData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AudioManager().currentPath.removeListener(_onTrackChanged);
    _autoRefreshTimer?.cancel();
    _deletedSub?.cancel();
    _movedSub?.cancel();
    Library().createdFolders.removeListener(_onCreatedFoldersChanged);
    _searchController.dispose();
    _scrollAll.dispose();
    _scrollFolders.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The user may have just granted access in system Settings.
      if (_errorMessage != null && _allFiles.isEmpty) {
        loadMusicFolder();
      } else {
        _silentRefresh();
      }
      _startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      // No point scanning storage while nobody is looking at the list.
      _autoRefreshTimer?.cancel();
    }
  }

  void _onTrackChanged() {
    if (mounted) setState(() {});
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      _autoRefreshInterval,
      (_) => _silentRefresh(),
    );
  }

  Future<void> _loadSortMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final i = prefs.getInt(_kSortMode);
      if (i != null && i >= 0 && i < SortMode.values.length) {
        _sortMode = SortMode.values[i];
      }
    } catch (_) {}
  }

  void _setSortMode(SortMode mode) {
    if (mode == _sortMode) return;
    setState(() {
      _sortMode = mode;
      _applySort();
    });
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_kSortMode, mode.index))
        .catchError((_) => false);
  }

  /// Load cached audio files immediately on launch for 0ms startup
  Future<void> _initData() async {
    await _loadSortMode();

    if (Platform.isAndroid && !await _ensurePermissions()) {
      if (mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(context).permissionDenied;
          _isLoading = false;
        });
      }
      return;
    }

    final cachedPaths = await MetadataCache().getCachedPaths();
    if (!mounted) return;
    final validFiles = [
      for (final path in cachedPaths ?? const <String>[])
        if (!isExcludedPath(path)) File(path),
    ];
    if (validFiles.isNotEmpty) {
      // Cached paths are already newest-first; avoid blocking disk I/O here.
      setState(() {
        _applyFiles(validFiles, needSort: false);
        _isLoading = false;
      });
      _scheduleRestore(validFiles);

      // Defer background silent refresh so startup and animations are completely fluid
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _silentRefresh();
      });
      return;
    }

    // If cache is empty, load after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) loadMusicFolder();
    });
  }

  void _scheduleRestore(List<File> files) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) AudioManager().restoreLastSession(files);
    });
  }

  /// Replaces the library with [files]; sorts them newest-first unless the
  /// caller guarantees they already are.
  void _applyFiles(List<File> files, {bool needSort = true}) {
    if (needSort) {
      final cache = MetadataCache();
      files.sort(
        (a, b) => cache.getFileModTime(b).compareTo(cache.getFileModTime(a)),
      );
    }
    _allFiles = files;
    final map = <String, List<File>>{};
    for (final f in files) {
      map.putIfAbsent(f.parent.path, () => []).add(f);
    }
    _groupedFiles = map;
    _applySort();
  }

  void _applySort() {
    int byName(File a, File b) => formatName(
      a.path,
    ).toLowerCase().compareTo(formatName(b.path).toLowerCase());
    int byLabel(String a, String b) =>
        _folderLabel(a).toLowerCase().compareTo(_folderLabel(b).toLowerCase());

    // Map keys keep insertion order, i.e. folders ordered by their newest file.
    final folders = _groupedFiles.keys.toList();
    switch (_sortMode) {
      case SortMode.dateNewest:
        _sortedFiles = List.of(_allFiles);
        _folderKeys = folders;
      case SortMode.dateOldest:
        _sortedFiles = _allFiles.reversed.toList();
        _folderKeys = folders.reversed.toList();
      case SortMode.nameAZ:
        _sortedFiles = List.of(_allFiles)..sort(byName);
        _folderKeys = folders..sort(byLabel);
      case SortMode.nameZA:
        _sortedFiles = List.of(_allFiles)..sort((a, b) => byName(b, a));
        _folderKeys = folders..sort((a, b) => byLabel(b, a));
    }
    Library().scannedFolders.value = List.unmodifiable(_folderKeys);
  }

  void _onCreatedFoldersChanged() {
    if (mounted) setState(() {});
  }

  void _onFilesMoved(Map<String, String> moves) {
    if (!mounted) return;
    final updated = [
      for (final f in _allFiles)
        moves.containsKey(f.path) ? File(moves[f.path]!) : f,
    ];
    _selected.removeAll(moves.keys);
    setState(() => _applyFiles(updated, needSort: false));
    MetadataCache().saveCachedPaths(updated.map((f) => f.path).toList());
  }

  /// Library folders plus empty folders created in the app, all in the
  /// chosen sort order (an empty folder sorts by its own date, since it has
  /// no newest file).
  List<String> get _allFolderKeys {
    final empty = [
      for (final f in Library().createdFolders.value)
        if (!_groupedFiles.containsKey(f)) f,
    ];
    if (empty.isEmpty) return _folderKeys;

    final keys = [..._folderKeys, ...empty];
    int byLabel(String a, String b) =>
        _folderLabel(a).toLowerCase().compareTo(_folderLabel(b).toLowerCase());
    final cache = MetadataCache();
    DateTime folderDate(String folder) {
      final files = _groupedFiles[folder];
      // Groups keep the library's newest-first order, so [0] is the newest.
      if (files != null && files.isNotEmpty) {
        return cache.getFileModTime(files.first);
      }
      try {
        return Directory(folder).statSync().modified;
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    switch (_sortMode) {
      case SortMode.dateNewest:
        keys.sort((a, b) => folderDate(b).compareTo(folderDate(a)));
      case SortMode.dateOldest:
        keys.sort((a, b) => folderDate(a).compareTo(folderDate(b)));
      case SortMode.nameAZ:
        keys.sort(byLabel);
      case SortMode.nameZA:
        keys.sort((a, b) => byLabel(b, a));
    }
    return keys;
  }

  Future<void> _moveSelected() async {
    final moved = await moveSongsToFolder(context, _selected.toList());
    if (moved && mounted) _clearSelection();
  }

  void _onFilesDeleted(Set<String> paths) {
    if (!mounted) return;
    _selected.removeAll(paths);
    final remaining = _allFiles.where((f) => !paths.contains(f.path)).toList();
    if (remaining.length == _allFiles.length) return;
    setState(() => _applyFiles(remaining, needSort: false));
    MetadataCache().saveCachedPaths(remaining.map((f) => f.path).toList());
  }

  /// Shares one in-flight storage scan between every caller, so a refresh
  /// triggered while another scan runs waits for it instead of being dropped.
  Future<List<File>> _scan() =>
      _pendingScan ??= findAudioFiles().whenComplete(() {
        _pendingScan = null;
      });

  /// Scans for new files without showing loading indicator if items exist.
  Future<void> _silentRefresh() async {
    if (!mounted || _errorMessage != null) return;
    try {
      final files = await _scan();
      if (!mounted) return;
      final newPaths = files.map((f) => f.path).toSet();
      final oldPaths = _allFiles.map((f) => f.path).toSet();
      final changed = !setEquals(newPaths, oldPaths);
      if (changed || _isLoading) {
        setState(() {
          if (changed) _applyFiles(files);
          _isLoading = false;
        });
      }
      if (changed) {
        MetadataCache().saveCachedPaths(files.map((f) => f.path).toList());
      }
    } catch (_) {}
  }

  Future<void> loadMusicFolder() async {
    setState(() => _errorMessage = null);

    try {
      if (Platform.isAndroid && !await _ensurePermissions()) {
        if (mounted) {
          setState(
            () => _errorMessage = AppLocalizations.of(context).permissionDenied,
          );
        }
        return;
      }

      final files = await _scan();
      if (!mounted) return;
      setState(() => _applyFiles(files));
      MetadataCache().saveCachedPaths(files.map((f) => f.path).toList());
      _scheduleRestore(files);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() => _errorMessage = l10n.errorLoading(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _hasFileAccess() async =>
      await Permission.audio.isGranted ||
      await Permission.storage.isGranted ||
      await Permission.manageExternalStorage.isGranted;

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _requestPermissions();
    } catch (_) {
      // e.g. another permission request is already in flight.
      return _hasFileAccess();
    }
  }

  Future<bool> _requestPermissions() async {
    if (await _hasFileAccess()) {
      // Notifications are only needed for the media controls; ask, but never
      // block the library on them. Android stops asking after two denials.
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      return true;
    }

    final statuses = await [
      Permission.audio,
      Permission.storage,
      Permission.notification,
    ].request();
    return (statuses[Permission.audio]?.isGranted ?? false) ||
        (statuses[Permission.storage]?.isGranted ?? false);
  }

  /// Retry from the error view: ask again, and if the system no longer shows
  /// the dialog, send the user to the app's settings page.
  Future<void> _onRetry() async {
    if (Platform.isAndroid && !await _ensurePermissions()) {
      await openAppSettings();
      return;
    }
    await loadMusicFolder();
  }

  String _folderLabel(String path) {
    final parts = path.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }

  void _openFolder(String key) {
    final files = _groupedFiles[key] ?? const <File>[];
    Navigator.push(
      context,
      SmoothPageRoute(
        builder: (_) => FolderSongsPage(
          folderLabel: _folderLabel(key),
          folderPath: key,
          files: files,
        ),
      ),
    );
  }

  // ---- Multi-select (long-press a song) ----
  final Set<String> _selected = {};

  /// Files currently listed in the "All songs" tab (after search/sort), used
  /// by "select all".
  List<File> _visibleFiles = const [];

  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _toggleSelectAll() {
    final visible = _visibleFiles.map((f) => f.path).toSet();
    setState(() {
      if (_selected.containsAll(visible)) {
        _selected.removeAll(visible);
      } else {
        _selected.addAll(visible);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final deleted = await confirmAndDeleteSongs(context, _selected.toList());
    if (deleted && mounted) _clearSelection();
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final wide = isWideLayout(context);
    return PopScope(
      canPop: !_isSearching && !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else if (_isSearching) {
          _closeSearch();
        }
      },
      child: DefaultTabController(
        length: 2,
        // One shared backdrop for the app bar and mini player blurs.
        child: BackdropGroup(
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              toolbarHeight: 64,
              titleSpacing: _selecting ? 4 : 20,
              flexibleSpace: const GlassBarBackground(),
              automaticallyImplyLeading: false,
              leadingWidth: _selecting ? 68 : null,
              leading: _selecting
                  ? Center(
                      child: GlassIconButton(
                        blur: 0,
                        icon: Icons.close_rounded,
                        size: 42,
                        tooltip: l10n.cancelSelection,
                        onPressed: _clearSelection,
                      ),
                    )
                  : null,
              title: _selecting
                  ? Text(
                      l10n.selectedCount(_selected.length),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isSearching
                          ? _SearchField(
                              key: const ValueKey('search'),
                              controller: _searchController,
                              hint: l10n.searchHint,
                              onChanged: (v) =>
                                  setState(() => _searchQuery = v.trim()),
                            )
                          : Text(l10n.myMusic, key: const ValueKey('title')),
                    ),
              actions: _selecting
                  ? _selectionActions(l10n, cs)
                  : [
                      GlassIconButton(
                        blur: 0,
                        icon: _isSearching
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                        size: 42,
                        tooltip: _isSearching
                            ? MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip
                            : l10n.search,
                        onPressed: () {
                          if (_isSearching) {
                            _closeSearch();
                          } else {
                            setState(() => _isSearching = true);
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      _buildSortMenu(l10n),
                      const SizedBox(width: 16),
                    ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _GlassTabs(
                    onTap: (_) {
                      if (_selecting) _clearSelection();
                    },
                    labels: [
                      (Icons.music_note_rounded, l10n.allSongs),
                      (Icons.folder_rounded, l10n.folders),
                    ],
                    primary: cs.primary,
                  ),
                ),
              ),
            ),
            body: GlassScrollWatcher(
              child: Stack(
                children: [
                  const Positioned.fill(child: AmbientBackground()),
                  // Builder: below the Scaffold, MediaQuery's top padding includes
                  // the (transparent) app bar, so content can scroll under it.
                  Builder(
                    builder: (bodyContext) {
                      _topInset = MediaQuery.paddingOf(bodyContext).top;
                      final tabs = TabBarView(
                        physics: _selecting
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        children: [
                          _buildAllSongsTab(context),
                          _buildFoldersTab(context),
                        ],
                      );
                      if (!wide) return tabs;
                      // Wide window: library and player side by side.
                      return Row(
                        children: [
                          Expanded(child: tabs),
                          Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(
                              0,
                              _topInset + 8,
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
                  if (!wide)
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
      ),
    );
  }

  List<Widget> _selectionActions(AppLocalizations l10n, ColorScheme cs) {
    final allSelected =
        _visibleFiles.isNotEmpty &&
        _selected.containsAll(_visibleFiles.map((f) => f.path));
    return [
      GlassIconButton(
        blur: 0,
        icon: allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
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
        icon: Icons.drive_file_move_outline,
        size: 42,
        tooltip: l10n.moveToFolder,
        onPressed: _moveSelected,
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
    ];
  }

  Widget _buildSortMenu(AppLocalizations l10n) {
    final labels = {
      SortMode.dateNewest: l10n.sortDateNewest,
      SortMode.dateOldest: l10n.sortDateOldest,
      SortMode.nameAZ: l10n.sortNameAZ,
      SortMode.nameZA: l10n.sortNameZA,
    };
    return GlassIconButton(
      blur: 0,
      icon: Icons.swap_vert_rounded,
      size: 42,
      tooltip: l10n.sortBy,
      onPressed: () => showGlassSheet<void>(
        context,
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassSheetTitle(l10n.sortBy),
            GlassMenuGroup(
              children: [
                for (final mode in SortMode.values)
                  GlassMenuItem(
                    icon: switch (mode) {
                      SortMode.dateNewest => Icons.schedule_rounded,
                      SortMode.dateOldest => Icons.history_rounded,
                      SortMode.nameAZ => Icons.sort_by_alpha_rounded,
                      SortMode.nameZA => Icons.sort_by_alpha_rounded,
                    },
                    label: labels[mode]!,
                    checked: mode == _sortMode,
                    onTap: () {
                      Navigator.pop(ctx);
                      _setSortMode(mode);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Height of the status bar + glass app bar, set while building the body.
  double _topInset = 0;

  double get _listBottomPadding =>
      (isWideLayout(context) ? 24 : 120) + MediaQuery.paddingOf(context).bottom;

  EdgeInsets get _listPadding =>
      EdgeInsets.fromLTRB(16, _topInset + 8, 16, _listBottomPadding);

  bool _matches(String text) =>
      text.toLowerCase().contains(_searchQuery.toLowerCase());

  /// Wraps a non-scrollable placeholder so pull-to-refresh still works.
  Widget _refreshable(Widget child) {
    return RefreshIndicator(
      onRefresh: loadMusicFolder,
      edgeOffset: _topInset,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildAllSongsTab(BuildContext context) {
    if (_isLoading && _allFiles.isEmpty) return _buildShimmer();

    if (_errorMessage != null && _allFiles.isEmpty) {
      return ErrorView(message: _errorMessage!, onRetry: _onRetry);
    }

    var files = _sortedFiles;
    if (_searchQuery.isNotEmpty) {
      files = files.where((f) {
        final artist = MetadataCache().getCachedArtist(f.path) ?? '';
        return _matches(formatName(f.path)) || _matches(artist);
      }).toList();
    }
    if (files.isEmpty) {
      return _refreshable(
        _searchQuery.isNotEmpty ? _buildNoResults() : const EmptyView(),
      );
    }

    final curPath = AudioManager().currentPath.value;
    _visibleFiles = files;

    return RefreshIndicator(
      onRefresh: loadMusicFolder,
      edgeOffset: _topInset,
      child: ListView.builder(
        controller: _scrollAll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _listPadding,
        itemCount: files.length,
        itemBuilder: (_, i) {
          final file = files[i];
          return SongCard(
            key: ValueKey(file.path),
            name: formatName(file.path),
            filePath: file.path,
            isActive: file.path == curPath,
            selectionMode: _selecting,
            selected: _selected.contains(file.path),
            // Long-press starts (or extends) the selection.
            onLongPress: () => _toggleSelect(file.path),
            // Queue from the full library (not the filtered/sorted view) so
            // the whole folder is available for next/previous.
            onTap: _selecting
                ? () => _toggleSelect(file.path)
                : () => playAndOpenPlayer(
                    context,
                    _allFiles,
                    _allFiles.indexWhere((f) => f.path == file.path),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFoldersTab(BuildContext context) {
    if (_isLoading && _groupedFiles.isEmpty) return _buildShimmer();

    if (_errorMessage != null && _groupedFiles.isEmpty) {
      return ErrorView(message: _errorMessage!, onRetry: _onRetry);
    }

    var keys = _allFolderKeys;
    if (keys.isEmpty) return _refreshable(const EmptyView());
    if (_searchQuery.isNotEmpty) {
      keys = keys.where((k) => _matches(_folderLabel(k))).toList();
      if (keys.isEmpty) return _refreshable(_buildNoResults());
    }

    return RefreshIndicator(
      onRefresh: loadMusicFolder,
      edgeOffset: _topInset,
      child: ListView.builder(
        controller: _scrollFolders,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _listPadding,
        // First row: "New folder" (hidden while searching).
        itemCount: keys.length + (_searchQuery.isEmpty ? 1 : 0),
        itemBuilder: (_, i) {
          if (_searchQuery.isEmpty) {
            if (i == 0) return const _NewFolderTile();
            i -= 1;
          }
          final key = keys[i];
          return FolderCard(
            key: ValueKey(key),
            label: _folderLabel(key),
            folderPath: key,
            files: _groupedFiles[key] ?? const [],
            onTap: () => _openFolder(key),
          );
        },
      ),
    );
  }

  Widget _buildNoResults() {
    return GlassMessage(
      icon: Icons.search_off_rounded,
      message: AppLocalizations.of(context).noResults,
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: _listPadding,
      itemCount: 10,
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GlassSurface(
          blur: 0,
          shadow: false,
          child: const SizedBox(height: 68, width: double.infinity),
        ),
      ),
    );
  }
}

/// Search box shown in place of the title.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: BorderRadius.circular(21),
      blur: 0,
      shadow: false,
      height: 42,
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        style: TextStyle(color: cs.onSurface, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
        ),
      ),
    );
  }
}

/// Segmented, capsule-shaped glass tab switcher.
class _GlassTabs extends StatelessWidget {
  final List<(IconData, String)> labels;
  final Color primary;

  final ValueChanged<int>? onTap;

  const _GlassTabs({required this.labels, required this.primary, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: BorderRadius.circular(22),
      blur: 0,
      padding: const EdgeInsets.all(4),
      child: TabBar(
        onTap: onTap,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        splashBorderRadius: BorderRadius.circular(18),
        // Selected segment is a brighter pane of glass, not a solid fill.
        indicator: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        labelColor: primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontFamily: 'Janna',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        tabs: [
          for (final (icon, text) in labels)
            Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Text(text),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "New folder" row at the top of the folders tab.
class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassTile(
        onTap: () => showNewFolderDialog(context),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.create_new_folder_outlined,
                color: cs.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context).newFolder,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
