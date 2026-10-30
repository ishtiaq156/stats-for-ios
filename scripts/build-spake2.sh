#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
crate_dir="$repo_dir/Native/Spake2Bridge"
output_dir="$repo_dir/Packages/ActivityCore/Vendor/Spake2FFI.xcframework"

if ! command -v cargo >/dev/null 2>&1; then
  export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
fi
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-darwin x86_64-apple-ios

for target in aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  cargo build --manifest-path "$crate_dir/Cargo.toml" --release --locked --target "$target"
done

mkdir -p "$crate_dir/target/universal"
lipo -create \
  "$crate_dir/target/aarch64-apple-darwin/release/libstats_spake2.a" \
  "$crate_dir/target/x86_64-apple-darwin/release/libstats_spake2.a" \
  -output "$crate_dir/target/universal/libstats_spake2_macos.a"
lipo -create \
  "$crate_dir/target/aarch64-apple-ios-sim/release/libstats_spake2.a" \
  "$crate_dir/target/x86_64-apple-ios/release/libstats_spake2.a" \
  -output "$crate_dir/target/universal/libstats_spake2_ios_sim.a"

rm -rf "$output_dir"
xcodebuild -create-xcframework \
  -library "$crate_dir/target/universal/libstats_spake2_macos.a" -headers "$crate_dir/include" \
  -library "$crate_dir/target/aarch64-apple-ios/release/libstats_spake2.a" -headers "$crate_dir/include" \
  -library "$crate_dir/target/universal/libstats_spake2_ios_sim.a" -headers "$crate_dir/include" \
  -output "$output_dir"
find "$output_dir" -name '*.a' -exec strip -S -x {} \;
