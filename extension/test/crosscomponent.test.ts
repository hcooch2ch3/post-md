import { describe, it, expect } from "vitest";
import fixturesRoot from "../../fixtures/roundtrip.json";
import { toBase64URL, buildStickyURL, URL_PREFIX } from "../src/encoding";

// One machine-generated source (fixtures/roundtrip.json) is shared by both the extension and app tests.
// The app-side counterpart: app/Tests/PostMDTests/CrossComponentTests.swift (reads the same file and verifies the parser restores it).
interface Fixture { input: string; encoded: string; note?: string; }
const fixtures = (fixturesRoot as { fixtures: Fixture[] }).fixtures;

// A base64url decoder independent of both the app parser and the encoder (DOM atob + TextDecoder).
// Proves the encoder output round-trips through a third decoder too, removing the risk of a wrong vector passing on both sides.
function independentDecode(b64url: string): string {
  const b64 = b64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  const bytes = Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

describe("cross-component round-trip fixtures (fixtures/roundtrip.json)", () => {
  it("fixtures are non-empty (path/load regression guard)", () => {
    expect(fixtures.length).toBeGreaterThan(0);
  });

  for (const { input, encoded, note } of fixtures) {
    it(`encoder reproduces the fixture encoded: ${note ?? input}`, () => {
      // The real extension encoder must match the machine-generated encoded value byte for byte.
      expect(toBase64URL(input)).toBe(encoded);
      expect(buildStickyURL(input, 10 * 1024 * 1024)).toBe(URL_PREFIX + encoded);
    });

    it(`independent decoder round-trip (no encoder trust): ${note ?? input}`, () => {
      // toBase64URL output → third decoder → original text. Proves the encoder is correct rather than trusting the literal.
      expect(independentDecode(toBase64URL(input))).toBe(input);
    });
  }
});
