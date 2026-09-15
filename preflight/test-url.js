// preflight/test-url.js: MarkEdit extension, checks whether external URL navigation works
// Variants: A/C/D use location.href (scheme differs only), B uses window.open.
// - A(https): web-scheme external handoff. WebKit renders this scheme itself, so it's weak evidence for custom schemes.
// - D(obsidian://): non-web custom-scheme handoff, same class as the path post-md:// takes. The key signal for step 1.
// - C(mailto): the OS-level handler is broken on this Mac, so it's excluded from the verdict (kept for reference).
// - B(window.open): no-op in WKWebView when the host doesn't implement it, so low diagnostic value (kept for reference).
MarkEdit.addMainMenuItem([
  {
    title: "Pre-flight A: https via location.href",
    action: () => { window.location.href = "https://example.com/?preflight=href"; }
  },
  {
    title: "Pre-flight B: https via window.open",
    action: () => { window.open("https://example.com/?preflight=open"); }
  },
  {
    title: "Pre-flight C: mailto via location.href",
    action: () => { window.location.href = "mailto:test@example.com"; }
  },
  {
    title: "Pre-flight D: obsidian:// via location.href",
    action: () => { window.location.href = "obsidian://"; }
  }
]);
