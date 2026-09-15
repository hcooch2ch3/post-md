import { Plugin, Notice, MarkdownView, FileSystemAdapter, type Editor, type TFile } from "obsidian";
import { buildStickyURL, buildOpenURL } from "./encoding";
import { MAX_CONTENT_BYTES } from "./limits";
import { deriveContent } from "./derive";

const MAX_MB = Math.round(MAX_CONTENT_BYTES / (1024 * 1024));

// We launch the post-md:// URL through Electron's shell rather than window.location: Obsidian
// intercepts in-page scheme navigations, and there is no first-party API to fire a custom
// external scheme. Guarded so a renderer without node integration degrades to a Notice.
function electronShell(): { openExternal(url: string): Promise<void> } | null {
  try {
    return (window as any).require?.("electron")?.shell ?? null;
  } catch {
    return null;
  }
}

export default class StickyCastPlugin extends Plugin {
  onload() {
    // Launch API reachability: warns only when the shell is missing, so a healthy install is silent.
    if (!electronShell()) {
      console.warn("[stickycast] electron.shell unavailable — Pop as Sticky will not launch here.");
    }

    // Plain callback (not editorCallback) so the command still works when focus is on the
    // ribbon, command palette, or another pane — popActive() resolves the target note itself.
    this.addCommand({
      id: "pop-as-sticky",
      name: "Pop as Sticky",
      callback: () => this.popActive(),
    });

    this.addRibbonIcon("sticky-note", "Pop as Sticky", () => this.popActive());

    // editor-menu hands us the editor AND its own file (info.file) — pass both so the flush/link
    // always act on the note that was right-clicked, never a divergently-resolved "active" note.
    this.registerEvent(
      this.app.workspace.on("editor-menu", (menu, editor, info) => {
        menu.addItem((item) =>
          item.setTitle("Pop as Sticky").setIcon("sticky-note").onClick(() => void this.pop(editor, info.file)),
        );
      }),
    );
  }

  // Resolve the note to pop for the command/ribbon (which aren't handed an editor). Returns the editor
  // AND its own file from the SAME view — never two independent resolutions — so a later flush can't
  // write one note's buffer onto another note's file. Falls back progressively so clicking the ribbon
  // (which moves focus off the note) still works.
  private resolveTarget(): { editor: Editor; file: TFile | null } | null {
    const w = this.app.workspace;
    const active = w.activeEditor;
    if (active?.editor) return { editor: active.editor, file: active.file };
    const view = w.getActiveViewOfType(MarkdownView);
    if (view?.editor) return { editor: view.editor, file: view.file };
    // With several markdown panes and focus off all of them, this picks the most recently
    // active one (Obsidian's own "active pane" notion) — the intuitive target.
    const recent = w.getMostRecentLeaf();
    if (recent?.view instanceof MarkdownView && recent.view.editor) {
      return { editor: recent.view.editor, file: recent.view.file };
    }
    return null;
  }

  private popActive() {
    const target = this.resolveTarget();
    if (!target) {
      new Notice("Open a Markdown note to pop as a sticky.");
      return;
    }
    void this.pop(target.editor, target.file);
  }

  // An open?path= URL for `file`, or null if it can't be linked (no file, non-filesystem vault, or the
  // pre-link flush failed). `file` MUST be the file backing `editor` — the caller threads them as a pair.
  private async tryBuildOpenURL(editor: Editor, file: TFile | null): Promise<string | null> {
    if (!file) return null;
    const adapter = this.app.vault.adapter;
    if (!(adapter instanceof FileSystemAdapter)) return null;
    try {
      // Flush THIS editor's buffer to ITS OWN file so the linked file on disk matches what's on screen.
      // Obsidian saves on a debounce, so popping right after typing could otherwise link stale content.
      // Writing to `file` (the editor's own file, not getActiveFile()) is what prevents a cross-note overwrite.
      await this.app.vault.modify(file, editor.getValue());
    } catch (e) {
      console.error("[stickycast] flush before link failed", e);
      new Notice("Couldn't save the note before linking — popping a snapshot instead.");
      return null; // fall back to snapshot
    }
    return buildOpenURL(adapter.getFullPath(file.path));
  }

  private launch(shell: { openExternal(url: string): Promise<void> }, url: string) {
    void shell.openExternal(url).catch((e) => {
      console.error("[stickycast] openExternal failed", e);
      new Notice("Failed to launch the sticky — see console.");
    });
  }

  private async pop(editor: Editor, file: TFile | null) {
    if (process.platform !== "darwin") {
      new Notice("StickyCast is macOS-only.");
      return;
    }
    const shell = electronShell();
    if (!shell) {
      new Notice("Cannot launch: electron.shell is unavailable.");
      return;
    }

    const selections = editor.listSelections();
    const hasSelection = selections.some(
      (s) => s.anchor.line !== s.head.line || s.anchor.ch !== s.head.ch,
    );
    const content = deriveContent(
      selections,
      (from, to) => editor.getRange(from, to),
      () => editor.getValue(),
    );
    if (content.trim().length === 0) {
      new Notice("Nothing to pop — the document or selection is empty.");
      return;
    }

    // Whole note → flush to disk and link it to its file. A selection is a fragment with no file,
    // so it stays a snapshot. If the path can't be resolved (non-filesystem vault) or the flush fails,
    // tryBuildOpenURL returns null and we fall back to the snapshot below.
    if (!hasSelection) {
      const linked = await this.tryBuildOpenURL(editor, file);
      if (linked) {
        this.launch(shell, linked);
        return;
      }
    }

    const url = buildStickyURL(content, MAX_CONTENT_BYTES);
    if (url === null) {
      new Notice(`A sticky can hold about ${MAX_MB}MB. Select a smaller part and try again.`);
      return;
    }
    this.launch(shell, url);
  }
}
