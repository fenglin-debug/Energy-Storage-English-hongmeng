import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { DocumentRef } from '../domain/Models';

const COPY_BUFFER_BYTES = 64 * 1024;

export class FileService {
  private context: common.UIAbilityContext | null = null;

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  requireContext(): common.UIAbilityContext {
    if (this.context === null) throw new Error('FILE_SERVICE_NOT_INITIALIZED');
    return this.context;
  }

  async pickOpen(suffixes: string[]): Promise<DocumentRef | null> {
    const viewPicker = new picker.DocumentViewPicker(this.requireContext());
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = suffixes;
    const selected = await viewPicker.select(options);
    return selected.length === 0 ? null : new DocumentRef(selected[0]);
  }

  async pickSave(fileName: string, suffixes: string[]): Promise<DocumentRef | null> {
    const viewPicker = new picker.DocumentViewPicker(this.requireContext());
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = suffixes;
    const selected = await viewPicker.save(options);
    return selected.length === 0 ? null : new DocumentRef(selected[0]);
  }

  readDocument(document: DocumentRef, maxBytes: number): Uint8Array {
    const file = fs.openSync(document.uri, fs.OpenMode.READ_ONLY);
    try {
      return this.readFd(file.fd, maxBytes);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  readPath(path: string, maxBytes: number): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      return this.readFd(file.fd, maxBytes);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  writeDocument(document: DocumentRef, bytes: Uint8Array): void {
    const file = fs.openSync(document.uri,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      this.writeFd(file.fd, bytes);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  writePath(path: string, bytes: Uint8Array): void {
    const file = fs.openSync(path,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      this.writeFd(file.fd, bytes);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  async rawFile(name: string): Promise<Uint8Array> {
    return await this.requireContext().resourceManager.getRawFileContent(name);
  }

  displayName(document: DocumentRef): string {
    const clean = document.uri.split('?')[0];
    const part = clean.slice(clean.lastIndexOf('/') + 1);
    try { return decodeURIComponent(part); } catch (_) { return part; }
  }

  async mediaDuration(document: DocumentRef): Promise<number> {
    const file = fs.openSync(document.uri, fs.OpenMode.READ_ONLY);
    const extractor = await media.createAVMetadataExtractor();
    try {
      extractor.fdSrc = { fd: file.fd, offset: 0, length: fs.statSync(document.uri).size };
      const metadata = await extractor.fetchMetadata();
      const duration = Number(metadata.duration ?? '0');
      if (!Number.isFinite(duration) || duration <= 0) throw new Error('INVALID_AUDIO');
      return Math.floor(duration);
    } finally {
      await extractor.release();
      fs.closeSync(file.fd);
    }
  }

  tempDirectory(prefix: string): string {
    const path = `${this.requireContext().cacheDir}/${prefix}-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}`;
    fs.mkdirSync(path);
    return path;
  }

  tempFile(prefix: string, extension: string): string {
    return `${this.requireContext().cacheDir}/${prefix}-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}${extension}`;
  }

  ensureDirectory(path: string): void {
    // API 20 returns false for a missing path instead of throwing.
    if (!fs.accessSync(path)) fs.mkdirSync(path, true);
  }

  removeTree(path: string): void {
    try {
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        for (const child of fs.listFileSync(path)) this.removeTree(`${path}/${child}`);
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (_) {
      // Cleanup is best-effort and never masks the operation result.
    }
  }

  copyDocumentToPath(document: DocumentRef, destination: string, maxBytes: number): Uint8Array {
    const bytes = this.readDocument(document, maxBytes);
    this.writePath(destination, bytes);
    return bytes;
  }

  copyPath(source: string, destination: string, maxBytes: number): void {
    this.writePath(destination, this.readPath(source, maxBytes));
  }

  private readFd(fd: number, maxBytes: number): Uint8Array {
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const chunk = new ArrayBuffer(COPY_BUFFER_BYTES);
      // Omitting offset uses and advances the current file pointer. On API 20,
      // an explicit offset of 0 is treated as the beginning of the file.
      const read = fs.readSync(fd, chunk, { length: COPY_BUFFER_BYTES });
      if (read <= 0) break;
      total += read;
      if (total > maxBytes) throw new Error('FILE_TOO_LARGE');
      chunks.push(new Uint8Array(chunk).slice(0, read));
    }
    const output = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      output.set(chunk, offset);
      offset += chunk.length;
    }
    return output;
  }

  private writeFd(fd: number, bytes: Uint8Array): void {
    let offset = 0;
    while (offset < bytes.length) {
      const end = Math.min(offset + COPY_BUFFER_BYTES, bytes.length);
      // Keep the descriptor's current position so consecutive chunks append.
      const written = fs.writeSync(fd, bytes.slice(offset, end).buffer);
      if (written <= 0) throw new Error('FILE_WRITE_FAILED');
      offset += written;
    }
  }
}

export const fileService = new FileService();
