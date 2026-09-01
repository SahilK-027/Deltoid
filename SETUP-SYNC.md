# Setting up sync

Deltoid's offline build needs nothing but the Flutter SDK. This guide is for
the **full** build, which backs your training up to a server and syncs it
between your own devices.

Everything here runs on infrastructure you own: your Supabase project, your
Google Cloud project. Nothing routes through anyone else's account, and no part
of this connects you to the author's project.

**This is a developer setup.** You will use a terminal, generate a signing key,
and configure two web consoles. Budget an hour the first time. If that is not
appealing, the offline build is a complete training log and needs none of it.

## What you will end up with

| Thing | Where it lives | What needs it |
| --- | --- | --- |
| Project URL | Supabase → Project Settings | `deltoid.env.json` |
| Publishable key | Supabase → Project Settings | `deltoid.env.json` |
| Google **Web** client ID | Google Cloud Console | `deltoid.env.json`, and Supabase |
| Google **Web** client secret | Google Cloud Console | Supabase only. Never the phone |
| Google **Android** client | Google Cloud Console | Nothing reads it; Google matches your app against it |
| Release keystore | Your machine, outside the repo | Signing the APK, and the Android client |

Three of these are compiled into the APK and can be extracted from it by
anyone. That is expected and safe — the security is row-level security keyed to
your account, not key secrecy. See [SYNC § 3](SYNC.md#3-identity). The client
secret is a real secret and stays in Supabase.

---

## 1. Create the Supabase project

1. Sign in at [supabase.com](https://supabase.com) and create a project. Pick a
   region near you; everything else can stay on its defaults.
2. Wait for provisioning to finish, then open **Project Settings → API** and
   copy two values:
   - the **Project URL**, which looks like `https://abcdefgh.supabase.co`
   - the **publishable key**, which starts with `sb_publishable_`

**A free project pauses after seven days with no requests.** On the phone that
looks like sync quietly failing, not like an email. If you use the app daily it
will never happen; if you stop for a week, open the Supabase dashboard to
un-pause it.

## 2. Install the Supabase CLI and push the schema

The database tables, indexes, and security policies all live in this repository
under `supabase/migrations/`. The CLI applies them to your project.

```bash
brew install supabase/tap/supabase     # or see supabase.com/docs/guides/cli
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

The project ref is the subdomain from your project URL — the `abcdefgh` part.
`supabase link` will ask for your database password, which you set when you
created the project.

Verify it worked in the dashboard under **Table Editor**: you should see nine
tables, including `workouts`, `set_logs`, and `exercises`.

## 3. Create a release keystore

Google needs to know which app is asking to sign in, and it identifies your app
by the fingerprint of the key you sign it with. So the key has to exist before
the OAuth setup.

```bash
keytool -genkey -v -keystore ~/deltoid-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias deltoid
```

It will ask for a password and some identifying details. The details do not
matter; the password does — losing it means you can never update an installed
copy of the app again.

Create `android/key.properties` and point the build at the key:

```properties
storeFile=/Users/you/deltoid-release.jks
storePassword=<the password you just chose>
keyAlias=deltoid
keyPassword=<the same password, unless you set a separate one>
```

Use the absolute path. This file is gitignored, and so is the keystore if you
keep it outside the repository — which you should.

Now read both fingerprints. Google needs the release one for the APK you
install, and the debug one so that `flutter run` also works:

```bash
# Release
keytool -list -v -keystore ~/deltoid-release.jks -alias deltoid | grep SHA1

# Debug — the password really is "android"
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android | grep SHA1
```

Keep both `SHA1:` lines to hand.

## 4. Create the Google OAuth clients

1. Go to the [Google Cloud Console](https://console.cloud.google.com) and
   create a project.
2. Open **APIs & Services → OAuth consent screen**. Choose **External**, fill in
   an app name and your own email, and save. While the screen is in *Testing*
   status only accounts you list as test users can sign in — which is a useful
   way to keep it to yourself. Publishing it lets any Google account sign in.
3. Open **APIs & Services → Credentials** and create **two** OAuth client IDs.

   **The Web client** — application type *Web application*. Give it any name.
   No redirect URIs are needed. Save it and copy both the **client ID** and the
   **client secret**.

   **The Android client** — application type *Android*.
   - Package name: `com.deltoid.deltoid`
   - SHA-1: your **release** fingerprint

   Then create a **second Android client**, identical but with your **debug**
   fingerprint. Google allows one fingerprint per client, and you need both:
   the release one for the installed APK, the debug one for `flutter run`. Miss
   the debug one and sign-in works on the phone but fails during development;
   miss the release one and it fails on the build that matters.

Nothing in the app ever reads the Android clients. They exist so Google can
recognise your app and agree to issue it a token — a token whose audience is
the **Web** client, which is the one Supabase checks. That is why the web
client ID is the value the app needs at runtime.

## 5. Connect Google to Supabase

In the Supabase dashboard, open **Authentication → Providers → Google** and
enable it.

- **Client ID**: your Google **Web** client ID
- **Client Secret**: your Google **Web** client secret
- **Authorized Client IDs**: your Google **Web** client ID again

That last field is the one that matters here. Deltoid signs in natively — the
phone gets an ID token from Google and hands it to Supabase — and Supabase will
only accept a token whose audience appears in that list.

## 6. Write the environment file

Back in your checkout:

```bash
cp deltoid.env.example.json deltoid.env.json
```

Fill in the three values:

```json
{
  "SUPABASE_URL": "https://abcdefgh.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "GOOGLE_WEB_CLIENT_ID": "1234567890-abcdef.apps.googleusercontent.com"
}
```

`GOOGLE_WEB_CLIENT_ID` is the **Web** client ID, not either Android one. This
is the single most common mistake in this setup, and the failure it produces is
a sign-in that opens Google's sheet, completes, and is then refused by Supabase.

`deltoid.env.json` is gitignored. Do not commit it — not because the values are
secret, but because a live project reference in a public repository is an
invitation to probe it.

## 7. Build and install

```bash
flutter build apk --release --flavor full --split-per-abi \
  --dart-define-from-file=deltoid.env.json

adb install build/app/outputs/flutter-apk/app-arm64-v8a-full-release.apk
```

Open the app. The welcome screen should now offer **Continue with Google**
alongside **Continue on this phone**. Sign in, then check **Table Editor** in
Supabase — rows should appear within a few seconds of finishing a session.

To run it from your laptop while developing, pass the same flags to
`flutter run`:

```bash
flutter run --flavor full --dart-define-from-file=deltoid.env.json
```

## When it does not work

**The welcome screen shows no Google button.** The build received no
configuration. Check that you passed `--dart-define-from-file` and that all
three values in the file are non-empty.

**"Google couldn't sign you in just now."** Google refused to issue a token,
which is almost always a fingerprint mismatch. Confirm the SHA-1 on your
Android client matches the key you actually signed with, and that the package
name is `com.deltoid.deltoid` exactly. Note that the offline flavour is
`com.deltoid.deltoid.offline` and will never sign in by design.

**"Your account couldn't be reached."** Supabase rejected a token that Google
issued happily. Either the web client ID is missing from **Authorized Client
IDs**, or the app was built with an Android client ID instead of the web one.

**Sign-in works but nothing appears in the tables.** Check that `supabase db
push` actually ran — an empty **Table Editor** means the schema was never
applied.

**Sync worked and then stopped for no reason.** Check whether the project has
paused. Free projects do that after seven days of inactivity.

## What this costs

Nothing, for one person. A free Supabase project and a free Google Cloud
project cover this comfortably: a decade of training is a few tens of megabytes
of rows, and the app syncs in small batches rather than holding a connection
open.

Be aware that if you share a build configured against *your* project, anyone
who installs it can sign in and create an account on it. Row-level security
keeps their data and yours completely separate, but the project, its quota, and
the responsibility for their data are all still yours. Share the offline build
instead — see [The two builds](README.md#the-two-builds).
