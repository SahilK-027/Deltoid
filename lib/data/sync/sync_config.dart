/// Where the account lives, and which app is asking.
///
/// Passed at build time rather than committed:
///
/// ```bash
/// flutter run --dart-define-from-file=deltoid.env.json
/// ```
///
/// **None of these three is a secret.** All of them ship inside the APK and
/// come out of it with a zip tool, which is the whole reason the security is
/// RLS keyed to `auth.uid()` rather than a key nobody is supposed to have — see
/// [SYNC.md § 3](SYNC.md#3-identity). They are kept out of the tree because a
/// live project reference in a public repo is an invitation to probe it, not
/// because finding one would grant anything.
///
/// The two that *are* secrets — the Google client secret and the `service_role`
/// key — appear nowhere in this repository and never reach the phone. The first
/// lives in Supabase's dashboard; the second bypasses RLS entirely and the app
/// has no use for it.
class SyncConfig {
  const SyncConfig({
    required this.url,
    required this.publishableKey,
    required this.googleWebClientId,
  });

  /// What the build was given. Empty strings when it was given nothing.
  static const fromEnvironment = SyncConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );

  final String url;

  /// What [SYNC.md § 3](SYNC.md#3-identity) calls the anon key. Supabase renamed
  /// it: `sb_publishable_…` replaces the old JWT, and is revocable without
  /// rotating the project's signing secret. Same role, same non-secrecy.
  final String publishableKey;

  /// The **Web** client id, not either Android one.
  ///
  /// Google issues the ID token to the APK by matching its package name and
  /// signing fingerprint against an *Android* client, and then stamps the
  /// token's audience with the **Web** client — which is what Supabase checks.
  /// So the Android client ids exist and never appear in code, and this one
  /// appears in code and is never registered against a fingerprint.
  final String googleWebClientId;

  /// Whether this build can reach an account at all.
  ///
  /// A build with no defines is a working app that cannot sync, never a broken
  /// one: every screen reads local disk and no read waits on a server
  /// ([SYNC.md § 15](SYNC.md#15-what-sync-may-never-do) rule 1). `flutter test`
  /// runs in exactly that state, and so does anyone who clones this repo.
  bool get isConfigured =>
      url.isNotEmpty &&
      publishableKey.isNotEmpty &&
      googleWebClientId.isNotEmpty;
}
