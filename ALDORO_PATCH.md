# Aldoro Android TV fork

Base: upstream `media-kit/media-kit` at `c533e446755f51cf53c7e57aea873f2aa5355f81`.
Branch: `codex/android-tv`. Keep both Dart packages pinned to the same commit.

## Comparison and selected changes

| Source | Decision |
| --- | --- |
| [Predidit](https://github.com/Predidit/media-kit/tree/cd75bcfe94ba45ebb6f6b940c68e072d079aee14) | Reuse its native event-loop owner, C cleanup worker, owned screenshot replies, allocation cleanup and lifecycle stress fixtures. Do not replace the entire fork: it also changes binary delivery, platform renderers and APIs, and lacks upstream's newer media/content-URI leak fixes. |
| [PR 1454](https://github.com/media-kit/media-kit/pull/1454), `ed6311a53607527dafc255c05d164c33d5ebeb36` | Cherry-picked with original authorship. Public property writes use the existing async mpv request/reply path, including Android surface attachment. |
| [PR 1424](https://github.com/media-kit/media-kit/pull/1424) / [issue 1443](https://github.com/media-kit/media-kit/issues/1443) | Use Predidit's native owner instead. The PR retains a five-second destruction timer and does not await native teardown. |
| [PR 1356](https://github.com/media-kit/media-kit/pull/1356) | Reuse the disposal-guard approach for Android; additionally drain the controller lock before releasing notifiers and the surface. Avoid taking the player's lifecycle lock inside this controller lock. |
| [Issue 1445](https://github.com/media-kit/media-kit/issues/1445) | Restore position only after attaching a nonzero surface to a demuxer reporting `seekable=yes`. Never seek on surface detachment or a non-seekable live stream. |
| [PR 1393](https://github.com/media-kit/media-kit/pull/1393) | Not taken: a standalone notifier disposal method does not coordinate asynchronous initialization/listener ownership. |
| [PR 1435](https://github.com/media-kit/media-kit/pull/1435) | Not taken: broad toolchain/Kotlin/Apple integration migration is separate from these playback fixes. |
| [PR 1476](https://github.com/media-kit/media-kit/pull/1476) | Not taken: changes NativeVideoController output size; Android uses a different controller. |

## Lifetime and compatibility

Android uses `NativeEventLoop`: mpv retains a C callback, not an executable Dart
callback. Explicit disposal waits for the current event consumer, destroys mpv
on a native worker, then awaits acknowledgement. A native finalizer covers isolate
shutdown without depending on a Dart timer or another Flutter engine. Repeated
disposal returns the same future. Pending requests fail instead of hanging.

The existing `NativePlayer.test` mode exercises the same ownership path on the
host. Desktop/Apple production player teardown and renderers retain their upstream
behavior; their asynchronous renderer teardown needs separate validation before
extending the ownership change beyond Android.

Screenshot replies copy pixels before mpv reuses the event buffer. Only owned
pixels enter the encoding isolate, so destruction cannot invalidate its input.
The public API, playlist handling and upstream media cache fixes are retained.

The C owner and tests are adapted from Predidit's revision above under the
repository MIT license. The build hook compiles only this small bridge; it does
not replace libmpv or FFmpeg. Keep `media_kit_libs_video` and existing platform
library packages. `media_kit` now requires Dart >=3.10 and a native compiler.
Android's `gpu`, `auto-safe`, SurfaceProducer and emulator software-decoding
defaults remain unchanged.

## Validation

From the repository root, run `flutter pub get`. On macOS, prepare the official
upstream test libmpv using `media_kit/test/ci/macos/scripts/setup_dylibs.sh` from
the `media_kit` directory and set `LIBMPV_LIBRARY_PATH` to its
`test/ci/macos/libs/libmpv.dylib` absolute path.

```sh
cd media_kit
dart test test/src/player/native/core/native_event_loop_test.dart test/src/player/native/core/native_player_lifecycle_test.dart
cd tool/lifecycle_test
dart pub get
dart test
```

```sh
cd media_kit_video
flutter test test/android_video_controller_test.dart
```

The native tests exercise repeated create/dispose, initialization disposal,
asynchronous and synchronous properties, concurrent writes/disposal and screenshot
ownership. The controllable native fixture checks borrowed event lifetime, delayed
destruction acknowledgement, initialization failure and 150 isolate shutdowns
with callbacks or disposal active, followed by recreation in the same process.
Android controller tests cover live attachment, VOD position restoration,
detachment and disposal during queued attachment.

These host tests do not measure Android hardware decoding or video frame drops.
Use Aldoro's existing TV integration test and profile entry point on the target
device with both live and on-demand streams before claiming a performance gain.
