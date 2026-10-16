/// The letters in More's profile circle.
///
/// The first letters of the first and last words of the name, so
/// `Ada Lovelace` and `Ada King Lovelace` both read `AL`. A one-word name
/// gives one letter, and with no name the first letter of the email stands in.
/// Upper-cased, since a sign-in that gives `ada lovelace` still names a person.
///
/// Empty only when there is neither a name nor an email, and the circle then
/// shows nothing rather than a placeholder letter nobody chose.
library;

String initialsOf({String? name, String? email}) {
  final words = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return _first(email?.trim() ?? '');
  if (words.length == 1) return _first(words.single);
  return '${_first(words.first)}${_first(words.last)}';
}

/// The first character, counted in runes so a name that starts outside the
/// basic plane is not cut in half.
String _first(String s) =>
    s.isEmpty ? '' : String.fromCharCode(s.runes.first).toUpperCase();
