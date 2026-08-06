#!/usr/bin/env node
/**
 * Mosaic grid of all podcast cover art for Facebook / Open Graph (1200×630).
 *
 * Usage: node tools/generate-social-grid.mjs
 * Output: assets/img/social.jpg (+ docs/assets/img/social.jpg)
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import sharp from "sharp";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, "..");
const POSTS_DIR = path.join(ROOT, "_posts", "podcasts");
const WIDTH = 1200;
const HEIGHT = 630;
const COLS = 11;
const ROWS = 11;
const BG = { r: 29, g: 29, b: 29 };

function collectCoverPaths() {
  const files = fs.readdirSync(POSTS_DIR).filter((f) => f.endsWith(".md"));
  const covers = new Set();

  for (const file of files) {
    const text = fs.readFileSync(path.join(POSTS_DIR, file), "utf8");
    const match = text.match(/^cover_image:\s*(\S+)/m);
    if (!match) continue;
    const rel = match[1].replace(/^["']|["']$/g, "");
    if (!rel.startsWith("/media/")) continue;
    const abs = path.join(ROOT, "docs", rel.replace(/^\//, ""));
    if (fs.existsSync(abs)) covers.add(abs);
  }

  return [...covers].sort();
}

async function cellImage(filePath, cellW, cellH) {
  return sharp(filePath)
    .resize(cellW, cellH, { fit: "cover", position: "centre" })
    .jpeg({ quality: 82, mozjpeg: true })
    .toBuffer();
}

async function main() {
  const covers = collectCoverPaths();
  if (covers.length === 0) {
    console.error("No cover images found.");
    process.exit(1);
  }

  const cellW = Math.floor(WIDTH / COLS);
  const cellH = Math.floor(HEIGHT / ROWS);
  const gridW = cellW * COLS;
  const gridH = cellH * ROWS;
  const offsetX = Math.floor((WIDTH - gridW) / 2);
  const offsetY = Math.floor((HEIGHT - gridH) / 2);

  console.log(`Compositing ${covers.length} covers into ${COLS}×${ROWS} grid (${WIDTH}×${HEIGHT})…`);

  const composites = [];
  for (let i = 0; i < covers.length && i < COLS * ROWS; i++) {
    const col = i % COLS;
    const row = Math.floor(i / COLS);
    const buf = await cellImage(covers[i], cellW, cellH);
    composites.push({
      input: buf,
      left: offsetX + col * cellW,
      top: offsetY + row * cellH,
    });
  }

  const outBuf = await sharp({
    create: {
      width: WIDTH,
      height: HEIGHT,
      channels: 3,
      background: BG,
    },
  })
    .composite(composites)
    .jpeg({ quality: 88, mozjpeg: true, progressive: true })
    .toBuffer();

  const targets = [
    path.join(ROOT, "assets", "img", "social.jpg"),
    path.join(ROOT, "docs", "assets", "img", "social.jpg"),
  ];

  for (const target of targets) {
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, outBuf);
    console.log(`Wrote ${path.relative(ROOT, target)} (${outBuf.length} bytes)`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
