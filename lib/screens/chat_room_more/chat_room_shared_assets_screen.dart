import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../services/chat_asset_service.dart';
import '../../services/local_preferences_service.dart';
import 'poll_bubble.dart';

class ChatRoomSharedAssetsScreen extends StatefulWidget {
  final String roomId;
  final String? refGroupId;

  const ChatRoomSharedAssetsScreen({
    super.key,
    required this.roomId,
    this.refGroupId,
  });

  @override
  State<ChatRoomSharedAssetsScreen> createState() =>
      _ChatRoomSharedAssetsScreenState();
}

class _ChatRoomSharedAssetsScreenState extends State<ChatRoomSharedAssetsScreen> {
  static const _tabTypes = ['recent', 'media', 'file', 'link', 'poll', 'starred'];
  int _initialTabIndex = 0;
  bool _ready = false;
  TabController? _tabController;

  String get _tabPrefKey => 'pref.shared_assets_tab.${widget.roomId}';

  @override
  void initState() {
    super.initState();
    _loadInitialTab();
  }

  Future<void> _loadInitialTab() async {
    final saved = await LocalPreferencesService.getInt(_tabPrefKey);
    if (!mounted) return;
    setState(() {
      _initialTabIndex =
          saved != null && saved >= 0 && saved < _tabTypes.length ? saved : 0;
      _ready = true;
    });
  }

