#!/usr/bin/bash
# activate mise if installed
if hash mise 2>/dev/null; then
    eval "$(mise activate bash)"
    eval "$(mise complete bash)"
fi
