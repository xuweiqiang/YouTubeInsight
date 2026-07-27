#!/bin/zsh
set -euo pipefail

youtubeinsight_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$youtubeinsight_project_dir"

for youtubeinsight_strings_file in Resources/*.lproj/Localizable.strings; do
    plutil -lint "$youtubeinsight_strings_file" >/dev/null
done

youtubeinsight_reference_keys="$(
    sed -n 's/^"\([^"]*\)".*/\1/p' Resources/en.lproj/Localizable.strings | sort
)"
for youtubeinsight_strings_file in Resources/*.lproj/Localizable.strings; do
    youtubeinsight_locale_keys="$(
        sed -n 's/^"\([^"]*\)".*/\1/p' "$youtubeinsight_strings_file" | sort
    )"
    if [[ "$youtubeinsight_locale_keys" != "$youtubeinsight_reference_keys" ]]; then
        echo "Localization keys do not match: $youtubeinsight_strings_file" >&2
        exit 1
    fi
done

mkdir -p "build"
swiftc \
    -target arm64-apple-macosx13.0 \
    -o "build/YouTubeInsightSelfTest" \
    Sources/YouTubeInsight/Models.swift \
    Sources/YouTubeInsight/Localization.swift \
    Sources/YouTubeInsight/AnalysisFormatter.swift \
    Sources/YouTubeInsight/AnalysisPresentation.swift \
    Sources/YouTubeInsight/HistoryStore.swift \
    Sources/YouTubeInsight/YouTubeURLParser.swift \
    Sources/YouTubeInsight/SubtitleParser.swift \
    Sources/YouTubeInsight/ProcessRunner.swift \
    Sources/YouTubeInsight/RuntimeEnvironment.swift \
    Sources/YouTubeInsight/WhisperTranscript.swift \
    Sources/YouTubeInsight/YouTubeOAuth.swift \
    Sources/YouTubeInsight/YouTubeAPI.swift \
    Sources/YouTubeInsight/AnalysisPipeline.swift \
    Tests/SelfTest.swift \
    -framework AppKit \
    -framework Network \
    -framework Security

"build/YouTubeInsightSelfTest"
