#!/usr/bin/env sh
sed -e 's/claude-code/gemini-cli/g' \
    -e 's/Claude Code/Gemini CLI/g' \
    -e 's/Claude/Gemini/g' \
    -e 's/claude/gemini/g' \
    -e 's/compact/compress/g' \
    -e 's/Compact/Compress/g' \
    -e 's/Exit/Quit/g' \
    -e 's/exit/quit/g' \
    claude-code.el > gemini-cli.el
