# obsidian/src

`encoding.ts` and `limits.ts` are BYTE-IDENTICAL copies of `extension/src/*`.
They encode the `sticky://` URL contract shared with the macOS app's Swift decoder
(`app/Sources/PostMDCore/StickyURLParser.swift`).

Do NOT edit them — not even comments (the `// extension/src/limits.ts:` header stays
verbatim). Any change breaks byte-identity and fails `extension/test/obsidian-drift.test.ts`.

To re-sync after an upstream change in `extension/src`:

    cp extension/src/encoding.ts obsidian/src/encoding.ts
    cp extension/src/limits.ts   obsidian/src/limits.ts
