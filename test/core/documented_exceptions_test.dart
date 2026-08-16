import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **An exception to a documented rule is a change to the document.**
///
/// The failure this catches is individually reasonable every time it happens: a
/// comment states a global rule, notes that this code breaks it, explains why,
/// and that is the whole approval process. THEME is never told. The rule stays
/// written down as absolute while the code accumulates exceptions, and the next
/// person to read THEME believes something about the app that stopped being
/// true months ago.
///
/// `hold_pad.dart` is how it is done right: it runs its clock over the type cap
/// and says *"the one place in the app that goes over it — see THEME → Type"*,
/// and THEME → Type says the same thing from the other side. Two documents, one
/// fact, neither surprising.
///
/// So: a comment that invokes THEME or RULES and then claims an exception has
/// to say *where* the exception is written — `THEME → Type`, `RULES § 4` — not
/// merely that a document exists. This cannot check that the section really
/// grants it; that is a reading, not a test. What it does stop is a comment
/// being the only place an exception is recorded.
void main() {
  test('every comment claiming an exception cites the document', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('.g.dart'))) {
      for (final block in _commentBlocks(file.readAsStringSync())) {
        if (!_citesADocument(block.text)) continue;
        if (!_claimsAnException(block.text)) continue;
        if (_namesTheSection(block.text)) continue;
        offenders.add('${file.path}:${block.line} — ${_firstLine(block.text)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'a comment cannot grant itself an exception to a documented '
          'rule. Write the exception into THEME.md or RULES.md and point at '
          'the section that grants it — "THEME → Type", "RULES § 4" — or stop '
          'taking it:\n${offenders.join('\n')}',
    );
  });

  test('the reader can tell a claim of exception from ordinary prose', () {
    expect(_claimsAnException('the one place in the app that goes over it'),
        isTrue);
    expect(_claimsAnException('One exception, a clock.'), isTrue);
    expect(_claimsAnException('this is the only place the gap is two pieces'),
        isTrue);
    expect(_claimsAnException('the one field that overrides the theme'), isTrue);

    expect(_claimsAnException('the honest answer is null'), isFalse);
    expect(_claimsAnException('a day with no id behind it'), isFalse);
  });

  test('the reader can tell a pointer from a bare citation', () {
    // How `hold_pad.dart` does it, which is the model § 8 names.
    expect(
      _namesTheSection('the one place in the app that goes over it — see '
          'THEME → Type'),
      isTrue,
    );
    expect(_namesTheSection('nothing inside the log may claim a horizontal '
        'gesture (RULES § 4)'), isTrue);

    // A rule cited but not located: the reader of THEME has nowhere to go and
    // no way to know the exception was ever written down.
    expect(_namesTheSection('the one field that overrides what THEME says'),
        isFalse);
  });
}

String _firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length <= 96 ? line : '${line.substring(0, 93)}…';
}

/// Whether the comment invokes one of the two documents at all. Only those are
/// held to the rule: a comment about anything else has no document to change.
bool _citesADocument(String text) =>
    RegExp(r'\bTHEME\b|\bRULES\b').hasMatch(text);

/// A citation that says *where*, which is what makes the exception findable
/// from the document's side rather than only from the code's.
bool _namesTheSection(String text) =>
    RegExp(r'THEME\s*(→|->)\s*\w|RULES\s*§').hasMatch(text);

/// The phrasings this codebase actually uses when a comment is about to grant
/// itself an exception. Deliberately a small list of idioms rather than a guess
/// at English: a checker that fires on ordinary prose is one that gets muted.
bool _claimsAnException(String text) {
  final t = text.toLowerCase();
  return RegExp(
    r'\bexception\b'
    r'|\bthe one (place|field|screen|row|list|widget|caller)\b'
    r'|\bthe only place\b'
    r'|\bgoes over\b'
    r'|\boverrides?\b',
  ).hasMatch(t);
}

typedef _Comment = ({int line, String text});

/// Every `//` run and `/* */` block in [source], with `//` lines that follow one
/// another gathered into a single comment — a rule and the exception it takes
/// are usually two lines of the same paragraph.
List<_Comment> _commentBlocks(String source) {
  final blocks = <_Comment>[];
  final lines = source.split('\n');
  var i = 0;
  while (i < lines.length) {
    final trimmed = lines[i].trim();
    if (trimmed.startsWith('//')) {
      final start = i;
      final buffer = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('//')) {
        buffer.add(lines[i].trim().replaceFirst(RegExp(r'^///?'), '').trim());
        i++;
      }
      blocks.add((line: start + 1, text: buffer.join('\n')));
      continue;
    }
    i++;
  }
  return blocks;
}
