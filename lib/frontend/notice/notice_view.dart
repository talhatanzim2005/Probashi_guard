import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import 'controllers/notice_controller.dart';
import 'models/notice_model.dart';
import '../../widget/ink_surface.dart';

/// The Notices tab: the full feed as rich cards.
///
/// Tapping a card here opens the article in the browser. The home slider shows
/// the same notices as plain text and deliberately does not open links — it
/// sends the person here instead.
class NoticeView extends StatefulWidget {
  final NoticeController? controller;

  const NoticeView({super.key, this.controller});

  @override
  State<NoticeView> createState() => _NoticeViewState();
}

class _NoticeViewState extends State<NoticeView> {
  NoticeController get _controller =>
      widget.controller ?? NoticeController.instance;

  /// True for compact half-height side-by-side cards, false for full 16:9 banner cards.
  bool _isCompactView = true;

  @override
  void initState() {
    super.initState();
    // The home slider usually loaded the feed already; this covers arriving
    // at the tab directly.
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.loadOnce());
  }

  Future<void> _openArticle(NoticeModel notice) async {
    final uri = Uri.tryParse(notice.sourceUrl);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('[NoticeView] could not open ${notice.sourceUrl}: $e');
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).couldNotOpenLink),
          backgroundColor: AppColors.crimsonRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            return RefreshIndicator(
              onRefresh: _controller.refresh,
              color: AppColors.royalBlue,
              backgroundColor: AppColors.cloudDancer,
              child: CustomScrollView(
                // Always scrollable, so pull-to-refresh works on an empty feed.
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.officialNotices,
                                  style: const TextStyle(
                                    color: AppColors.royalBlue,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.latestNews,
                                  style: const TextStyle(
                                    color: AppColors.inkMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildViewToggle(s),
                        ],
                      ),
                    ),
                  ),
                  _buildBody(s),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildViewToggle(AppStrings s) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.royalBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.20),
          width: 1.1,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleOption(
            icon: Icons.view_headline_rounded,
            label: s.viewCompact,
            selected: _isCompactView,
            onTap: () {
              if (!_isCompactView) {
                setState(() => _isCompactView = true);
              }
            },
          ),
          _toggleOption(
            icon: Icons.view_agenda_rounded,
            label: s.viewExpanded,
            selected: !_isCompactView,
            onTap: () {
              if (_isCompactView) {
                setState(() => _isCompactView = false);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _toggleOption({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? AppColors.royalBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: selected ? AppColors.cloudDancer : AppColors.royalBlue,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.cloudDancer : AppColors.royalBlue,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppStrings s) {
    if (_controller.isLoading && _controller.notices.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.royalBlue),
        ),
      );
    }

    if (_controller.notices.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyFeed(
          message: _controller.error ?? s.noNoticesYet,
          isError: _controller.error != null,
          onRetry: _controller.refresh,
          retryLabel: s.tryAgain,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      sliver: SliverList.separated(
        itemCount: _controller.notices.length,
        separatorBuilder: (_, _) => SizedBox(height: _isCompactView ? 10 : 14),
        itemBuilder: (context, index) => _NoticeCard(
          notice: _controller.notices[index],
          onTap: () => _openArticle(_controller.notices[index]),
          isCompact: _isCompactView,
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final NoticeModel notice;
  final VoidCallback onTap;
  final bool isCompact;

  const _NoticeCard({
    required this.notice,
    required this.onTap,
    this.isCompact = true,
  });

  @override
  Widget build(BuildContext context) {
    return isCompact
        ? _CompactNoticeCard(notice: notice, onTap: onTap)
        : _ExpandedNoticeCard(notice: notice, onTap: onTap);
  }
}

class _CompactNoticeCard extends StatelessWidget {
  final NoticeModel notice;
  final VoidCallback onTap;

  const _CompactNoticeCard({required this.notice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.royalBlue.withValues(alpha: 0.14),
              width: 1.1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Source + date
                    Row(
                      children: [
                        const Icon(
                          Icons.public_rounded,
                          size: 12,
                          color: AppColors.royalBlue,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            notice.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.royalBlue,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (notice.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        notice.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          s.readFullStory,
                          style: const TextStyle(
                            color: AppColors.royalBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 11,
                          color: AppColors.royalBlue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (notice.hasImage) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _Thumbnail(
                    url: notice.imageUrl!,
                    width: 88,
                    height: 88,
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

class _ExpandedNoticeCard extends StatelessWidget {
  final NoticeModel notice;
  final VoidCallback onTap;

  const _ExpandedNoticeCard({required this.notice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.royalBlue.withValues(alpha: 0.14),
              width: 1.1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notice.hasImage) _Thumbnail(url: notice.imageUrl!),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source + date
                    Row(
                      children: [
                        const Icon(
                          Icons.public_rounded,
                          size: 13,
                          color: AppColors.royalBlue,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            notice.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.royalBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      notice.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    if (notice.description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        notice.description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          s.readFullStory,
                          style: const TextStyle(
                            color: AppColors.royalBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 13,
                          color: AppColors.royalBlue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;

  const _Thumbnail({required this.url, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final imageWidget = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: AppColors.royalBlue.withValues(alpha: 0.06),
      ),
      // A dead image must not leave a broken box above the headline.
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: AppColors.royalBlue.withValues(alpha: 0.06),
        child: Icon(
          Icons.newspaper_rounded,
          size: (height != null && height! < 100) ? 22 : 30,
          color: AppColors.royalBlue.withValues(alpha: 0.35),
        ),
      ),
    );

    if (width != null && height != null) {
      return SizedBox(width: width, height: height, child: imageWidget);
    }

    return AspectRatio(aspectRatio: 16 / 9, child: imageWidget);
  }
}

class _EmptyFeed extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback onRetry;
  final String retryLabel;

  const _EmptyFeed({
    required this.message,
    required this.isError,
    required this.onRetry,
    required this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isError ? Icons.cloud_off_rounded : Icons.campaign_outlined,
            size: 46,
            color: AppColors.royalBlue.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.royalBlue,
              side: BorderSide(
                color: AppColors.royalBlue.withValues(alpha: 0.4),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              retryLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
