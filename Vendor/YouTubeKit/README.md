# YouTubeKit: Flux native trailer subset

This is a local, deliberately restricted derivative of [alexeichhorn/YouTubeKit](https://github.com/alexeichhorn/YouTubeKit), release **0.4.10**, pinned commit **89854c93207ad0d2b3d78d6f1aea24595ca66552**. The original Swift code is MIT licensed; see LICENSE and UPSTREAM.json. Original blob hashes are retained for comparing later updates. There are no external Swift package dependencies.

This is **not an official YouTube playback API**. It uses current public player metadata. YouTube changes, IP restrictions, consent/login requirements or removed videos can make an otherwise valid trailer unavailable. An explicit app error remains visible in that case; no phone, QR code, browser, account or remote extraction service is substituted.

## Local changes

- Only the local parsing, stream models and optional JavaScriptCore signature solver are retained. Remote clients, servers, websockets, OAuth, token caches, proxy options, embedded/creator clients and age-verification helpers are absent.
- A normal anonymous watch response must explicitly report OK for the requested video ID, with no age marker, embed restriction, live content or DRM metadata. Every subsequent player response must meet the same policy. A denial terminates extraction; another client is never tried to evade it.
- Requests use ephemeral URLSession instances without cookies, credentials or caching. HTTPS request hosts are restricted to youtube.com and www.youtube.com; redirects to account/consent sites are refused. Requests have 8-second timeouts, resources have 12-second timeouts and response bodies are bounded at 12 MiB. The app resolver adds an 18-second structured cancellation deadline.
- Native output is restricted to HTTPS googlevideo.com media hosts, without embedded credentials or alternate ports. Clear HLS is preferred. Progressive MP4 must contain both H.264 video and AAC audio at at most 1080p. Separate audio/video DASH tracks are never combined.
- The upstream player timestamp and parsing algorithms remain in use. Signature work, only if needed, runs off the UI actor in JavaScriptCore with bundled parser helpers; no JavaScript network or native-object bridge is exposed. Network waits are cancellable. As with other synchronous parsing, cancellation is checked before and after a JavaScript evaluation; JavaScriptCore's public API does not supply a hard CPU execution deadline.
- Raw script outputs and signed stream URLs are not logged.

The application imports this package only on tvOS. macOS/iOS retain the official iframe player. The macOS smoke program defines FLUX_NATIVE_YOUTUBE_TESTING to compile and exercise the exact TV resolver independently.

## Included third-party resources

All three JavaScript files are copied unchanged from the pinned YouTubeKit revision; their upstream git blob hashes are recorded in UPSTREAM.json.

| Resource | Upstream | License |
| --- | --- | --- |
| meriyah.umd.js | https://github.com/meriyah/meriyah | ISC |
| astring.umd.js | https://github.com/davidbonnet/astring | MIT |
| yt_ejs_helper.js | https://github.com/yt-dlp/ejs | Unlicense |

License notices are included in the package resource bundle. Their source texts are the respective upstream LICENSE.md / LICENSE files; they are not a claim that these bundles match the latest upstream JavaScript release.

## Validation

Run from the repository root on a Mac with Xcode:

```sh
bash scripts/test-native-youtube.sh
bash scripts/test-native-youtube.sh --live
```

The package tests gate public-only status handling, video identity, age/embed restrictions, DRM rejection, host validation and muxed codec selection. The CLI recompiles the production resolver and repeats its essential policy fixtures. With --live, it then tries two named public trailers and loads AVURLAsset readiness and video/audio tracks. Network availability is reported separately from deterministic test success.

A native_asset_ready result proves native asset loading from that machine at that time. It is not a claim of visible playback on an Apple TV; the probe reports playback_verified:false explicitly. A login, timeout or network rejection is reported by category without signed URLs. Live failures do not hide fixture or compiler failures.
