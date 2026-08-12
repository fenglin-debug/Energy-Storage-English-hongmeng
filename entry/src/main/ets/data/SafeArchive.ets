import { zlib } from '@kit.BasicServicesKit';
import { utf8, utf8String, readU16LE, readU32LE, writeU16LE, writeU32LE } from './Binary';

export interface ArchiveLimits {
  maxContainerBytes: number;
  maxEntryBytes: number;
  maxTotalBytes: number;
  maxEntries: number;
}

export interface ArchiveEntry {
  name: string;
  compressedSize: number;
  uncompressedSize: number;
  method: number;
  crc32: number;
  localHeaderOffset: number;
}

export class SafeArchive {
  inspect(bytes: Uint8Array, limits: ArchiveLimits): ArchiveEntry[] {
    if (bytes.length > limits.maxContainerBytes) throw new Error('ARCHIVE_TOO_LARGE');
    if (bytes.length < 22) throw new Error('ZIP_EOCD_MISSING');
    const eocd = this.findEndOfCentralDirectory(bytes);
    if (eocd + 22 > bytes.length || readU16LE(bytes, eocd + 4) !== 0 ||
      readU16LE(bytes, eocd + 6) !== 0 || readU16LE(bytes, eocd + 8) !== readU16LE(bytes, eocd + 10)) {
      throw new Error('MULTI_DISK_ZIP_UNSUPPORTED');
    }
    const entryCount = readU16LE(bytes, eocd + 10);
    const centralSize = readU32LE(bytes, eocd + 12);
    const centralOffset = readU32LE(bytes, eocd + 16);
    if (entryCount > limits.maxEntries || centralOffset + centralSize > eocd) {
      throw new Error('INVALID_ZIP_DIRECTORY');
    }
    const names = new Set<string>();
    const entries: ArchiveEntry[] = [];
    let total = 0;
    let cursor = centralOffset;
    for (let index = 0; index < entryCount; index++) {
      if (cursor + 46 > bytes.length) throw new Error('INVALID_ZIP_ENTRY');
      if (readU32LE(bytes, cursor) !== 0x02014B50) throw new Error('INVALID_ZIP_ENTRY');
      const flags = readU16LE(bytes, cursor + 8);
      const method = readU16LE(bytes, cursor + 10);
      const crc = readU32LE(bytes, cursor + 16);
      const compressed = readU32LE(bytes, cursor + 20);
      const uncompressed = readU32LE(bytes, cursor + 24);
      const nameLength = readU16LE(bytes, cursor + 28);
      const extraLength = readU16LE(bytes, cursor + 30);
      const commentLength = readU16LE(bytes, cursor + 32);
      const externalAttributes = readU32LE(bytes, cursor + 38);
      const localHeaderOffset = readU32LE(bytes, cursor + 42);
      if (cursor + 46 + nameLength + extraLength + commentLength > bytes.length) throw new Error('INVALID_ZIP_ENTRY');
      const name = utf8String(bytes.slice(cursor + 46, cursor + 46 + nameLength));
      this.validatePath(name);
      if (names.has(name)) throw new Error(`DUPLICATE_ENTRY:${name}`);
      if ((flags & 0x1) !== 0 || (method !== 0 && method !== 8)) throw new Error('UNSUPPORTED_ZIP_ENTRY');
      const unixMode = (externalAttributes >>> 16) & 0xFFFF;
      if ((unixMode & 0xF000) === 0xA000) throw new Error('ZIP_SYMLINK_REJECTED');
      this.validateLocalHeader(bytes, localHeaderOffset, name, method, compressed, centralOffset);
      if (uncompressed > limits.maxEntryBytes) throw new Error(`ENTRY_TOO_LARGE:${name}`);
      total += uncompressed;
      if (total > limits.maxTotalBytes) throw new Error('ZIP_BOMB_REJECTED');
      names.add(name);
      entries.push({ name: name, compressedSize: compressed, uncompressedSize: uncompressed,
        method: method, crc32: crc, localHeaderOffset: localHeaderOffset });
      cursor += 46 + nameLength + extraLength + commentLength;
      if (cursor > centralOffset + centralSize) throw new Error('INVALID_ZIP_DIRECTORY');
    }
    return entries;
  }

  async extractValidated(zipPath: string, destinationPath: string,
    bytes: Uint8Array, limits: ArchiveLimits): Promise<ArchiveEntry[]> {
    const entries = this.inspect(bytes, limits);
    await zlib.decompressFile(zipPath, destinationPath, {});
    return entries;
  }

