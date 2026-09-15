// preflight/test-length.js: measure the URL length limit (target: total encoded URL length)
const fire = (urlLen) => {
  const prefix = "post-md://new?content=";
  const payload = "A".repeat(urlLen - prefix.length); // 'A' is a valid base64url character
  window.location.href = prefix + payload;
};
MarkEdit.addMainMenuItem([
  { title: "Pre-flight: sticky 1KB URL",   action: () => fire(1024) },
  { title: "Pre-flight: sticky 8KB URL",   action: () => fire(8 * 1024) },
  { title: "Pre-flight: sticky 43KB URL",  action: () => fire(43 * 1024) },
  { title: "Pre-flight: sticky 128KB URL", action: () => fire(128 * 1024) },
]);
