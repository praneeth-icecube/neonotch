# Contributing to NeoNotch

Thanks for your interest in improving NeoNotch. Bug reports, ideas and pull requests are all welcome.

## Reporting bugs

[Open an issue](https://github.com/praneeth-icecube/neonotch/issues/new) that includes:

- your macOS version and Mac model, and whether the display has a notch
- what you did, what you expected, and what happened instead
- a screenshot or screen recording, if the problem is visual
- relevant lines from a trace, if you can reproduce it (see [Tracing](docs/ARCHITECTURE.md#tracing))

## Suggesting features

Open an issue describing the problem you want solved before you write a large change. NeoNotch tries to stay small, fast and out of the way, so a quick discussion first saves everyone time.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep it focused: one fix or feature per pull request.
3. Make sure it builds without warnings in Xcode, then run the checks below.
4. Open a pull request describing what changed and why. Include before and after screenshots for UI changes.

### Checks

Build a Debug copy, then run:

```bash
APP=path/to/NeoNotch.app/Contents/MacOS/NeoNotch
$APP --selftest-widgets
$APP --selftest-drop /etc/hosts
$APP --snapshot /tmp/neonotch-shots
```

If you change anything in `Features/Music`, run `--selftest-music` as well (see [Self-tests](docs/ARCHITECTURE.md#self-tests)). For UI changes, look through the snapshots to confirm that every state still renders correctly.

## Code style

- Follow the style of the surrounding code: Swift 5, SwiftUI for views, and AppKit where SwiftUI can't do the job (windows, drops, hit-testing).
- Each feature lives in its own folder under `NeoNotch/Features`, with a model and its views.
- Comments explain *why*, not *what*. If something is non-obvious or was learned the hard way, write it down.
- Respect the closed island's rule: it only grows sideways and never drops below the menu bar.
- Don't add analytics, third-party services or network calls that send user data anywhere.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
