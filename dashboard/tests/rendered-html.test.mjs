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
  assert.match(html, /Unified library/);
  assert.match(html, /Backups &amp; recovery/);
  assert.match(html, /Assign drive letter/);
  assert.match(html, /Format media/);
  assert.match(html, /Create disk image/);
  assert.match(html, /Clone drive/);
  assert.match(html, /VHS/);
  assert.match(html, /HDD \/ NVMe/);
  assert.match(html, /Verified hardware snapshot/);
  assert.match(html, /Apple iPod Shuffle/);
  assert.match(html, /10 of 10 hashes matched/);
  assert.match(html, /destructive actions disabled/);
});

test("keeps device writes gated and the layout responsive", async () => {
  const [page, css, layout] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(page, /requires a verified restore point and explicit approval/);
  assert.match(page, /destructive actions disabled/);
  assert.match(page, /useMemo/);
  assert.match(page, /setSelected/);
  assert.match(css, /@media\(max-width:760px\)/);
  assert.match(css, /source-types/);
  assert.match(layout, /Legacy Doctor — Media Operations/);
});
