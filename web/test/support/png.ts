/**
 * Enough of the PNG container to interrogate a card, written here rather than depended on.
 *
 * **Why the suite decodes the bytes it serves instead of asking the renderer what it drew.**
 * `@resvg/resvg-js` will hand back `RenderedImage.width`, `.height` and `.pixels`, and every one
 * of those is the renderer's account of its own work. The thing a crawler fetches is the PNG, and
 * the claims the page makes in its `<meta>` tags are claims about that file: that it is a PNG,
 * that it is 1200×630, that there is something on it. An assertion that reads those facts out of
 * the encoded bytes is an assertion about the artifact; one that reads them off the object that
 * produced them is an assertion about the library. This project has shipped the second kind.
 *
 * No dependency: `node:zlib` inflates, and the five filter types are forty lines. Deliberately
 * narrow — it refuses anything that is not the 8-bit RGBA non-interlaced form resvg emits, rather
 * than growing a decoder nobody checks the corners of.
 */
import { inflateSync } from 'node:zlib';

/** The eight bytes every PNG starts with. */
export const PNG_SIGNATURE = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export interface PNGHeader {
  readonly width: number;
  readonly height: number;
  readonly bitDepth: number;
  readonly colorType: number;
  readonly interlace: number;
}

export interface DecodedPNG extends PNGHeader {
  /** Row-major RGBA, four bytes per pixel, `width * height * 4` long. */
  readonly pixels: Uint8Array;
}

export function hasPNGSignature(bytes: Uint8Array): boolean {
  if (bytes.length < PNG_SIGNATURE.length) return false;
  return PNG_SIGNATURE.every((byte, index) => bytes[index] === byte);
}

function u32(bytes: Uint8Array, at: number): number {
  return (
    ((bytes[at] ?? 0) << 24) + ((bytes[at + 1] ?? 0) << 16)
    + ((bytes[at + 2] ?? 0) << 8) + (bytes[at + 3] ?? 0)
  ) >>> 0;
}

/** `[type, data]` for every chunk, in file order. */
function chunks(bytes: Uint8Array): readonly (readonly [string, Uint8Array])[] {
  if (!hasPNGSignature(bytes)) throw new Error('not a PNG: the eight-byte signature is wrong');
  const found: [string, Uint8Array][] = [];
  let at = PNG_SIGNATURE.length;
  while (at + 8 <= bytes.length) {
    const length = u32(bytes, at);
    const type = String.fromCharCode(...bytes.subarray(at + 4, at + 8));
    const start = at + 8;
    if (start + length + 4 > bytes.length) throw new Error(`PNG chunk ${type} runs past the end`);
    found.push([type, bytes.subarray(start, start + length)]);
    at = start + length + 4;
    if (type === 'IEND') break;
  }
  return found;
}

/** IHDR, read out of the encoded file. */
export function pngHeader(bytes: Uint8Array): PNGHeader {
  const ihdr = chunks(bytes).find(([type]) => type === 'IHDR')?.[1];
  if (ihdr === undefined || ihdr.length < 13) throw new Error('the PNG has no usable IHDR');
  return {
    width: u32(ihdr, 0),
    height: u32(ihdr, 4),
    bitDepth: ihdr[8] ?? 0,
    colorType: ihdr[9] ?? 0,
    interlace: ihdr[12] ?? 0,
  };
}

