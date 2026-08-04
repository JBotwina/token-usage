# TokenUsage

macOS menu bar app that tracks **Claude Code** usage — 5-hour window, weekly limit, Fable allocation, and live session context — so you don't hit the wall mid-task.

Loosely inspired by [Usagebar](https://usagebar.com/) and the API approach in [claude-monitor](https://github.com/rjwalters/claude-monitor).

## Features

- **Menu bar % remaining** — orange under 20% left, red under 5%
- **Popover** — 5-hour, weekly, Fable, context fill, today's messages/tokens
- **Setup token auth** — paste the long-lived token from `claude setup-token` (Keychain)
- **Local context** — reads latest `~/.claude/projects/**/*.jsonl` transcript
- **Notifications** when you cross into low / very-low

## Requirements

- macOS 14+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (for `claude setup-token`)
- Xcode CLT / Swift 5.9+

## Build & run

```bash
# Dev
swift build
.build/debug/TokenUsage &

# App bundle
./scripts/build-app.sh
open build/TokenUsage.app
```

First launch: click the **TU** menu item → run `claude setup-token` → paste the `sk-ant-oat01-…` token.

## How it works

| Metric | Source |
|--------|--------|
| 5-hour / weekly | `POST /v1/messages` (1 Haiku token) → `anthropic-ratelimit-unified-5h/7d-*` headers |
| Fable | Probe `claude-fable-5` → `anthropic-ratelimit-unified-7d_oi-*` headers |
| Context | Latest assistant `usage` in local Claude Code JSONL |
| Today | Sum of assistant turns in today's transcripts |

Token never leaves the machine except as `Authorization: Bearer` to Anthropic.

## Thresholds

| Remaining | State | Menu bar |
|-----------|-------|----------|
| ≥ 20% | Normal | default |
| < 20% | Almost hit | orange |
| < 5% | Context low | red |

## License

MIT
