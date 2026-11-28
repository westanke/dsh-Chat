# dsh-Chat

<p align="center">
  <strong>The DSH chat client on your phone — one Flutter codebase for Android, iOS and HarmonyOS.</strong><br>
  Connect to your own <a href="https://github.com/westanke/dsh-remote-bridge">dsh-remote-bridge</a>;
  chats, sessions and tool calls stay on your machine.
</p>

<p align="center">
  <img src="assets/promo-16x9.en.png" alt="dsh-Chat: new chat, session drawer and settings on Android, iOS and HarmonyOS" width="100%">
</p>

<p align="center">
  <a href="https://gitee.com/westanke/dsh-Chat/releases/tag/v1.0.41"><code>Download v1.0.41 · APK / HAP</code></a>
</p>

<p align="center">
  <a href="./README.md">中文</a> ·
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.41-087f8c">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-2da44e">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20HarmonyOS-586069">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B">
  <a href="https://github.com/westanke/dsh-Chat/actions/workflows/ci.yml"><img
     alt="CI" src="https://github.com/westanke/dsh-Chat/actions/workflows/ci.yml/badge.svg"></a>
</p>

`dsh-Chat` is the Flutter client for [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge).
It reads sessions and history over REST `/api/v1` and receives streaming deltas over WS `/ws/mobile`
(subprotocol `dsh-mobile-v1`, `hello.protocol=3`). This repository only consumes the protocol; the
source of truth lives in the bridge repository's `docs/api/`.

**Who it is for**: people who use DSH as their main tool but do not want to be tied to the desk.
The phone is a display and input surface; chats, workspace and files stay on your own machine. The
bridge listens on loopback by default, so installing a client does not expose the machine by itself.

**Boundary**: this is not a fork of any official client. It does not connect to official servers and
does not reuse their icons, fonts or binaries. Visual measurements follow the official app (see
[`docs/design-tokens.md`](docs/design-tokens.md)), but all branding — launch mark, display name,
bundle id — belongs to this project.

## What it looks like

<p align="center">
  <a href="assets/screenshots/chat.png"><img src="assets/screenshots/chat.png" width="270" alt="New chat: working directory, suggestion cards and the composer"></a>
  <a href="assets/screenshots/sessions.png"><img src="assets/screenshots/sessions.png" width="270" alt="Session drawer: search, groups, running / pending / unread filters and the archived toggle"></a>
  <a href="assets/screenshots/settings.png"><img src="assets/screenshots/settings.png" width="270" alt="Settings: appearance, font scale and work-step detail"></a>
</p>

Left: chat, with Markdown, tool calls, process groups and a “changed N files” card on one timeline.
Middle: the session drawer, with search, date groups, running/waiting/unread filters and the current bridge.
Right: settings, with connection state, device permissions, appearance and notifications; the device id is redacted.

> Screenshots taken on HarmonyOS hardware (API 26). Android and HarmonyOS share the same Flutter UI;
> iOS has the native bridge but has not gone through on-device visual verification yet.

## Features

- **Streaming chat**: renders `chat.message.delta`, reloads history after `committed`, and debounces
  external REST writes.
- **Markdown**: headings, nested lists, task lists, fenced code (Atom One Light, language label,
  copy), full-width tables, quotes, inline/block math and link badges.
- **Tool calls**: official-style three-part titles, parameter summaries, five states kept in
  accessibility text, exit-code badges, and per-tool detail views (Bash command + IO, diffs, read
  windows, search hits, web results, question cards), driven by live frames.
- **Process groups**: consecutive calls collapse into one header with live parameters; four detail
  levels; a turn-end line with duration or failure.
- **Thinking stream**: breathing dot ring, shimmer label and a three-line live window; collapses to a
  one-line summary when the answer starts, expands to Markdown on tap.
- **Changed / generated files**: per-file `+N −M` diffs and generated-file thumbnails at the end of a
  turn, derived locally from `meta.diffs`.
- **Composer**: up to six images, `@` references to workspace files and past sessions, `/` commands,
  a persistent task strip, and per-session drafts that survive session switching.
- **Visible waiting and retries**: typing dots before the first token; an expandable
  “retried model request (1/5)” row when the kernel retries after 504/rate limiting.
