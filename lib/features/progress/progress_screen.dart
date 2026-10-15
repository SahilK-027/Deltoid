import 'package:flutter/material.dart';

import '../../core/widgets/primitives.dart';
import '../../core/theme/tokens.dart';
import '../account/backup_mark.dart';

/// Where the training is read rather than entered.
///
/// Cycle progress and Weekly volume move here from Home unchanged
/// (THEME → The destinations). Until they do, the page is its masthead and
/// nothing else: a section with nothing in it hides rather than printing a
/// placeholder (THEME → Empty states).
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          HeaderBand(
            child: PageHeader(
              title: 'Progress',
              // No eyebrow yet. `Cycles and volume` names the cards this page
              // will hold, and printing it over an empty page would describe
              // something that is not there. Without it the title is the first
              // line under the status bar and takes the wider gap.
              topGap: Space.xxl,
              actions: [BackupMark()],
            ),
          ),
        ],
      ),
    );
  }
}
