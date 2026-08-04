# TokenUsage

macOS menu bar app that tracks **Claude Code** usage — 5-hour window, weekly limit, Fable allocation, and live session context — so you don't hit the wall mid-task.

Loosely inspired by [Usagebar](https://usagebar.com/) and the API approach in [claude-monitor](https://github.com/rjwalters/claude-monitor).

## Features

- **Menu bar % remaining** — orange under 20% left, red under 5%
- **Popover** — 5-hour, weekly, Fable, context fill, today's messages/tokens
- **Setup token auth** — paste the long-lived token from `claude setup-token` (Keychain)
- **Local context** — reads latest `~/.claude/projects/**/*.jsonl` transcript
- **Desktop notifications** under 20% left (Almost hit) and under 5% left (Limit low) — allow when macOS prompts; test via ⋯ → **Test notification**

## Requirements

- macOS 14+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (for `claude setup-token`)
- Xcode CLT / Swift 5.9+

## Install (use forever)

Build a real macOS app and put it in Applications:

```bash
./scripts/build-app.sh
cp -R build/TokenUsage.app /Applications/
open /Applications/TokenUsage.app
```

Then:

1. Click **TU** (or the %) in the menu bar → paste a token from `claude setup-token` (once; stored at `~/Library/Application Support/TokenUsage/token`, mode 0600).
2. Optional — open at login: **System Settings → General → Login Items → +** → pick TokenUsage.
3. First open may need **right-click → Open** if Gatekeeper complains (unsigned/ad-hoc signed).

After that it’s a normal menu-bar app: no Terminal, no `swift run`.

### Dev only

```bash
swift run          # temporary binary under .build/
```

## How it works

| Metric | Source |
|--------|--------|
| 5-hour / weekly | `POST /v1/messages` (1 Haiku token) → `anthropic-ratelimit-unified-5h/7d-*` headers |
| Fable | Probe `claude-fable-5` → `anthropic-ratelimit-unified-7d_oi-*` headers |
| Context | Latest assistant `usage` in local Claude Code JSONL |
| Today | Sum of assistant turns in today's transcripts |

Token never leaves the machine except as `Authorization: Bearer` to Anthropic. Reinstalls do not re-prompt — we intentionally avoid Keychain so ad-hoc re-signing does not trigger macOS password dialogs.

## Thresholds

| Remaining | State | Menu bar |
|-----------|-------|----------|
| ≥ 20% | Normal | default |
| < 20% | Almost hit | orange |
| < 5% | Context low | red |

## License

MIT
