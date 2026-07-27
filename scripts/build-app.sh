#!/bin/zsh
set -euo pipefail

youtubeinsight_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$youtubeinsight_project_dir"

mkdir -p "build"
swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -o "build/YouTubeInsight" \
    Sources/YouTubeInsight/*.swift \
    -framework SwiftUI \
    -framework AppKit

if [[ -d "dist/YouTubeInsight.app" ]]; then
    rm -rf "dist/YouTubeInsight.app"
fi

mkdir -p "dist/YouTubeInsight.app/Contents/MacOS"
mkdir -p "dist/YouTubeInsight.app/Contents/Resources"

cp "build/YouTubeInsight" "dist/YouTubeInsight.app/Contents/MacOS/YouTubeInsight"
cp "Resources/Info.plist" "dist/YouTubeInsight.app/Contents/Info.plist"
cp -R Resources/*.lproj "dist/YouTubeInsight.app/Contents/Resources/"

codesign --force --deep --sign - "dist/YouTubeInsight.app"

echo "Built: $youtubeinsight_project_dir/dist/YouTubeInsight.app"
