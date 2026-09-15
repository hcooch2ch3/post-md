// preflight/test-length-auto.js: automated URL-length measurement, fires each size in sequence on editor load
// Note: remove from scripts/ once measured (it fires every time the editor opens)
const fire = (urlLen) => {
  const prefix = "post-md://new?content=";
  const payload = "A".repeat(urlLen - prefix.length);
  window.location.href = prefix + payload;
};
const sizes = [1, 8, 43, 128]; // KB
sizes.forEach((kb, i) => {
  setTimeout(() => fire(kb * 1024), 2000 + i * 1500);
});
