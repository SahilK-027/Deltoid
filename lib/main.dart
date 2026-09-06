import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/failure.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Nothing used to catch anything.
  //
  // Between them these two cover the ways a failure reaches the top without a
  // handler: `FlutterError.onError` takes what the framework catches inside
  // build, layout and gesture callbacks, and `PlatformDispatcher.onError` takes
  // what an async gap drops — a repository call awaited inside an `onTap` that
  // throws, which is most of the writes in this app. Uncaught, the second kind
  // is *entirely* invisible: the handler that was running simply stops, so the
  // visible symptom is a button that does nothing at all.
  //
  // Both still do what they did before as well. `presentError` keeps the red
  // screen and the console trace in debug, and returning false from the
  // platform handler leaves the error to the runtime rather than swallowing it.
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    presentError?.call(details);
    reportFailure(
      details.exception,
      details.stack ?? StackTrace.current,
      what: 'Part of this screen could not be drawn.',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportFailure(error, stack, what: 'That change was not saved.');
    return false;
  };

  // Edge-to-edge, declared before the first frame. Flutter owns this from Dart
  // — setting it only on the Android side is not enough — and without it the
  // window's geometry settles some time after boot rather than before it, so
  // the first layout of the shell measured a top inset of zero and the header
  // band stopped short of the status bar until a tab switch rebuilt it.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The bars draw over the app's own colours, so neither gets a scrim.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: DeltoidApp()));
}