- **Endpoint probing on reconnect**: LAN, virtual networks (Tailscale etc.), Cloudflare tunnel and
  direct IPv6 (`http://[<IPv6>]:3090`) can all be candidates; the app probes them and picks the
  fastest reachable one, with the failure reason shown inline. Global-unicast IPv6 counts as public.
- **Device capabilities**: local notifications (done / failed / waiting for approval / waiting for an
  answer), TTS, system sharing, photo picker, file opening and a private app directory. Android also
  supports in-app download/install; iOS and HarmonyOS update through their stores.
- **Dark mode, drawer, failures and reconnects**: system-following palettes, instant search and date
  groups, visible `turn/end` errors, and backoff 1→2→4→8→16s capped at 30s.

## Platform support

| Platform | Status |
|---|---|
| **Android** | **Verified on Android hardware**: pairing, auto-reconnect, streaming, Markdown, tool details, process groups, thinking, question cards, drawer, dark mode and sharing. v1.0.39 APK is 26.8 MB |
| **iOS** | Native bridge covers IANA time zone, private directory, notifications, TTS, sharing, image picker and file opening. CI builds an unsigned IPA. **Not verified on an iPhone**; updates go through the App Store |
| **HarmonyOS** | **Flutter-OH build verified on HarmonyOS hardware / API 26**: pairing, chat, sessions, sharing, TTS, picker and notifications (including tap-to-return) passed. Release distribution needs an AGC certificate/profile |

Current version: `app/pubspec.yaml` is `1.0.41+42`, tag `v1.0.41`.

## Download and install

Latest **v1.0.41** (Gitee primary; GitHub mirrors the same tag):

