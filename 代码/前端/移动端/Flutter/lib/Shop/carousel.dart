import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../Data/models.dart';
import 'media.dart';

class ShopCarousel extends StatefulWidget {
  const ShopCarousel({
    super.key,
    required this.banners,
    required this.t,
    required this.baseUrl,
    required this.onOpen,
    this.packaged = false,
    this.autoPlayInterval = const Duration(seconds: 5),
  });
  final List<Json> banners;
  final String Function(String) t;
  final String baseUrl;
  final bool packaged;
  final void Function(String) onOpen;
  final Duration autoPlayInterval;
  @override
  State<ShopCarousel> createState() => _ShopCarouselState();
}

class _ShopCarouselState extends State<ShopCarousel>
    with WidgetsBindingObserver {
  late final PageController controller;
  final FocusNode focus = FocusNode(debugLabel: 'Shop carousel');
  ScrollPosition? outerScroll;
  Timer? timer;
  int physicalPage = 0, index = 0;
  bool visible = false,
      foreground = true,
      userPaused = false,
      hovered = false,
      focused = false,
      dragging = false,
      geometryQueued = false;
  List<Json> get entries => widget.banners.isEmpty
      ? [
          {
            'id': 'fallback',
            'title_key': 'bannerGuide',
            'image': 'Assets/Banners/graduation.png',
            'target_url': '',
          },
        ]
      : widget.banners;
  bool get reduced => MediaQuery.disableAnimationsOf(context);
  bool get canAuto =>
      entries.length > 1 &&
      visible &&
      foreground &&
      !reduced &&
      !userPaused &&
      !dragging &&
      TickerMode.valuesOf(context).enabled &&
      !focused &&
      !hovered;
  @override
  void initState() {
    super.initState();
    physicalPage = entries.length * 1000;
    controller = PageController(initialPage: physicalPage);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != outerScroll) {
      outerScroll?.removeListener(_queueGeometry);
      outerScroll = position;
      outerScroll?.addListener(_queueGeometry);
    }
    _queueGeometry();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ShopCarousel old) {
    super.didUpdateWidget(old);
    if (old.banners.length != widget.banners.length) {
      index = index % entries.length;
      physicalPage = entries.length * 1000 + index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          controller.jumpToPage(physicalPage);
        }
      });
    }
    _queueGeometry();
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _syncTimer();
  }

  @override
  void didChangeMetrics() => _queueGeometry();
  void _queueGeometry() {
    if (geometryQueued) return;
    geometryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      geometryQueued = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      final viewport = context
          .findAncestorRenderObjectOfType<RenderAbstractViewport>();
      final RenderBox? viewportBox = viewport is RenderBox
          ? viewport as RenderBox
          : null;
      final screen = Offset.zero & MediaQuery.sizeOf(context);
      final clip = viewportBox != null && viewportBox.hasSize
          ? (viewportBox.localToGlobal(Offset.zero) & viewportBox.size)
                .intersect(screen)
          : screen;
      final next = clip.overlaps(bounds) && !bounds.isEmpty;
      if (next != visible) {
        visible = next;
        _syncTimer();
      }
    });
    // Scroll and metrics callbacks can arrive between frames.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncTimer() {
    if (!mounted || !canAuto) {
      timer?.cancel();
      timer = null;
      return;
    }
    // Parent refreshes must not postpone the next slide indefinitely.
    if (timer?.isActive == true) return;
    timer = Timer(widget.autoPlayInterval, () {
      timer = null;
      if (!mounted || !canAuto) return;
      unawaited(
        _move(physicalPage + 1).whenComplete(() {
          if (mounted) _syncTimer();
        }),
      );
    });
  }

  Future<void> _move(int page) async {
    if (!controller.hasClients || entries.length < 2) return;
    if (reduced) {
      controller.jumpToPage(page);
    } else {
      await controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _manual(int delta) {
    timer?.cancel();
    timer = null;
    unawaited(
      _move(physicalPage + delta).whenComplete(() {
        if (mounted) _syncTimer();
      }),
    );
  }

  void _focusChanged(bool value) {
    setState(() {
      // Mouse/touch interaction must not permanently stop rotation.
      focused =
          value &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
      if (focused) userPaused = true;
    });
    _syncTimer();
  }

  bool _scroll(ScrollNotification note) {
    if (note is ScrollStartNotification && note.dragDetails != null) {
      setState(() {
        dragging = true;
      });
      _syncTimer();
    }
    if (note is ScrollEndNotification) {
      dragging = false;
      _syncTimer();
    }
    return false;
  }

  @override
  void dispose() {
    timer?.cancel();
    outerScroll?.removeListener(_queueGeometry);
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  Widget _card(Json banner, bool compact, ColorScheme colors) {
    final title = banner['title_key'] is String
        ? widget.t(banner['title_key'])
        : '${banner['title'] ?? ''}';
    final target = '${banner['target_url'] ?? ''}';
    final uri = Uri.tryParse(target);
    final valid =
        target.isNotEmpty &&
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !RegExp(r'[\x00-\x20]').hasMatch(target);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: colors.surfaceContainerLowest,
        child: InkWell(
          mouseCursor: valid
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          canRequestFocus: valid,
          onTap: valid ? () => widget.onOpen(target) : null,
          child: Column(
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: ShopMedia(
                    path: '${banner['image'] ?? ''}',
                    baseUrl: widget.baseUrl,
                    packaged: widget.packaged,
                    brandSize: compact ? 80 : 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 15 : 19,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (valid)
                      Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: colors.onSurface,
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final compact = c.maxWidth < 600,
          colors = Theme.of(context).colorScheme,
          multiple = entries.length > 1;
      final height = (c.maxWidth / 2.57).clamp(120.0, 260.0) + 56;
      final content = SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: multiple
                  ? NotificationListener<ScrollNotification>(
                      onNotification: _scroll,
                      child: ScrollConfiguration(
                        behavior: const MaterialScrollBehavior().copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                            PointerDeviceKind.invertedStylus,
                          },
                        ),
                        child: PageView.builder(
                          key: const ValueKey('shop-banner-pages'),
                          controller: controller,
                          onPageChanged: (page) {
                            setState(() {
                              physicalPage = page;
                              index = page % entries.length;
                            });
                          },
                          itemBuilder: (context, page) => ExcludeFocus(
                            excluding: page != physicalPage,
                            child: ExcludeSemantics(
                              excluding: page != physicalPage,
                              child: _card(
                                entries[page % entries.length],
                                compact,
                                colors,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : _card(entries.single, compact, colors),
            ),
            if (multiple)
              Positioned(
                right: 18,
                bottom: 68,
                child: Material(
                  color: colors.surface.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(24),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      for (var item = 0; item < entries.length; item++)
                        Semantics(
                          selected: item == index,
                          child: IconButton(
                            key: ValueKey('carousel-indicator-$item'),
                            tooltip: '${widget.t('banners')} ${item + 1}',
                            onPressed: () => _manual(item - index),
                            iconSize: 12,
                            color: colors.primary,
                            icon: Icon(
                              item == index
                                  ? Icons.circle
                                  : Icons.radio_button_unchecked,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      if (!multiple) return content;
      return MouseRegion(
        onEnter: (_) {
          hovered = true;
          _syncTimer();
        },
        onExit: (_) {
          hovered = false;
          _syncTimer();
        },
        child: Focus(
          key: const ValueKey('shop-carousel-focus'),
          focusNode: focus,
          onFocusChange: _focusChanged,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _manual(-1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _manual(1);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: content,
        ),
      );
    },
  );
}
