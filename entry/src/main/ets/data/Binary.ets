import { buffer } from '@kit.ArkTS';

export function utf8(value: string): Uint8Array {
  const encoded = buffer.from(value, 'utf-8');
  // API 20 Buffer can expose a backing ArrayBuffer whose reported offset is
  // not safe to pass into a Uint8Array view. Copy bytes explicitly instead.
  const output = new Uint8Array(encoded.length);
  for (let index = 0; index < encoded.length; index++) output[index] = encoded[index];
  return output;
}

export function utf8String(value: Uint8Array): string {
  return buffer.from(value).toString('utf-8');
}

export function base64(value: Uint8Array): string {
  return buffer.from(value).toString('base64');
}

export function fromBase64(value: string): Uint8Array {
  const decoded = buffer.from(value, 'base64');
  const output = new Uint8Array(decoded.length);
  for (let index = 0; index < decoded.length; index++) output[index] = decoded[index];
  return output;
}

export function concatBytes(parts: Uint8Array[]): Uint8Array {
  let length = 0;
  for (const part of parts) length += part.length;
  const output = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

export function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let different = 0;
  for (let index = 0; index < left.length; index++) {
    different |= left[index] ^ right[index];
  }
  return different === 0;
}

export function hex(value: Uint8Array): string {
  let output = '';
  for (const byte of value) output += byte.toString(16).padStart(2, '0');
  return output;
}

export function readU16LE(value: Uint8Array, offset: number): number {
  return value[offset] | (value[offset + 1] << 8);
}

export function readU32LE(value: Uint8Array, offset: number): number {
  return (value[offset] | (value[offset + 1] << 8) |
    (value[offset + 2] << 16) | (value[offset + 3] << 24)) >>> 0;
}

export function writeU16LE(output: number[], value: number): void {
  output.push(value & 0xFF, (value >>> 8) & 0xFF);
}

export function writeU32LE(output: number[], value: number): void {
  output.push(value & 0xFF, (value >>> 8) & 0xFF, (value >>> 16) & 0xFF, (value >>> 24) & 0xFF);
}
