import type { MarkEdit as MarkEditAPI } from "markedit-api";
import { buildStickyURL, buildOpenURL } from "./encoding";
import { deriveContent } from "./selection";
import { MAX_CONTENT_BYTES } from "./limits";
import { detectLang, t } from "./i18n";

declare const MarkEdit: MarkEditAPI;

// Derive the over-limit message from the constant so the size never gets hardcoded again.
const MAX_MB = Math.round(MAX_CONTENT_BYTES / (1024 * 1024));

// Idempotent registration guard: MarkEdit loads the extension script once per webview context, so the
// same script can run multiple times (confirmed in a two-stage pre-flight test). A global sentinel blocks duplicate menu registration.
const g = globalThis as unknown as { __postMDRegistered?: boolean };
if (!g.__postMDRegistered) {
  g.__postMDRegistered = true;

  MarkEdit.addMainMenuItem([{
    title: "Pop as Sticky",
    action: async () => {
      const m = t(detectLang(), MAX_MB);
      // Use the selection if there is one, otherwise the whole document. deriveContent does the work (pure function, covered by tests).
      const selections = MarkEdit.editorAPI.getSelections();
      const hasSelection = selections.some((r) => r.to !== r.from);
      const content = deriveContent(selections, (range) => MarkEdit.editorAPI.getText(range));

      // Treat a whitespace-only document or selection as empty too (avoids launching an invisible blank card). The launched content keeps the original text.
      if (content.trim().length === 0) {
        void MarkEdit.showAlert({ title: m.emptyTitle, message: m.emptyBody });
        return;
      }

      // Whole document → try to link it to its file. A selection is a fragment with no file, so it stays a snapshot.
      if (!hasSelection) {
        const info = await MarkEdit.getFileInfo();
        if (info?.filePath) {
          // Best-effort flush so the linked file on disk matches what's on screen, then link.
          // We deliberately do NOT gate the link on saveDocument()'s boolean: markedit-api doesn't
          // specify its return for a clean (no-op) save, and gating would silently snapshot the common
          // "open a saved file and Pop" case. A dirty document whose save truly fails links slightly-stale
          // disk content — rare, and the app's hash-based conflict detection catches later divergence.
          try { await MarkEdit.saveDocument(); } catch { /* best-effort flush */ }
          window.location.href = buildOpenURL(info.filePath);
          return;
        }
        // Genuinely untitled (no file on disk) → warn, then snapshot or cancel.
        const choice = await MarkEdit.showAlert({
          title: m.unsavedTitle,
          message: m.unsavedBody,
          buttons: [m.unsavedSnapshotBtn, m.cancelBtn],
        });
        if (choice !== 0) return; // Cancel
        // fall through to snapshot
      }

      // Over the content limit (raw bytes): reject and warn instead of truncating (no silent failure, no truncation).
      const url = buildStickyURL(content, MAX_CONTENT_BYTES);
      if (url === null) {
        void MarkEdit.showAlert({
          title: hasSelection ? m.tooLargeTitleSel : m.tooLargeTitleDoc,
          message: m.tooLargeBody,
        });
        return;
      }
      window.location.href = url;
    },
  }]);
}