  createStored(entries: Map<string, Uint8Array>): Uint8Array {
    const local: number[] = [];
    const central: number[] = [];
    let localOffset = 0;
    entries.forEach((data: Uint8Array, name: string) => {
      this.validatePath(name);
      const nameBytes = utf8(name);
      const crc = this.crc32(data);
      writeU32LE(local, 0x04034B50);
      writeU16LE(local, 20);
      writeU16LE(local, 0x0800);
      writeU16LE(local, 0);
      writeU16LE(local, 0);
      writeU16LE(local, 0);
      writeU32LE(local, crc);
      writeU32LE(local, data.length);
      writeU32LE(local, data.length);
      writeU16LE(local, nameBytes.length);
      writeU16LE(local, 0);
      this.append(local, nameBytes);
      this.append(local, data);

      writeU32LE(central, 0x02014B50);
      writeU16LE(central, 20);
      writeU16LE(central, 20);
      writeU16LE(central, 0x0800);
      writeU16LE(central, 0);
      writeU16LE(central, 0);
      writeU16LE(central, 0);
      writeU32LE(central, crc);
      writeU32LE(central, data.length);
      writeU32LE(central, data.length);
      writeU16LE(central, nameBytes.length);
      writeU16LE(central, 0);
      writeU16LE(central, 0);
      writeU16LE(central, 0);
      writeU16LE(central, 0);
      writeU32LE(central, 0);
      writeU32LE(central, localOffset);
      this.append(central, nameBytes);
      localOffset = local.length;
    });
    const centralOffset = local.length;
    this.append(local, new Uint8Array(central));
    writeU32LE(local, 0x06054B50);
    writeU16LE(local, 0);
    writeU16LE(local, 0);
    writeU16LE(local, entries.size);
    writeU16LE(local, entries.size);
    writeU32LE(local, central.length);
    writeU32LE(local, centralOffset);
    writeU16LE(local, 0);
    return new Uint8Array(local);
  }

  readStoredEntry(bytes: Uint8Array, entry: ArchiveEntry): Uint8Array {
    if (entry.method !== 0) throw new Error('ENTRY_IS_COMPRESSED');
    const nameLength = readU16LE(bytes, entry.localHeaderOffset + 26);
    const extraLength = readU16LE(bytes, entry.localHeaderOffset + 28);
    const start = entry.localHeaderOffset + 30 + nameLength + extraLength;
    return bytes.slice(start, start + entry.uncompressedSize);
  }

  private validatePath(name: string): void {
    if (name.length === 0 || name.startsWith('/') || name.startsWith('\\') ||
      name.includes('\\') || name.includes('..') || new RegExp('^[A-Za-z]:').test(name) || name.includes('\0')) {
      throw new Error(`INVALID_ZIP_PATH:${name}`);
    }
  }

  private validateLocalHeader(bytes: Uint8Array, offset: number, centralName: string,
    method: number, compressedSize: number, centralOffset: number): void {
    if (offset + 30 > bytes.length || readU32LE(bytes, offset) !== 0x04034B50) throw new Error('INVALID_LOCAL_HEADER');
    const flags = readU16LE(bytes, offset + 6);
    const localMethod = readU16LE(bytes, offset + 8);
    const nameLength = readU16LE(bytes, offset + 26);
    const extraLength = readU16LE(bytes, offset + 28);
    if ((flags & 0x1) !== 0 || localMethod !== method || offset + 30 + nameLength + extraLength > bytes.length) {
      throw new Error('LOCAL_HEADER_MISMATCH');
    }
    const localName = utf8String(bytes.slice(offset + 30, offset + 30 + nameLength));
    this.validatePath(localName);
    if (localName !== centralName) throw new Error('LOCAL_HEADER_NAME_MISMATCH');
    if (offset + 30 + nameLength + extraLength + compressedSize > centralOffset) throw new Error('ZIP_DATA_OUT_OF_BOUNDS');
  }

  private findEndOfCentralDirectory(bytes: Uint8Array): number {
    const minimum = Math.max(0, bytes.length - 65_557);
    for (let cursor = bytes.length - 22; cursor >= minimum; cursor--) {
      if (readU32LE(bytes, cursor) === 0x06054B50) return cursor;
    }
    throw new Error('ZIP_EOCD_MISSING');
  }

  private crc32(bytes: Uint8Array): number {
    let crc = 0xFFFFFFFF;
    for (const byte of bytes) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) {
        crc = (crc & 1) !== 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  private append(output: number[], bytes: Uint8Array): void {
    for (const byte of bytes) output.push(byte);
  }
}

export const safeArchive = new SafeArchive();
