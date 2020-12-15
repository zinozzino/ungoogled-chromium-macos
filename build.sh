#!/bin/bash -eux

# Simple build script for macOS

_root_dir=$(dirname $(greadlink -f $0))
_download_cache="$_root_dir/build/download_cache"
_src_dir="$_root_dir/build/src"
_main_repo="$_root_dir/ungoogled-chromium"

# For packaging
_chromium_version=$(cat $_root_dir/ungoogled-chromium/chromium_version.txt)
_ungoogled_revision=$(cat $_root_dir/ungoogled-chromium/revision.txt)
_package_revision=$(cat $_root_dir/revision.txt)

rm -rf "$_src_dir/out" || true
mkdir -p "$_src_dir/out/Default"
mkdir -p "$_download_cache"

"$_main_repo/utils/downloads.py" retrieve -i "$_main_repo/downloads.ini" "$_root_dir/downloads.ini" -c "$_download_cache"
"$_main_repo/utils/downloads.py" unpack -i "$_main_repo/downloads.ini" "$_root_dir/downloads.ini" -c "$_download_cache" "$_src_dir"
"$_main_repo/utils/prune_binaries.py" "$_src_dir" "$_main_repo/pruning.list"
"$_main_repo/utils/patches.py" apply "$_src_dir" "$_main_repo/patches" "$_root_dir/patches"
"$_main_repo/utils/domain_substitution.py" apply -r "$_main_repo/domain_regex.list" -f "$_main_repo/domain_substitution.list" -c "$_root_dir/build/domsubcache.tar.gz" "$_src_dir"

cd "$_src_dir"

for arch in ("arm64", "x86_64"); do
  cp "$_main_repo/flags.gn" "$_src_dir/out/release_$arch/args.gn"
  cat "$_root_dir/flags.macos.gn" >> "$_src_dir/out/release_$arch/args.gn"

  if [ $arch = "arm64" ]; then
    echo "target_cpu=\"arm64\"" >> "$_src_dir/out/release_$arch"
  fi

  rm -rf out/Release

  ./tools/gn/bootstrap/bootstrap.py -o "out/release_$arch/gn" --skip-generate-buildfiles
  "./out/release_$arch/gn" gen "out/release_$arch" --fail-on-unused-args
  ninja -C "out/release_$arch" chrome chromedriver
done

mkdir -p out/release_universal
chrome/installer/mac/universalizer.py \
  ./out/release_x86_64/Chromium.app \
  ./out/release_arm64/Chromium.app \
  ./out/release_universal/Chromium.app

chrome/installer/mac/pkg-dmg \
  --sourcefile --source out/release_universal/Chromium.app \
  --target "$_root_dir/build/ungoogled-chromium_${_chromium_version}-${_ungoogled_revision}.${_package_revision}_macos_universal.dmg" \
  --volname Chromium --symlink /Applications:/Applications \
  --format UDBZ --verbosity 2

# Fix issue where macOS requests permission for incoming network connections
# See https://github.com/ungoogled-software/ungoogled-chromium-macos/issues/17
xattr -csr out/Default/Chromium.app
# Using ad-hoc signing
codesign --force --deep --sign - out/Default/Chromium.app
