// post-md:// content encoding
export const URL_PREFIX = "post-md://new?content=";

function bytesToBase64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b); // each char ≤ 0xFF → safe for btoa
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** UTF-8 → base64url (RFC 4648, no padding). Don't call btoa on the raw text. */
export function toBase64URL(input: string): string {
  return bytesToBase64URL(new TextEncoder().encode(input));
}

/**
 * Returns null if the raw bytes exceed the content limit (the caller shows the alert). The limit is on raw
 * bytes, not URL length: transport (the URL) allows up to 32MB, but we keep a separate content budget to
 * cap storage (UserDefaults) and rendering cost. The size check runs before base64 encoding so oversized
 * input can't stall the main thread.
 */
export function buildStickyURL(content: string, maxContentBytes: number): string | null {
  const bytes = new TextEncoder().encode(content);
  if (bytes.length > maxContentBytes) return null;
  return URL_PREFIX + bytesToBase64URL(bytes);
}

export const OPEN_URL_PREFIX = "post-md://open?path=";

/**
 * Build a link URL that tells the app to OPEN (and stay synced to) an on-disk file, rather than
 * copy a text snapshot. The absolute path is base64url-encoded (same alphabet as content) so spaces,
 * unicode, and slashes survive transport and the app-side alphabet check. No size cap: paths are short,
 * and the app enforces the content cap when it reads the file.
 */
export function buildOpenURL(absPath: string): string {
  return OPEN_URL_PREFIX + toBase64URL(absPath);
}
