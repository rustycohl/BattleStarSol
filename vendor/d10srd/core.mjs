const encoder = new TextEncoder();
const decoder = new TextDecoder();

function canonicalize(value) {
  if (value === null) {
    return "null";
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => {
      if (item === undefined) {
        throw new TypeError("Undefined values are not canonical data.");
      }
      return canonicalize(item);
    }).join(",")}]`;
  }

  switch (typeof value) {
    case "string":
      return JSON.stringify(value);
    case "boolean":
      return value ? "true" : "false";
    case "number":
      if (!Number.isFinite(value)) {
        throw new TypeError("Non-finite numbers are not canonical data.");
      }
      return Object.is(value, -0) ? "0" : JSON.stringify(value);
    case "object": {
      const prototype = Object.getPrototypeOf(value);
      if (prototype !== Object.prototype && prototype !== null) {
        throw new TypeError("Only plain objects are canonical data.");
      }

      const keys = Object.keys(value).sort();
      return `{${keys.map((key) => {
        if (value[key] === undefined) {
          throw new TypeError(`Undefined value at key: ${key}`);
        }
        return `${JSON.stringify(key)}:${canonicalize(value[key])}`;
      }).join(",")}}`;
    }
    default:
      throw new TypeError(`Unsupported canonical value: ${typeof value}`);
  }
}
export function stableStringify(value) {
  return canonicalize(value);
}

export function canonicalBytes(value) {
  return encoder.encode(stableStringify(value));
}

export function utf8Bytes(value) {
  return encoder.encode(String(value));
}

export function utf8Text(value) {
  return decoder.decode(value);
}

export function bytesToHex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function hexToBytes(hex) {
  if (!/^[0-9a-f]*$/i.test(hex) || hex.length % 2 !== 0) {
    throw new TypeError("Expected an even-length hexadecimal string.");
  }
  return Uint8Array.from(hex.match(/.{2}/g) ?? [], (pair) => Number.parseInt(pair, 16));
}

export function bytesToBase64(bytes) {
  if (typeof Buffer !== "undefined") {
    return Buffer.from(bytes).toString("base64");
  }

  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

export function base64ToBytes(value) {
  if (typeof Buffer !== "undefined") {
    return new Uint8Array(Buffer.from(value, "base64"));
  }

  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function asBytes(value) {
  if (typeof value === "string") {
    return utf8Bytes(value);
  }
  if (value instanceof Uint8Array) {
    return value;
  }
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  throw new TypeError("Digest input must be text or bytes.");
}

export async function sha256Bytes(value) {
  const digest = await globalThis.crypto.subtle.digest("SHA-256", asBytes(value));
  return new Uint8Array(digest);
}

export async function sha256Hex(value) {
  return bytesToHex(await sha256Bytes(value));
}

export async function digestObject(value) {
  return sha256Hex(canonicalBytes(value));
}

export function randomHex(byteLength = 16) {
  if (!Number.isInteger(byteLength) || byteLength < 1) {
    throw new RangeError("byteLength must be a positive integer.");
  }
  const bytes = new Uint8Array(byteLength);
  globalThis.crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
}

export async function deterministicIndex(seed, label, size) {
  if (!Number.isInteger(size) || size < 1 || size > 256) {
    throw new RangeError("size must be an integer from 1 through 256.");
  }

  const ceiling = 256 - (256 % size);
  for (let counter = 0; counter < 1024; counter += 1) {
    const block = await sha256Bytes(`${seed}|${label}|${counter}`);
    for (const byte of block) {
      if (byte < ceiling) {
        return byte % size;
      }
    }
  }
  throw new Error("Unable to derive a deterministic index.");
}

export async function deterministicD10(seed, label) {
  return (await deterministicIndex(seed, label, 10)) + 1;
}

export function cloneCanonical(value) {
  return JSON.parse(stableStringify(value));
}
