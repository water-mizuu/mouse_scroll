// ignore_for_file: avoid_types_on_closure_parameters, omit_local_variable_types, discarded_futures

import "dart:math" as math;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class MouseScroll extends StatefulWidget {
  const MouseScroll({
    required this.builder,
    this.controller,
    super.key,
    this.mobilePhysics = kMobilePhysics,
    this.duration = const Duration(milliseconds: 380),
    this.scrollSpeed = 1.0,
    this.animationCurve = Curves.easeOutQuart,
  });
  final ScrollController? controller;
  final ScrollPhysics mobilePhysics;
  final Duration duration;
  final double scrollSpeed;
  final Curve animationCurve;
  final Widget Function(BuildContext, ScrollController, ScrollPhysics) builder;

  @override
  State<MouseScroll> createState() => _MouseScrollState();
}

class _MouseScrollState extends State<MouseScroll> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();

    scrollController = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.controller case null) {
      scrollController.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScrollState>(
      create: (BuildContext context) => ScrollState(widget.mobilePhysics, scrollController, widget.duration),
      builder: (BuildContext context, _) {
        ScrollState scrollState = context.read<ScrollState>();
        ScrollController controller = scrollState.controller;
        var (ScrollPhysics physics, _) = context.select((ScrollState s) => (s.activePhysics, s.updateState));

        scrollState.handlePipelinedScroll?.call();
        return Listener(
          onPointerSignal: (PointerSignalEvent signalEvent) {
            scrollState.handleDesktopScroll(signalEvent, widget.scrollSpeed, widget.animationCurve);
          },
          onPointerDown: (PointerDownEvent pointerEvent) {
            scrollState.handleTouchScroll(pointerEvent);
          },
          child: widget.builder(context, controller, physics),
        );
      },
    );
  }
}

const BouncingScrollPhysics kMobilePhysics = BouncingScrollPhysics();
const NeverScrollableScrollPhysics kDesktopPhysics = NeverScrollableScrollPhysics();

class ScrollState with ChangeNotifier {
  ScrollState(this.mobilePhysics, this.controller, this.duration);

  final ScrollPhysics mobilePhysics;
  final ScrollController controller;
  final Duration duration;

  late ScrollPhysics activePhysics = mobilePhysics;
  double _futurePosition = 0;
  bool updateState = false;

  bool _previousDeltaIsPositive = false;
  double? _lastLock;

  Future<void>? _animationEnd;

  /// Scroll that is pipelined to be handled after the current render is finished.
  /// This is used to ensure that the scroll is handled while transitioning from physics.
  void Function()? handlePipelinedScroll;

  static double calcMaxDelta(ScrollController controller, double delta) {
    double pixels = controller.position.pixels;

    return delta.sign > 0
        ? math.min(pixels + delta, controller.position.maxScrollExtent) - pixels
        : math.max(pixels + delta, controller.position.minScrollExtent) - pixels;
  }

  void handleDesktopScroll(
    PointerSignalEvent event,
    double scrollSpeed,
    Curve animationCurve, {
    bool shouldReadLastDirection = true,
  }) {
    // Ensure desktop physics is being used.
    if (activePhysics == kMobilePhysics || _lastLock != null) {
      if (_lastLock != null) {
        updateState = !updateState;
      }
      if (event case PointerScrollEvent()) {
        double pixels = controller.position.pixels;

        /// If the scroll is at the top or bottom, don't allow the user to scroll further.
        if (pixels <= controller.position.minScrollExtent && event.scrollDelta.dy < 0 ||
            pixels >= controller.position.maxScrollExtent && event.scrollDelta.dy > 0) {
          return;
        } else {
          activePhysics = kDesktopPhysics;
        }

        double computedDelta = calcMaxDelta(controller, event.scrollDelta.dy);
        bool isOutOfBounds = pixels < controller.position.minScrollExtent || //
            pixels > controller.position.maxScrollExtent;

        if (!isOutOfBounds) {
          controller.jumpTo(_lastLock ?? (pixels - computedDelta));
        }
        double deltaDifference = computedDelta - event.scrollDelta.dy;
        handlePipelinedScroll = () {
          handlePipelinedScroll = null;
          double currentPos = controller.position.pixels;
          double currentDelta = event.scrollDelta.dy;
          bool shouldLock = _lastLock != null
              ? (_lastLock == currentPos)
              : (pixels != currentPos + deltaDifference &&
                  (currentPos != controller.position.maxScrollExtent || currentDelta < 0) &&
                  (currentPos != controller.position.minScrollExtent || currentDelta > 0));

          if (!isOutOfBounds && shouldLock) {
            controller.jumpTo(pixels);
            _lastLock = pixels;
            controller.position.moveTo(pixels).whenComplete(() {
              if (activePhysics == kDesktopPhysics) {
                activePhysics = kMobilePhysics;
                notifyListeners();
              }
            });
            return;
          } else {
            if (_lastLock != null || isOutOfBounds) {
              double jumpTarget = _lastLock != null //
                  ? pixels
                  : (currentPos - calcMaxDelta(controller, currentDelta));

              controller.jumpTo(jumpTarget);
            }
            _lastLock = null;
            handleDesktopScroll(event, scrollSpeed, animationCurve, shouldReadLastDirection: false);
          }
        };
        notifyListeners();
      }
    } else if (event case PointerScrollEvent()) {
      bool currentDeltaPositive = event.scrollDelta.dy > 0;
      if (shouldReadLastDirection && currentDeltaPositive == _previousDeltaIsPositive) {
        _futurePosition += event.scrollDelta.dy * scrollSpeed;
      } else {
        _futurePosition = controller.position.pixels + event.scrollDelta.dy * scrollSpeed;
      }
      _previousDeltaIsPositive = currentDeltaPositive;

      Future<void> animationEnd = _animationEnd = controller.animateTo(
        _futurePosition,
        duration: duration,
        curve: animationCurve,
      );
      animationEnd.whenComplete(() {
        if (animationEnd == _animationEnd && activePhysics == kDesktopPhysics) {
          activePhysics = mobilePhysics;
          notifyListeners();
        }
      });
    }
  }

