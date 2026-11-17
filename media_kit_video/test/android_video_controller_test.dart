import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

class _Streams extends PlatformPlayer {
  _Streams() : super(configuration: const PlayerConfiguration());
}

class _Native implements NativePlayer {
  final _streams = _Streams();
  @override
  PlayerState get state => _streams.state;
  @override
  set state(PlayerState value) => _streams.state = value;
  @override
  PlayerStream get stream => _streams.stream;
  @override
  List<Future<void> Function()> get release => _streams.release;
  final calls = <String>[];
  String seekable = 'no';
  Completer<void>? propertyGate;
  @override
  bool disposed = false;
  @override
  Future<int> get handle async => 1;
  @override
  Future<void> setProperty(String key, String value,
      {bool waitForInitialization = true}) async {
    calls.add('$key=$value');
    await propertyGate?.future;
  }

  @override
  Future<String> getProperty(String key,
      {bool waitForInitialization = true}) async {
    expect(key, 'seekable');
    return seekable;
  }

  @override
  Future<void> seek(Duration position, {bool synchronized = true}) async {
    expect(synchronized, isFalse);
    calls.add('seek=${position.inMilliseconds}');
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    disposed = true;
    await _streams.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  late _Native native;
  late AndroidVideoController controller;
  late List<String> channelCalls;
  setUp(() {
    native = _Native();
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      channelCalls.add(call.method);
      return null;
    });
    controller = AndroidVideoController.test(
      Player(platformPlayer: native),
      const VideoControllerConfiguration(vo: 'gpu', hwdec: 'no'),
    );
    native.state = native.state.copyWith(position: const Duration(seconds: 12));
  });
  tearDown(() async {
    if (!native.disposed) await native.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> attach(int wid) async {
    controller.wid.value = wid;
    await controller.lock.synchronized(() {});
  }

  test('live surface attaches without seeking or restarting the stream',
      () async {
    await attach(42);
    expect(native.calls,
        ['vo=null', 'android-surface-size=1x1', 'wid=42', 'vo=gpu']);
  });

  test('seekable video restores its current position after attachment',
      () async {
    native.seekable = 'yes';
    await attach(42);
    expect(native.calls.last, 'seek=12000');
  });

  test('detaching a seekable video never seeks', () async {
    native.seekable = 'yes';
    await attach(42);
    native.calls.clear();
    await attach(0);
    expect(native.calls,
        ['vo=null', 'android-surface-size=1x1', 'wid=0', 'vo=null']);
  });

  test('disposal drains an in-flight attach and suppresses queued work',
      () async {
    native.seekable = 'yes';
    native.propertyGate = Completer<void>();
    controller.wid.value = 42;
    await Future<void>.delayed(Duration.zero);
    expect(native.calls, ['vo=null']);
    controller.wid.value = 43;
    var closed = false;
    final closing = native.dispose().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    native.propertyGate!.complete();
    await closing.timeout(const Duration(seconds: 2));
    expect(native.calls, ['vo=null']);
    expect(channelCalls, ['VideoOutputManager.Dispose']);
  });
}
