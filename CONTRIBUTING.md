# Contributing to YouTubeInsight

Thank you for helping improve YouTubeInsight.

## Development requirements

- Apple Silicon Mac running macOS 13 or later
- Swift 5.10 or later
- `uv`
- Codex CLI for the end-to-end smoke test

Install runtime dependencies:

```bash
brew install uv
codex login
```

## Validate a change

Run the deterministic self-tests first:

```bash
chmod +x scripts/run-tests.sh
./scripts/run-tests.sh
```

Build and verify the macOS app:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/YouTubeInsight.app
```

For changes to the download, transcription, or analysis pipeline, also run:

```bash
chmod +x scripts/smoke-test.sh
./scripts/smoke-test.sh "https://www.youtube.com/watch?v=XYgm-dNNrR8"
```

The smoke test downloads audio and may use a logged-in Codex account. Do not run
it with private or confidential media unless that use complies with your account
and organizational policies.

## Localization

Every localization file must contain the same keys as
`Resources/en.lproj/Localizable.strings`. `scripts/run-tests.sh` checks key
parity and validates the `.strings` files.

When adding a user-facing string:

1. Add an English fallback in the Swift source.
2. Add the key to all eight `Localizable.strings` files.
3. Run `./scripts/run-tests.sh`.

## Pull requests

- Keep changes focused.
- Explain the user-visible behavior.
- Include the checks you ran.
- Do not commit `build/`, `dist/`, `.build/`, model caches, transcripts, or
  personal analysis history.

By contributing, you agree that your contribution may be distributed under the
MIT License.
