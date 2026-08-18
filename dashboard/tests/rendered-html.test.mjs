import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker.fetch(new Request("http://localhost/", { headers: { accept: "text/html" } }), { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } }, { waitUntil() {}, passThroughOnException() {} });
}

test("server-renders the Legacy Doctor dashboard", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  const html = await response.text();
  assert.match(html, /<title>Legacy Doctor — Media Operations<\/title>/i);
  assert.match(html, /Connected devices/);
  assert.match(html, /This machine/);
  assert.match(html, /AMD Ryzen 7 5800X/);
  assert.match(html, /NVIDIA GeForce RTX 4060/);
  assert.match(html, /Full iPod image verified/);
  assert.match(html, /Apple iPod Shuffle/);
  assert.match(html, /Every iPod disk byte hashed/);
  assert.match(html, /1,015,021,568/);
  assert.match(html, /IMAGE HASHES MATCH/);
  assert.match(html, /Verified local snapshot/);
});

test("keeps device writes gated and the layout responsive", async () => {
  const [page, css, layout] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(page, /remains disabled until device-write safeguards and explicit approval exist/);
  assert.match(page, /Read-only imaging is proven/);
  assert.match(page, /hardware restore remains locked/);
  assert.match(page, /Skip verified duplicates/);
  assert.match(page, /SHA-256 proven/);
  assert.match(page, /Encryption not configured/);
  assert.match(page, /Signing not configured/);
  assert.match(page, /Manage device/);
  assert.match(page, /useMemo/);
  assert.match(page, /setSelected/);
  assert.match(css, /@media\(max-width:760px\)/);
  assert.match(css, /source-types/);
  assert.match(layout, /Legacy Doctor — Media Operations/);
});
