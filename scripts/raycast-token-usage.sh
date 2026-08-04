#!/bin/bash
# Raycast Script Command — toggle the TokenUsage popover.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Token Usage
# @raycast.mode silent
# @raycast.packageName TokenUsage
# @raycast.icon 📊
# @raycast.description Toggle Claude Code usage popover
#
# Optional parameters:
# @raycast.author TokenUsage
#
# Install: Raycast → Create Script Command → point at this file
# (or copy into your Raycast script commands folder).
# App must be running (menu bar). Hotkey also works natively: ⌥E

open "tokenusage://toggle"
