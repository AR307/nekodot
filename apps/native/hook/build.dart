import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Cargo's dep-info lists Rust sources, not the manifest's feature selection.
    output.dependencies.addAll([
      input.packageRoot.resolve('rust/Cargo.toml'),
      input.packageRoot.resolve('rust/Cargo.lock'),
      input.packageRoot.resolve('rust/rust-toolchain.toml'),
    ]);
    await const FlutterRustBridgeNativeAssetsBuilder(cratePath: 'rust')
        .run(input: input, output: output);
  });
}
