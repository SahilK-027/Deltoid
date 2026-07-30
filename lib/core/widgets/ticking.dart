import 'dart:async';

import 'package:flutter/material.dart';

/// Rebuilds its child once a second, and nothing else with it.
///
/// The log screen used to hold one `Timer.periodic` that called `setState` on
/// the entire screen — PageView included — whether or not anything on it was
/// showing a clock. Two things need the time of day; they can pay for it
/// themselves.
class Ticking extends StatefulWidget {
  const Ticking({
    super.key,
    required this.builder,
    this.interval = const Duration(seconds: 1),
  });

  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
