import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
