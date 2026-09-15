**English** | [한국어](README.ko.md)

# post-md

Pop selected Markdown from MarkEdit onto your macOS desktop as a floating sticky note.

![post-md stickies on the desktop](assets/hero.png)

It has two parts:

- A **sender** — the **MarkEdit extension** (`extension/`) or the **Obsidian plugin** (`obsidian/`) — sends the current selection through a `post-md://` URL scheme.
- The **post-md companion app** (`app/`) catches that URL and draws it as a translucent sticky window. Only notes you pin with 📌 stay above other windows.

The two are coupled by exactly one thing: the custom `post-md://` URL scheme. The app never learns which editor sent a note, so any sender that speaks the scheme works.

## Requirements

- **post-md app**: macOS 14 or later.
- **MarkEdit**: [MarkEdit](https://github.com/MarkEdit-app/MarkEdit). The Homebrew cask (`brew install --cask markedit`) currently needs macOS 15+, so on macOS 14 grab a compatible build from the [GitHub releases](https://github.com/MarkEdit-app/MarkEdit/releases) instead.
- **Obsidian plugin** (optional): Obsidian 1.4 or later, on macOS.
- **To build**: Swift 5.9+ (Xcode or the CLI toolchain) and Node 18+.

## Install

> **Start the app first.** It registers the `post-md://` URL handler when it launches. Until it does, any URL the extension fires just disappears.

### 1. Companion app

```bash
cd app
./make-app.sh      # build, assemble .app, register with Launch Services, run
```

This produces and launches `build/post-md.app`. It stays out of the Dock (`LSUIElement`) and sits in the menu bar as a `note.text` icon.

### 2. MarkEdit extension

> **Install MarkEdit and open it once before this step.** The first launch creates MarkEdit's script container, and a Homebrew install may need Gatekeeper approval ("Open") the first time. Without the container, `deploy` stops with a clear error instead of failing halfway.

```bash
cd extension
npm install
npm run deploy     # build, then copy to MarkEdit's scripts directory
```

Restart MarkEdit and you'll find **Extensions ▸ Pop as Sticky**.

### 3. Obsidian plugin (optional)

macOS only, and the companion app must be running. There's no prebuilt bundle yet, so build it once:

```bash
cd obsidian
npm install
npm run build
```

Copy `manifest.json` (repo root) and `obsidian/main.js` into `<vault>/.obsidian/plugins/post-md/`, then enable **post-md** under Settings ▸ Community plugins. A community-store listing is planned.

## Using it

Four ways to make a sticky:

- **From MarkEdit**: select some Markdown, then **Extensions ▸ Pop as Sticky**. With nothing selected, popping a saved document **links** the sticky to that file (Live Sync); a selection or an unsaved document makes a plain snapshot.
- **From Obsidian**: run **Pop as Sticky** from the command palette, the ribbon icon, or the editor right-click menu. With nothing selected, it **links** the sticky to the note's file (Live Sync); a selection makes a plain snapshot.
- **From the clipboard**: menu bar icon ▸ **Sticky from clipboard**.
- **From a file**: menu bar icon ▸ **Open Markdown file…**, or drag a `.md` onto the menu bar icon. A sticky opened from a file stays linked to it (see below).

Each sticky has a top bar that darkens on hover: **✕** close (this deletes it), **📌** pin, **🎨** color (yellow, pink, blue, green, purple), an **opacity** slider, and **✏️** edit. Drag the body to move it; drag an edge to resize.

- **Unpinned stickies** drop behind whatever you switch to, so they never cover your work.
- **Pinned stickies** (📌) stay on top while you work.

Position, size, opacity, pin state, and color are saved and restored across restarts. The menu bar icon also holds the sticky list, **Hide all / Show all** (stash and bring back, not delete), All to front, Export sticky, Close all, recent errors, About, and Quit.

## Editing and Live Sync

- **Edit in place**: double-click the body or click **✏️**. **⌘Return** saves, **Esc** cancels.
- A sticky opened from a `.md` file is **linked** to it and gains two controls:
  - **⬆️** writes your edits back to the file, asking first if the file changed outside post-md.
  - **🔗** reveals the file in Finder, opens it in your editor, or detaches it (keeps the content, drops the link).
- **Live Sync**: edit the linked file in any editor and the sticky updates on its own. If both sides changed, a banner lets you **take the file** or **keep your edit**. Nothing is overwritten without your say.
- **Export**: menu bar icon ▸ **Export sticky** saves a sticky as a `.md` file.

## Limits

- Up to 30 stickies, each capped at about 1 MB of content (enough for essentially any Markdown document). Anything larger is refused with a notice rather than truncated.
- Renders standard GFM.

## Development

```bash
cd app && swift test          # unit tests for the core logic (parser, store)
cd extension && npm test      # unit tests for encoding, plus the Obsidian copy/derive guards
cd obsidian && npm run build  # bundle the Obsidian plugin to obsidian/main.js
```

## License and credits

Released under the [MIT License](LICENSE).

- Markdown rendering: [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (MIT)
- MarkEdit API types: [MarkEdit-api](https://github.com/MarkEdit-app/MarkEdit-api)
