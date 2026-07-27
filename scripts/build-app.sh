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

youtubeinsight_latest_source_epoch="$(
    find Sources Resources -type f -print0 \
        | xargs -0 stat -f "%m" \
        | sort -nr \
        | head -1
)"
youtubeinsight_build_version="${YOUTUBEINSIGHT_BUILD_NUMBER:-$(
    date -u -r "$youtubeinsight_latest_source_epoch" "+%Y%m%d%H%M%S"
)}"

if [[ ! "$youtubeinsight_build_version" =~ ^[0-9]+$ ]]; then
    echo "Build number must contain digits only: $youtubeinsight_build_version" >&2
    exit 1
fi

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $youtubeinsight_build_version" \
    "dist/YouTubeInsight.app/Contents/Info.plist"

codesign --force --deep --sign - "dist/YouTubeInsight.app"

youtubeinsight_marketing_version="$(
    /usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "dist/YouTubeInsight.app/Contents/Info.plist"
)"
echo "Built: $youtubeinsight_project_dir/dist/YouTubeInsight.app"
echo "Version: $youtubeinsight_marketing_version ($youtubeinsight_build_version)"