  void handleTouchScroll(PointerDownEvent event) {
    if (activePhysics == kDesktopPhysics) {
      activePhysics = mobilePhysics;
      notifyListeners();
    }
  }
}

/// Combination of [SingleChildScrollView] and [MouseScroll].
/// Note: Property [physics] is ignored.
class MouseSingleChildScrollView extends StatelessWidget {
  const MouseSingleChildScrollView({
    super.key,

    /// SingleScrollView properties
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.controller,
    this.child,
    this.dragStartBehavior = DragStartBehavior.start,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,

    /// MouseScroll properties
    this.mobilePhysics = kMobilePhysics,
    this.duration = const Duration(milliseconds: 380),
    this.scrollSpeed = 1.0,
    this.animationCurve = Curves.easeOutQuart,
  });

  /// {@macro flutter.widgets.scroll_view.scrollDirection}
  final Axis scrollDirection;

  /// Whether the scroll view scrolls in the reading direction.
  ///
  /// For example, if the reading direction is left-to-right and
  /// [scrollDirection] is [Axis.horizontal], then the scroll view scrolls from
  /// left to right when [reverse] is false and from right to left when
  /// [reverse] is true.
  ///
  /// Similarly, if [scrollDirection] is [Axis.vertical], then the scroll view
  /// scrolls from top to bottom when [reverse] is false and from bottom to top
  /// when [reverse] is true.
  ///
  /// Defaults to false.
  final bool reverse;

  /// The amount of space by which to inset the child.
  final EdgeInsetsGeometry? padding;

  /// An object that can be used to control the position to which this scroll
  /// view is scrolled.
  ///
  /// Must be null if [primary] is true.
  ///
  /// A [ScrollController] serves several purposes. It can be used to control
  /// the initial scroll position (see [ScrollController.initialScrollOffset]).
  /// It can be used to control whether the scroll view should automatically
  /// save and restore its scroll position in the [PageStorage] (see
  /// [ScrollController.keepScrollOffset]). It can be used to read the current
  /// scroll position (see [ScrollController.offset]), or change it (see
  /// [ScrollController.animateTo]).
  final ScrollController? controller;

  /// {@macro flutter.widgets.scroll_view.primary}
  final bool? primary;

  /// How the scroll view should respond to user input.
  ///
  /// For example, determines how the scroll view continues to animate after the
  /// user stops dragging the scroll view.
  ///
  /// Defaults to matching platform conventions.
  final ScrollPhysics? physics;

  /// The widget that scrolls.
  ///
  /// {@macro flutter.widgets.ProxyWidget.child}
  final Widget? child;

  /// {@macro flutter.widgets.scrollable.dragStartBehavior}
  final DragStartBehavior dragStartBehavior;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// {@macro flutter.widgets.scrollable.restorationId}
  final String? restorationId;

  /// {@macro flutter.widgets.scroll_view.keyboardDismissBehavior}
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  final ScrollPhysics mobilePhysics;
  final Duration duration;
  final double scrollSpeed;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    return MouseScroll(
      mobilePhysics: mobilePhysics,
      duration: duration,
      scrollSpeed: scrollSpeed,
      animationCurve: animationCurve,
      controller: controller,
      builder: (BuildContext context, ScrollController controller, ScrollPhysics physics) {
        return SingleChildScrollView(
          scrollDirection: scrollDirection,
          reverse: reverse,
          padding: padding,
          primary: primary,
          physics: this.physics ?? physics,
          controller: controller,
          dragStartBehavior: dragStartBehavior,
          clipBehavior: clipBehavior,
          restorationId: restorationId,
          keyboardDismissBehavior: keyboardDismissBehavior,
          child: child,
        );
      },
    );
  }
}
