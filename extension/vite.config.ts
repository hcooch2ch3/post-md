// The lib IIFE build is already a single file (no need for vite-plugin-singlefile, which is HTML-only)
import { defineConfig } from "vite";

export default defineConfig({
  build: {
    lib: { entry: "src/index.ts", formats: ["iife"], name: "PostMD", fileName: () => "post-md" },
    outDir: "dist",
    rollupOptions: { output: { entryFileNames: "post-md.js" } }
  }
});
