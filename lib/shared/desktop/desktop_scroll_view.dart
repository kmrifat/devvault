import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_theme.dart';

/// A vertical scroll area that shows when it scrolls: while its content is
/// taller than the room it has, the kit's scroll bar stays visible (macOS
/// otherwise hides it until you scroll), and an edge where content is cut
/// off gets a cue. Shorter content looks like a plain column.
///
/// The cue is a hairline, as under a macOS sheet's or window's fixed
/// header (a [DesktopSheet]'s content); with [fadeInto], the content fades
/// into that colour instead (a box inside a sheet).
class DesktopScrollView extends StatefulWidget {
  const DesktopScrollView({
    super.key,
    required this.child,
    this.padding,
    this.fadeInto,
  });

  final Widget child;

  /// Inside the scrolled area, so content scrolls through it up to the
  /// edges.
  final EdgeInsetsGeometry? padding;

  /// The background the content fades into at a cut edge. Null draws a
  /// hairline there instead.
  final Color? fadeInto;

  @override
  State<DesktopScrollView> createState() => _DesktopScrollViewState();
}

class _DesktopScrollViewState extends State<DesktopScrollView> {
  /// How far content fades out at a cut edge.
  static const double _fade = 14;

  final _controller = ScrollController();

  /// Whether content is out of view above and below.
  var _cut = (top: false, bottom: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Follows this view's own scrolling and size changes, not those of
  /// scroll views inside it.
  bool _onNotification(Notification notification) {
    final metrics = switch (notification) {
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      ScrollNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics == null || !metrics.hasContentDimensions) return false;
    final cut = (
      top: metrics.extentBefore > 0.5,
      bottom: metrics.extentAfter > 0.5,
    );
    if (cut == _cut) return false;
    // Not in the middle of a layout (a jump while laying out).
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cut = cut);
      });
    } else {
      setState(() => _cut = cut);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    // The kit's bar below replaces the default one; scroll views inside
    // keep theirs.
    final view = ScrollConfiguration(
      behavior: behavior.copyWith(scrollbars: false),
      child: NotificationListener<Notification>(
        onNotification: _onNotification,
        child: SingleChildScrollView(
          controller: _controller,
          padding: widget.padding,
          child: ScrollConfiguration(behavior: behavior, child: widget.child),
        ),
      ),
    );
    final stack = Stack(
      children: [
        view,
        if (_cut.top) _edge(context, top: true),
        if (_cut.bottom) _edge(context, top: false),
      ],
    );
    // Shown whenever the content scrolls: a bar only paints when there is
    // something to scroll.
    return switch (context.desktopKit) {
      DesktopKit.macos => mac.MacosScrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: stack,
      ),
      DesktopKit.fluent => fl.Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: stack,
      ),
      DesktopKit.yaru => Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: stack,
      ),
    };
  }

  /// The cue on a cut edge: a fade into [DesktopScrollView.fadeInto], or a
  /// hairline.
  Widget _edge(BuildContext context, {required bool top}) {
    final fadeInto = widget.fadeInto;
    final Widget cue = fadeInto == null
        ? SizedBox(
            height: 0.5,
            child: ColoredBox(color: context.desktopColors.innerSeparator),
          )
        : SizedBox(
            height: _fade,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                  end: top ? Alignment.bottomCenter : Alignment.topCenter,
                  colors: [fadeInto, fadeInto.withValues(alpha: 0)],
                ),
              ),
            ),
          );
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(child: cue),
    );
  }
}
