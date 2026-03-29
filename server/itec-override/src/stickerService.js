const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PUBLIC_DIR = path.join(__dirname, "../public");
const GENERATED_STICKERS_DIR = path.join(PUBLIC_DIR, "generated-stickers");
const GENERATED_STICKERS_WEB_ROOT = "/generated-stickers";
const HF_IMAGE_MODEL = process.env.HF_IMAGE_MODEL || "ByteDance/SDXL-Lightning";

const STICKER_LIBRARY = Object.freeze([
  {
    id: "bolt-badge",
    name: "Bolt Badge",
    url: "/stickers/bolt-badge.svg",
    kind: "local",
  },
  {
    id: "glitch-star",
    name: "Glitch Star",
    url: "/stickers/glitch-star.svg",
    kind: "local",
  },
  {
    id: "smiley-spray",
    name: "Smiley Spray",
    url: "/stickers/smiley-spray.svg",
    kind: "local",
  },
]);

function getStickerLibrary() {
  return STICKER_LIBRARY.map((item) => ({ ...item }));
}

function ensureGeneratedDir() {
  fs.mkdirSync(GENERATED_STICKERS_DIR, { recursive: true });
}

function extensionForContentType(contentType = "") {
  if (contentType.includes("image/jpeg")) return ".jpg";
  if (contentType.includes("image/webp")) return ".webp";
  return ".png";
}

async function generateStickerFromPrompt(prompt) {
  const normalizedPrompt = typeof prompt === "string" ? prompt.trim() : "";
  if (!normalizedPrompt) {
    return { ok: false, error: "prompt is required" };
  }

  if (!process.env.HF_TOKEN) {
    return {
      ok: false,
      error: "HF_TOKEN is not configured on the backend",
    };
  }

  const response = await fetch(
    `https://router.huggingface.co/hf-inference/models/${encodeURIComponent(HF_IMAGE_MODEL)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.HF_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        inputs: normalizedPrompt,
        parameters: {
          width: 512,
          height: 512,
          negative_prompt: "text, watermark, frame, border, blurry, low quality",
        },
      }),
    }
  );

  if (!response.ok) {
    const message = await response.text();
    return {
      ok: false,
      error: `image generation failed: ${response.status} ${message}`.trim(),
    };
  }

  const arrayBuffer = await response.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);
  const extension = extensionForContentType(response.headers.get("content-type") || "");
  const id = `ai_${Date.now()}_${crypto.randomBytes(4).toString("hex")}`;

  ensureGeneratedDir();
  fs.writeFileSync(path.join(GENERATED_STICKERS_DIR, `${id}${extension}`), buffer);

  return {
    ok: true,
    sticker: {
      id,
      name: normalizedPrompt.slice(0, 48),
      url: `${GENERATED_STICKERS_WEB_ROOT}/${id}${extension}`,
      prompt: normalizedPrompt,
      kind: "generated",
      model: HF_IMAGE_MODEL,
    },
  };
}

module.exports = {
  stickerService: {
    getStickerLibrary,
    generateStickerFromPrompt,
  },
};