| Artifact | Size | SHA-256 |
|---|---|---|
| [APK](https://gitee.com/westanke/dsh-Chat/releases/download/v1.0.41/dsh-Chat-v1.0.41.apk) | 27,731,018 bytes | `fe6ac051bf610850f124224b6d2978246dbb98bc0b083104ecb07a6e4f0f737f` |
| [HAP](https://gitee.com/westanke/dsh-Chat/releases/download/v1.0.41/dsh-Chat-v1.0.41-unsigned.hap) | 35,304,836 bytes | `822a8fb66584e0e4a5bbadf20b69fd679ea5827ac0b76aefc98f93f2068a4dd9` (unsigned, for local verification) |

- Android: install the APK directly. Some Android builds show a risk-interception page; confirm and continue.
- HarmonyOS: the HAP must be signed by a certificate the device trusts. For development use
  `scripts/sign-hap.sh`; for distribution use an AGC certificate and profile.
- iOS: no App Store build yet. Build an unsigned IPA from source on macOS or in GitHub Actions.

## First connection

1. Install and enable [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge)
   (requires **≥ 2.10.0**, protocol v3) on the desktop, then open **Phone settings → Remote access**.
2. On the phone, open dsh-Chat and enter the bridge URL, e.g. `http://<host>:3090`
   (IPv6: `http://[<IPv6>]:3090`). On Android you can also run
   `adb reverse tcp:3090 tcp:3090` and use `http://127.0.0.1:3090`.
3. Paste the one-time pairing code and tap **Pair and connect**. Credentials are stored locally and
   the app reconnects automatically afterwards.

## Remote access over IPv6 (optional)

Away from your LAN there are two ways to reach the bridge: the Cloudflare tunnel built into
`dsh-remote-bridge`, or a **direct IPv6 connection**. Most Chinese home broadband has CGNAT-only
IPv4 (no public address), but carriers do hand out IPv6 prefixes; direct is third-party-free and
lower latency.

> The steps below were verified on a China Mobile home line with a Huawei OptiXstar V175 (ONT doing
> PPPoE). Menu names vary by vendor/firmware — see the table. **Only open TCP 3090 and keep the
> ONT's IPv6 firewall enabled**; disabling it exposes every device and port behind the ONT.

### 1. Check that IPv6 works

- Computer: `ip -6 addr show scope global` shows a global address (`2409:`, `2408:`, `240e:`…), and
  `curl -6 -s https://ifconfig.co` echoes it.
- Bridge: change the listen address from the default `0.0.0.0` to `::` (dual-stack on Linux) or to
  the computer's concrete IPv6 address — `0.0.0.0` listens on IPv4 only. The port stays 3090.
- ONT: the INTERNET WAN connection must be **IPv4/IPv6 dual stack**; some regions provision IPv4 only.
- Phone on cellular (Wi-Fi off): `http://[<computer IPv6>]:3090` returning `401 Unauthorized` means
  the path works and only pairing is left; a timeout sends you back to step 2. With only TCP opened,
  `ping6` failing is expected.

### 2. Open one port on the ONT

Log in as **super admin** (usually `http://192.168.1.1`) and:

1. keep the **IPv6 firewall enabled**;
2. add an **IPv6 virtual server / port mapping**: internal host = the computer's IPv6, protocol TCP,
   port 3090 (same inside and out), attached to the PPPoE WAN.

Most ONT UPnP implementations are IGD v1 only and do not affect IPv6 inbound — do not count on it
to open the port for you.

| Vendor (examples) | Menu path | Notes |
|---|---|---|
| Huawei HN8145XR / V173 / OptiXstar V175 | Security → Firewall → IPv6 firewall; Application → Advanced NAT → IPv6 virtual server | keep the firewall on; map TCP 3090 to the host |
| ZTE F7607P / G7615 / G7615AV5 | Security → Firewall (IPv6 has its own switch); Application → Port mapping / virtual host | some firmware has no IPv6 mapping page; telnet `ip6tables` (reverts on reboot) |
| FiberHome HG3142f / HG6145D2 | Security → Port filter → Access control (WAN-LAN) | whitelist the destination port; some firmware ranges are imprecise and also affect IPv4 — verify from outside |
| Nokia Bell / TEWA / Youhua | usually no separate IPv6 firewall switch | IPv6 inbound is blocked by default; telnet `ip6tables` or ask your ISP; may revert on reboot |

### 3. Pin the computer's IPv6 address

DHCPv6 hands out addresses in pool order and SLAAC privacy addresses rotate, so the host suffix
drifts (`::2`, `::3`, `::100` were all observed) and the mapping breaks.

- ONT: DHCPv6 static allocation, binding the NIC MAC to a fixed suffix (e.g. `::200`).
- Host (recommended belt-and-braces): add a static address so a reboot does not leave
  NetworkManager without a fresh lease:

  ```sh
  nmcli connection modify "Wired connection 1" +ipv6.addresses '<prefix>::200/64'
  nmcli connection up "Wired connection 1"
  ```

  Take the `/64` from the ONT; the address should show `forever` in `ip -6 addr`.

> If the ISP changes the `/64` prefix (re-dial or central-office change), update both the ONT
> mapping and the host address; the `::200` suffix stays.

### 4. Connect the app

Enter `http://[<computer IPv6>]:3090` (brackets required) and paste the desktop pairing code.
Global-unicast IPv6 counts as a direct endpoint, so it joins the LAN / virtual-net / tunnel
candidates in the probe-and-pick before reconnecting.

### ONT accounts

- `useradmin` on the label has limited rights; IPv6 firewall and port mapping need the **super admin**.
- Common factory super admins seen online (region/firmware dependent, not guaranteed):

  | Carrier | Account | Common factory password |
  |---|---|---|
  | China Mobile | `CMCCAdmin` | `aDm8H%MdA`, `Cmcc10086#` |
  | China Telecom | `telecomadmin` | `nE7jA%5m` |
  | China Unicom | `CUAdmin` | `CUAdmin` / `cuadmin` |

  On some FiberHome models the web super admin is `rootadmin` (model dependent).
- The carrier's ACS may already have changed the factory password (sometimes on every reboot); the
  label or the installation sheet is authoritative. **If you cannot get in, or the change does not
  take effect, contact your local broadband maintenance staff** and ask them to map one TCP port over
  IPv6 — much safer than blindly editing `telnet` settings, which can take the line down or reset
  the ONT.
- This README records no real addresses, accounts or passwords.

### Security notes

- Only TCP 3090 is mapped; an unpaired bridge always answers 401, and pairing credentials stay on
  the phone.
- Do not disable the ONT's IPv6 firewall and do not put the computer in the DMZ.
- For stronger isolation, put an HTTPS reverse proxy or a VPN (WireGuard / Tailscale) in front and
  expose only that.

## Build from source

You need Flutter-OH `3.50.0+ohos-1.3.3`, the Android SDK and JDK 17; building the HarmonyOS HAP also
needs HarmonyOS SDK API 26. The SDKs are not bundled in this repository.

```sh
cd app
flutter pub get
flutter analyze
flutter test                # 616 cases

flutter build apk --release --target-platform android-arm64
flutter build hap --release --no-codesign
```

- Use **Flutter-OH**. Upstream stable lacks `TargetPlatform.ohos`, so the material_ui/cupertino_ui
  ohos forks do not compile.
- iOS on macOS: `flutter build ios --release --no-codesign`, then zip `Runner.app/Payload` into an
  unsigned IPA. The CI `macos-15` job already does this.

## CI and release

| Workflow | What it does |
|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | `docs-check` + `flutter analyze` + `flutter test` (616); uses the Flutter-OH SDK |
| [`release.yml`](.github/workflows/release.yml) | On a tag: Ubuntu builds the APK, `macos-15` builds an unsigned IPA; HAP is an optional self-hosted job (`BUILD_HAP=true` plus a real HarmonyOS SDK) |
| [`mirror-sync.yml`](.github/workflows/mirror-sync.yml) | Gitee → GitHub mirror; GitHub is a read-only mirror, day-to-day pushes go to Gitee |

`scripts/release.sh` runs the gates, builds the APK/HAP, optionally signs the HAP, backfills the
README, creates the two-site releases and verifies the uploaded assets. See
[`docs/project/RELEASE.md`](docs/project/RELEASE.md).

## Repository layout

```
dsh-Chat/
  AGENTS.md     ← engineering rules: red lines, commands, protocol discipline, doc sync, pitfalls
  assets/       ← README hero and actual-effect screenshots
  docs/         ← STRUCTURE.md / design-tokens.md / project/ (documentation index)
  ref/          ← official visual references and packet captures; read-only, not built or imported
  app/          ← Flutter project (lib/ has only design/, bridge/, ui/)
  app/ohos/     ← Flutter-OH HarmonyOS host project (bundleName com.dsh.dshchat)
  app/vendor/   ← patched third-party packages (gpt_markdown, see README.dsh.md)
  LICENSE       ← AGPL-3.0
```

## Known limitations

- **iOS is not device-verified**: the bridge is implemented and CI builds, but notification taps,
  TTS quality and photo/file permissions still need an iPhone. iOS does not allow in-app installs;
  updates point to the App Store.
- **HarmonyOS release signing**: a release HAP signed with the project certificate can fail with
  `signature verification failed due to not trusted app source` on some devices. Distribution needs
  an AGC certificate/profile.
- **App label**: v1.0.36 and earlier HAPs still show `dshchat` on the launcher; v1.0.38 and later use `DSH Chat`.
- **Toolchain is pinned**: all three platforms share the Flutter-OH SDK; replacing it with upstream
  stable breaks the ohos forks.
- **Updates**: only Android supports in-app download/install; iOS and HarmonyOS use their stores.

## Repositories

| Site | URL | Role |
|---|---|---|
| Gitee | <https://gitee.com/westanke/dsh-Chat> | Primary |
| AtomGit | <https://atomgit.com/westanke163/dsh-Chat> | Backup |
| GitHub | <https://github.com/westanke/dsh-Chat> | Automatic mirror; do not push by hand |

## Sibling projects

- [`dsh-remote-bridge`](https://github.com/westanke/dsh-remote-bridge) — the upstream desktop plugin
  (REST + WS + phone settings); its protocol and minimum version are authoritative (≥ 2.10.0, protocol v3).
- [`dsh-companion`](https://github.com/westanke/dsh-companion) — the Kotlin/Compose client in the same
  ecosystem, sharing the same bridge protocol. **No longer maintained or updated**; kept for historical
  reference only.

## License

[GNU Affero General Public License v3.0](LICENSE).
