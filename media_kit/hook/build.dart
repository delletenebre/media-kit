import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

// Predidit's native owner, using upstream media_kit_libs_* for libmpv itself.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'media_kit_event_loop',
      assetName: 'src/player/native/core/native_event_loop_bindings.dart',
      sources: ['src/native_event_loop.c'],
      includes: [
        File(
          Platform.resolvedExecutable,
        ).parent.parent.uri.resolve('include/').toFilePath(),
      ],
      libraries: [if (input.config.code.targetOS == OS.linux) 'pthread'],
    ).run(input: input, output: output);
  });
}