function paeth(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

/** The image, unfiltered into RGBA. Refuses anything but 8-bit RGBA, non-interlaced. */
export function decodePNG(bytes: Uint8Array): DecodedPNG {
  const header = pngHeader(bytes);
  if (header.bitDepth !== 8 || header.colorType !== 6 || header.interlace !== 0) {
    throw new Error(
      `this reader handles 8-bit RGBA non-interlaced PNG only; got bit depth ${header.bitDepth}, `
        + `color type ${header.colorType}, interlace ${header.interlace}`,
    );
  }
  const idat = chunks(bytes).filter(([type]) => type === 'IDAT').map(([, data]) => data);
  if (idat.length === 0) throw new Error('the PNG carries no IDAT');
  const raw = inflateSync(Buffer.concat(idat.map((part) => Buffer.from(part))));

  const bpp = 4;
  const stride = header.width * bpp;
  const expected = (stride + 1) * header.height;
  if (raw.length !== expected) {
    throw new Error(`inflated ${raw.length} bytes, expected ${expected} for ${header.width}×${header.height}`);
  }

  const pixels = new Uint8Array(stride * header.height);
  for (let row = 0; row < header.height; row += 1) {
    const filter = raw[row * (stride + 1)] ?? 0;
    const from = row * (stride + 1) + 1;
    const to = row * stride;
    const above = (row - 1) * stride;
    for (let index = 0; index < stride; index += 1) {
      const x = raw[from + index] ?? 0;
      const a = index >= bpp ? (pixels[to + index - bpp] ?? 0) : 0;
      const b = row > 0 ? (pixels[above + index] ?? 0) : 0;
      const c = row > 0 && index >= bpp ? (pixels[above + index - bpp] ?? 0) : 0;
      let value: number;
      switch (filter) {
        case 0: value = x; break;
        case 1: value = x + a; break;
        case 2: value = x + b; break;
        case 3: value = x + ((a + b) >> 1); break;
        case 4: value = x + paeth(a, b, c); break;
        default: throw new Error(`unknown PNG filter type ${filter} on row ${row}`);
      }
      pixels[to + index] = value & 0xff;
    }
  }
  return { ...header, pixels };
}

export interface Rect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

/** The RGBA of one pixel. */
export function pixelAt(image: DecodedPNG, x: number, y: number): readonly [number, number, number, number] {
  const at = (y * image.width + x) * 4;
  return [
    image.pixels[at] ?? 0,
    image.pixels[at + 1] ?? 0,
    image.pixels[at + 2] ?? 0,
    image.pixels[at + 3] ?? 0,
  ];
}

/** How many pixels in `rect` are within `tolerance` (euclidean, per channel sum of squares) of `rgb`. */
export function countNear(
  image: DecodedPNG,
  rect: Rect,
  rgb: readonly [number, number, number],
  tolerance: number,
): number {
  const limit = tolerance * tolerance;
  let count = 0;
  for (let y = rect.y; y < rect.y + rect.height; y += 1) {
    for (let x = rect.x; x < rect.x + rect.width; x += 1) {
      const [r, g, b] = pixelAt(image, x, y);
      const distance = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2;
      if (distance <= limit) count += 1;
    }
  }
  return count;
}

/** The rightmost x in `rect` holding a pixel within `tolerance` of `rgb`, or -1. */
export function rightmostNear(
  image: DecodedPNG,
  rect: Rect,
  rgb: readonly [number, number, number],
  tolerance: number,
): number {
  const limit = tolerance * tolerance;
  for (let x = rect.x + rect.width - 1; x >= rect.x; x -= 1) {
    for (let y = rect.y; y < rect.y + rect.height; y += 1) {
      const [r, g, b] = pixelAt(image, x, y);
      if ((r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2 <= limit) return x;
    }
  }
  return -1;
}

/** How many distinct RGB triples appear in `rect`. A blank canvas answers 1. */
export function distinctColors(image: DecodedPNG, rect: Rect): number {
  const seen = new Set<number>();
  for (let y = rect.y; y < rect.y + rect.height; y += 1) {
    for (let x = rect.x; x < rect.x + rect.width; x += 1) {
      const [r, g, b] = pixelAt(image, x, y);
      seen.add((r << 16) | (g << 8) | b);
    }
  }
  return seen.size;
}

/**
 * How many pixels in `rect` differ from the pixel to their left by more than `threshold` in luma.
 *
 * **This is the measure that tells text from no text**, and it is here because the obvious one
 * does not work. Three of the card's four text runs are drawn at a `fill-opacity` below 1, so
 * their glyphs are the ink color blended with whatever the gradient is doing underneath — a
 * "count the pixels that are the ink color" test finds nothing in the eyebrow and finds the pale
 * top-left corner of the gradient instead, which is a test that reports text where there is none
 * and no text where there is.
 *
 * A glyph edge is a step. A gradient is, by construction, everywhere smooth: `W1_HERO` is a
 * vertical linear ramp under three wide radials, so consecutive pixels differ by at most a unit or
 * two of luma. Counting steps therefore separates the two with an enormous margin, and it does not
 * care what color the type is or how transparent it is.
 */
export function sharpEdgeCount(image: DecodedPNG, rect: Rect, threshold: number): number {
  const luma = (x: number, y: number): number => {
    const [r, g, b] = pixelAt(image, x, y);
    return 0.299 * r + 0.587 * g + 0.114 * b;
  };
  let count = 0;
  for (let y = rect.y; y < rect.y + rect.height; y += 1) {
    for (let x = rect.x + 1; x < rect.x + rect.width; x += 1) {
      if (Math.abs(luma(x, y) - luma(x - 1, y)) > threshold) count += 1;
    }
  }
  return count;
}

/** The bytes of one horizontal band, for comparing two renders region by region. */
export function band(image: DecodedPNG, rect: Rect): Uint8Array {
  const out = new Uint8Array(rect.width * rect.height * 4);
  let at = 0;
  for (let y = rect.y; y < rect.y + rect.height; y += 1) {
    const from = (y * image.width + rect.x) * 4;
    out.set(image.pixels.subarray(from, from + rect.width * 4), at);
    at += rect.width * 4;
  }
  return out;
}