  Future<void> _saveTabIndex(int index) async {
    await LocalPreferencesService.setInt(_tabPrefKey, index);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: Text(l.sharedVault)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: _tabTypes.length,
      initialIndex: _initialTabIndex,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          if (_tabController != controller) {
            _tabController = controller;
            controller.addListener(() {
              if (!controller.indexIsChanging) {
                _saveTabIndex(controller.index);
              }
            });
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(l.sharedVault),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .doc(widget.roomId)
                      .snapshots(),
                  builder: (context, snap) {
                    final counts = snap.data?.data()?['asset_counts']
                            as Map<String, dynamic>? ??
                        const {};
                    final imageCount = counts['image'] as int? ?? 0;
                    final videoCount = counts['video'] as int? ?? 0;
                    final fileCount = counts['file'] as int? ?? 0;
                    final audioCount = counts['audio'] as int? ?? 0;
                    final linkCount = counts['link'] as int? ?? 0;
                    final pollCount = counts['poll'] as int? ?? 0;
                    final recentCount = imageCount +
                        videoCount +
                        fileCount +
                        audioCount +
                        linkCount +
                        pollCount;

                    return TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                      tabs: [
                        _CountTab(label: l.sharedRecent, count: recentCount),
                        _CountTab(
                          label: l.sharedMedia,
                          count: imageCount + videoCount,
                        ),
                        _CountTab(
                          label: l.sharedFiles,
                          count: fileCount + audioCount,
                        ),
                        _CountTab(label: l.sharedLinks, count: linkCount),
                        _CountTab(label: l.sharedPolls, count: pollCount),
                        _CountTab(label: l.sharedStarred),
                      ],
                    );
                  },
                ),
              ),
            ),
            body: TabBarView(
              children: [
                _AssetTabPage(
                  roomId: widget.roomId,
                  refGroupId: widget.refGroupId,
                  queryType: 'recent',
                  emptyLabel: l.sharedVaultEmpty,
                  colorScheme: colorScheme,
                ),
                _AssetTabPage(
                  roomId: widget.roomId,
                  refGroupId: widget.refGroupId,
                  queryType: 'media',
                  emptyLabel: l.sharedMediaEmpty,
                  colorScheme: colorScheme,
                  useGrid: true,
                ),
                _AssetTabPage(
                  roomId: widget.roomId,
                  refGroupId: widget.refGroupId,
                  queryType: 'file',
                  emptyLabel: l.sharedFilesEmpty,
                  colorScheme: colorScheme,
                ),
                _AssetTabPage(
                  roomId: widget.roomId,
                  refGroupId: widget.refGroupId,
                  queryType: 'link',
                  emptyLabel: l.sharedLinksEmpty,
                  colorScheme: colorScheme,
                ),
                _AssetTabPage(
                  roomId: widget.roomId,
                  refGroupId: widget.refGroupId,
                  queryType: 'poll',
                  emptyLabel: l.sharedPollsEmpty,
                  colorScheme: colorScheme,
                ),
                _AssetTabPage(
                  roomId: widget.roomId,
                  refGroupId: widget.refGroupId,
                  queryType: 'starred',
                  emptyLabel: l.sharedStarredEmpty,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CountTab extends StatelessWidget {
  final String label;
  final int? count;

  const _CountTab({
    required this.label,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final suffix = count != null && count! > 0 ? ' $count' : '';
    return Tab(text: '$label$suffix');
  }
}

class _AssetTabPage extends StatefulWidget {
  final String roomId;
  final String? refGroupId;
  final String queryType;
  final String emptyLabel;
  final ColorScheme colorScheme;
  final bool useGrid;

  const _AssetTabPage({
    required this.roomId,
    required this.refGroupId,
    required this.queryType,
    required this.emptyLabel,
    required this.colorScheme,
    this.useGrid = false,
  });

  @override
  State<_AssetTabPage> createState() => _AssetTabPageState();
}

class _AssetTabPageState extends State<_AssetTabPage>
    with AutomaticKeepAliveClientMixin {
  final ChatAssetService _service = ChatAssetService();
  final ScrollController _scrollController = ScrollController();
  final List<ChatAssetRecord> _items = [];

  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _errorText;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        _service.invalidateRoom(widget.roomId);
      }
      final page = await _service.fetchAssets(
        roomId: widget.roomId,
        type: widget.queryType,
        useCache: !forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchAssets(
        roomId: widget.roomId,
        type: widget.queryType,
        startAfter: _cursor,
        useCache: false,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) {
      _loadMore();
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openPoll(String pollId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: PollBubble(
              roomId: widget.roomId,
              pollId: pollId,
              colorScheme: widget.colorScheme,
              refGroupId: widget.refGroupId,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStar(ChatAssetRecord item) async {
    await _service.setStarred(
      roomId: widget.roomId,
      assetId: item.id,
      isStarred: !item.isStarred,
    );
    await _loadInitial(forceRefresh: true);
  }

  Future<void> _showAssetActions(ChatAssetRecord item) async {
    final l = AppLocalizations.of(context);
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: widget.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.chat_bubble_outline, color: widget.colorScheme.primary),
              title: Text(l.sharedGoToMessage),
              onTap: () => Navigator.pop(ctx, 'jump'),
            ),
            ListTile(
              leading: Icon(
                item.isStarred ? Icons.star_outline : Icons.star,
                color: item.isStarred ? widget.colorScheme.onSurface : Colors.amber.shade700,
              ),
              title: Text(item.isStarred ? l.sharedUnstarAction : l.sharedStarAction),
              onTap: () => Navigator.pop(ctx, 'star'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result == 'jump') {
      Navigator.of(context).pop(item.messageId);
      return;
    }
    if (result == 'star') {
      await _toggleStar(item);
    }
  }

  void _onTapAsset(ChatAssetRecord item) {
    switch (item.type) {
      case 'image':
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _AssetImageViewer(url: item.primaryUrl),
          ),
        );
        return;
      case 'video':
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _AssetVideoPlayerScreen(videoUrl: item.primaryUrl),
          ),
        );
        return;
      case 'file':
      case 'audio':
        _openExternal(item.primaryUrl);
        return;
      case 'link':
        _openExternal(item.linkUrl);
        return;
      case 'poll':
        _openPoll(item.pollId);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorText != null) {
      return _ErrorState(
        colorScheme: widget.colorScheme,
        onRetry: () => _loadInitial(forceRefresh: true),
      );
    }

    if (_items.isEmpty) {
      return _EmptyState(
        label: widget.emptyLabel,
        colorScheme: widget.colorScheme,
      );
    }

    if (widget.useGrid) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final item = _items[index];
          return _MediaGridTile(
            item: item,
            colorScheme: widget.colorScheme,
            onTap: () => _onTapAsset(item),
            onLongPress: () => _showAssetActions(item),
            onStarToggle: () => _toggleStar(item),
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadInitial(forceRefresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final item = _items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AssetListTile(
              item: item,
              colorScheme: widget.colorScheme,
              labels: _AssetLabels.fromL10n(l),
              onTap: () => _onTapAsset(item),
              onLongPress: () => _showAssetActions(item),
              onJump: () => Navigator.of(context).pop(item.messageId),
              onStarToggle: () => _toggleStar(item),
            ),
          );
        },
      ),
    );
  }
}

class _AssetLabels {
  final String photo;
  final String video;
  final String audio;
  final String file;
  final String link;
  final String poll;
  final String recent;
  final String jump;
  final String star;
  final String unstar;

  const _AssetLabels({
    required this.photo,
    required this.video,
    required this.audio,
    required this.file,
    required this.link,
    required this.poll,
    required this.recent,
    required this.jump,
    required this.star,
    required this.unstar,
  });

