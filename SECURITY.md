# Security and privacy

## Trust model

YouTubeInsight is a local desktop client, but its complete workflow is not
offline:

- YouTube metadata, captions, and audio are retrieved from YouTube.
- `uvx` may download `yt-dlp`, `mlx-whisper`, Python packages, and model files.
- Transcription runs locally on the Mac.
- The transcript is sent to the locally authenticated Codex CLI for analysis.
- Analysis history is written to the current user's Application Support folder.

The app treats transcript text as untrusted quoted material and instructs the
analysis model to ignore commands embedded in it. This reduces, but cannot
eliminate, prompt-injection risk. Review generated analyses before relying on
them for medical, legal, financial, or safety-critical decisions.

## Local data

History:

```text
~/Library/Application Support/YouTubeInsight/history.json
```

Deleting a history item removes that record from the history file. Temporary
audio is removed after a completed or failed task. Package and Whisper model
caches are managed by `uv` and Hugging Face and are not removed when a history
record is deleted.

## Reporting a vulnerability

Do not open a public GitHub issue containing credentials, private video URLs,
transcripts, personal information, or exploit details.

Report the issue privately to the repository owner through the contact methods
listed on the owner's GitHub profile. Include:

- affected version or commit;
- reproduction steps;
- expected and actual behavior;
- impact;
- a minimal redacted proof of concept, if applicable.

Please allow reasonable time for investigation before public disclosure.
