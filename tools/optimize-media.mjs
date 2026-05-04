#!/usr/bin/env node
/**
 * Resize and recompress podcast cover art under media/, and emit .webp siblings.
 * Skip rules:
 * - If .webp is in git: re-run only when the raster’s last commit is newer than the .webp’s.
 * - If .webp is not in git but exists on disk (local dev): skip when .webp mtime >= raster mtime.
 * Set FORCE_OPTIMIZE_MEDIA=1 to process all raster images regardless.
 *
 * Local: npm install && npm run optimize-media
 * CI: scheduled workflow runs this before Jekyll (fetch-depth 0).
 */
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import sharp from "sharp";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");
const mediaDir = path.join(root, "media");
/** Max edge length; enough for ~2× retina at typical card widths */
const MAX_EDGE = 640;
const extRe = /\.(jpe?g|png)$/i;
const forceAll = process.env.FORCE_OPTIMIZE_MEDIA === "1";

function lastCommitUnixMs(relPosix) {
  try {
    const out = execSync(`git log -1 --format=%ct -- "${relPosix}"`, {
      cwd: root,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    if (!out) return null;
    const sec = parseInt(out, 10);
    if (Number.isNaN(sec)) return null;
    return sec * 1000;
  } catch {
    return null;
  }
}

async function needsProcessing(filePath) {
  if (forceAll) return true;
  const rel = path.relative(root, filePath).split(path.sep).join("/");
  const webpPath = filePath.replace(extRe, ".webp");
  const webpRel = rel.replace(extRe, ".webp");

  const webpCommitMs = lastCommitUnixMs(webpRel);
  const srcCommitMs = lastCommitUnixMs(rel);

  if (webpCommitMs != null && srcCommitMs != null) {
    return srcCommitMs > webpCommitMs;
  }

  try {
    const webpStat = await fs.promises.stat(webpPath);
    const srcStat = await fs.promises.stat(filePath);
    return webpStat.mtimeMs < srcStat.mtimeMs;
  } catch {
    return true;
  }
}

async function processFile(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const buf = await fs.promises.readFile(filePath);
  const pipeline = sharp(buf).rotate().resize(MAX_EDGE, MAX_EDGE, {
    fit: "inside",
    withoutEnlargement: true,
  });
  const tmp = `${filePath}.tmp-opt`;

  if (ext === ".png") {
    await pipeline.png({ compressionLevel: 9, adaptiveFiltering: true }).toFile(tmp);
  } else {
    await pipeline.jpeg({ quality: 82, mozjpeg: true }).toFile(tmp);
  }

  await fs.promises.rename(tmp, filePath);

  const webpPath = filePath.replace(extRe, ".webp");
  await sharp(await fs.promises.readFile(filePath))
    .webp({ quality: 78, effort: 6 })
    .toFile(webpPath);
}

async function main() {
  let names;
  try {
    names = await fs.promises.readdir(mediaDir);
  } catch (e) {
    console.error("Cannot read media/:", e.message);
    process.exit(1);
  }

  let ran = 0;
  let skipped = 0;
  for (const name of names) {
    if (!extRe.test(name)) continue;
    const fp = path.join(mediaDir, name);
    const st = await fs.promises.stat(fp);
    if (!st.isFile()) continue;
    if (!(await needsProcessing(fp))) {
      skipped += 1;
      continue;
    }
    process.stdout.write(`optimize: ${name}\n`);
    await processFile(fp);
    ran += 1;
  }
  if (ran === 0) {
    process.stdout.write(`done (0 updated, ${skipped} skipped).\n`);
  } else {
    process.stdout.write(`done (${ran} updated, ${skipped} skipped).\n`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
