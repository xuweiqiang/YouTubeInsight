#!/bin/zsh
set -euo pipefail

youtubeinsight_project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$youtubeinsight_project_dir"

mkdir -p "build"
swiftc \
    -target arm64-apple-macosx13.0 \
    -o "build/YouTubeInsightPipelineSmoke" \
    Sources/YouTubeInsight/Models.swift \
    Sources/YouTubeInsight/Localization.swift \
    Sources/YouTubeInsight/AnalysisFormatter.swift \
    Sources/YouTubeInsight/HistoryStore.swift \
    Sources/YouTubeInsight/YouTubeURLParser.swift \
    Sources/YouTubeInsight/SubtitleParser.swift \
    Sources/YouTubeInsight/ProcessRunner.swift \
    Sources/YouTubeInsight/AnalysisPipeline.swift \
    Tests/PipelineSmoke.swift

"build/YouTubeInsightPipelineSmoke" "${1:-https://www.youtube.com/watch?v=XYgm-dNNrR8}"
