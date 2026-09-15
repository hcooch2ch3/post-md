#!/bin/bash
# i18n acceptance gate — guards the English-default migration against silent regressions.
#
# What it checks: the set of CJK (Hangul + Han) lines surviving in the tree must exactly
# equal scripts/i18n-allowlist.txt. That allowlist is the expected-survivor snapshot from
# the migration, and it legitimately contains TWO kinds of Korean:
#   1. runtime i18n strings — the `.ko` / `ko:` branches of app/Sources/PostMDCore/L10n.swift
#      and extension/src/i18n.ts (the Korean half of every user-facing string), and
#   2. category-C test data — Korean values passed to code under test, expected values, and
#      fixture `input` fields that verify multibyte/NFC/NFD/byte-boundary + roundtrip handling.
# Both MUST stay Korean. Everything else (comments, NSLog, test titles/messages, deploy echoes,
# JSON note/_comment) is English.
#
# Why a green test suite is not enough: if a category-C value were wrongly Englishized, the
# multibyte/NFC/NFD assertions would still pass on the surviving ASCII — CI green, coverage
# silently gone. This diff catches that (a destroyed C line goes MISSING; a missed prose line
# shows up EXTRA). It catches allowlist/edit INCONSISTENCY; it cannot prove a *consistent*
# misclassification (same wrong call on both sides) — the diff audit + review do that.
# Two other limits: it audits only git-TRACKED content (stage new files before trusting it),
# and it cannot catch a value-for-value swap that preserves the surviving line multiset.
#
# Regenerate the allowlist ONLY when you have intentionally added/removed Korean and verified
# (tests + review) it is correct (note the UTF-8 locale on git grep — under LC_ALL=C the \x{}
# escapes error out to zero lines and the '>' would truncate the allowlist to empty):
#   LC_ALL="${STICKY_GREP_LOCALE:-en_US.UTF-8}" git grep -hP '[\x{1100}-\x{11ff}\x{ac00}-\x{d7a3}\x{4e00}-\x{9fff}]' -- . \
#     ':(exclude,glob)**/README*.md' ':!*.png' ':!assets/' ':!docs/' ':!scripts/' \
#     | LC_ALL=C sort > scripts/i18n-allowlist.txt
set -euo pipefail
# NOTE on locale: git grep -P needs a UTF-8 LC_CTYPE or PCRE runs in 8-bit mode and rejects the
# \x{4e00}-\x{9fff} (Han) escapes as "code point too large". So we do NOT export LC_ALL=C globally
# (that broke the sweep). git grep runs UTF-8; only `sort` is pinned to LC_ALL=C for determinism.
GREP_LC="${STICKY_GREP_LOCALE:-en_US.UTF-8}"   # override via env if this locale is unavailable
cd "$(git rev-parse --show-toplevel)"
ALLOW="scripts/i18n-allowlist.txt"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
# Content-keyed (no -n) so line moves/renames don't churn the allowlist. Hex ranges (Hangul +
# Han) instead of literal Hangul so ':!scripts/' can exclude this file without it self-matching.
# ':(exclude,glob)**/README*.md' excludes bilingual READMEs at root AND any depth.
# git grep exits 1 on no match; '|| true' keeps set -e from killing us, then we assert non-empty.
LC_ALL="$GREP_LC" git grep -hP '[\x{1100}-\x{11ff}\x{ac00}-\x{d7a3}\x{4e00}-\x{9fff}]' -- . \
  ':(exclude,glob)**/README*.md' ':!*.png' ':!assets/' ':!docs/' ':!scripts/' > "$tmp" || true
if [ ! -s "$tmp" ]; then
  echo "i18n-guard: sweep matched NOTHING — pathspec/regex likely broken (locale? try STICKY_GREP_LOCALE)." >&2
  exit 1
fi
# Re-sort BOTH sides (LC_ALL=C for deterministic byte order) so hand-curation order can't spuriously diff.
if ! diff -u <(LC_ALL=C sort "$ALLOW") <(LC_ALL=C sort "$tmp"); then
  echo "i18n-guard: surviving CJK differs from $ALLOW (see diff above)." >&2
  echo "  - a MISSING line (in allowlist, not in tree): either a category-C value was destroyed" >&2
  echo "    (restore it), OR a B-prose line was correctly Englishized but left in the allowlist" >&2
  echo "    (delete it from $ALLOW). Check which before acting — do NOT blindly re-add Korean." >&2
  echo "  - an EXTRA line (in tree, not in allowlist) = prose left un-Englishized → translate it" >&2
  echo "    (or, if genuinely new intentional Korean, add it to $ALLOW)." >&2
  exit 1
fi
echo "i18n-guard: OK"