  factory _AssetLabels.fromL10n(AppLocalizations l) {
    return _AssetLabels(
      photo: l.attachPhoto,
      video: l.attachVideo,
      audio: l.attachAudio,
      file: l.attachFile,
      link: l.sharedLinks,
      poll: l.poll,
      recent: l.sharedRecent,
      jump: l.sharedGoToMessage,
      star: l.sharedStarAction,
      unstar: l.sharedUnstarAction,
    );
  }
}

class _AssetListTile extends StatelessWidget {
  final ChatAssetRecord item;
  final ColorScheme colorScheme;
  final _AssetLabels labels;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onJump;
  final VoidCallback onStarToggle;

  const _AssetListTile({
    required this.item,
    required this.colorScheme,
    required this.labels,
    required this.onTap,
    required this.onLongPress,
    required this.onJump,
    required this.onStarToggle,
  });

  String _dateText() {
    final date = item.createdAt?.toDate();
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}.$month.$day';
  }

  IconData _icon() {
    switch (item.type) {
      case 'video':
        return Icons.play_circle_outline;
      case 'audio':
        return Icons.mic_none_outlined;
      case 'file':
        return Icons.insert_drive_file_outlined;
      case 'link':
        return Icons.link_outlined;
      case 'poll':
        return Icons.poll_outlined;
      default:
        return Icons.image_outlined;
    }
  }

  String _title() {
    switch (item.type) {
      case 'image':
        return labels.photo;
      case 'video':
        return labels.video;
      case 'audio':
        return item.fileName.isNotEmpty ? item.fileName : labels.audio;
      case 'file':
        return item.fileName.isNotEmpty ? item.fileName : labels.file;
      case 'link':
        return item.linkUrl;
      case 'poll':
        return labels.poll;
      default:
        return labels.recent;
    }
  }

  String _subtitle() {
    switch (item.type) {
      case 'video':
        return item.primaryUrl;
      case 'audio':
      case 'file':
        return _dateText();
      case 'link':
        final uri = Uri.tryParse(item.linkUrl);
        return uri?.host ?? item.linkUrl;
      case 'poll':
        return _dateText();
      default:
        return _dateText();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showThumbnail = item.type == 'image' || item.type == 'video';

    return Material(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (showThumbnail)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CachedNetworkImage(
                          imageUrl: item.thumbUrl.isNotEmpty
                              ? item.thumbUrl
                              : item.primaryUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(_icon(), color: colorScheme.primary),
                          ),
                        ),
                      ),
                      if (item.type == 'video')
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white),
                        ),
                    ],
                  ),
                )
              else
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_icon(), color: colorScheme.onPrimaryContainer),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.62),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: labels.jump,
                onPressed: onJump,
                icon: Icon(
                  Icons.chat_bubble_outline,
                  color: colorScheme.onSurface.withOpacity(0.48),
                ),
              ),
              IconButton(
                tooltip: item.isStarred ? labels.unstar : labels.star,
                onPressed: onStarToggle,
                icon: Icon(
                  item.isStarred ? Icons.star : Icons.star_outline,
                  color: item.isStarred ? Colors.amber.shade700 : colorScheme.onSurface.withOpacity(0.42),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaGridTile extends StatelessWidget {
  final ChatAssetRecord item;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onStarToggle;

  const _MediaGridTile({
    required this.item,
    required this.colorScheme,
    required this.onTap,
    required this.onLongPress,
    required this.onStarToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: item.thumbUrl.isNotEmpty ? item.thumbUrl : item.primaryUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(Icons.broken_image_outlined, color: colorScheme.primary),
              ),
            ),
            if (item.type == 'video')
              Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black.withOpacity(0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onStarToggle,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      item.isStarred ? Icons.star : Icons.star_outline,
                      size: 18,
                      color: item.isStarred ? Colors.amber.shade300 : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _EmptyState({
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 54,
            color: colorScheme.onSurface.withOpacity(0.25),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.55)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final ColorScheme colorScheme;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.colorScheme,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 54,
              color: colorScheme.onSurface.withOpacity(0.25),
            ),
            const SizedBox(height: 14),
            Text(
              l.saveError,
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.72)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(MaterialLocalizations.of(context).refreshIndicatorSemanticLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetImageViewer extends StatelessWidget {
  final String url;

  const _AssetImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white, size: 48),
          ),
        ),
      ),
    );
  }
}

class _AssetVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const _AssetVideoPlayerScreen({required this.videoUrl});

  @override
  State<_AssetVideoPlayerScreen> createState() => _AssetVideoPlayerScreenState();
}

class _AssetVideoPlayerScreenState extends State<_AssetVideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: _initialized
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
              child: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}
