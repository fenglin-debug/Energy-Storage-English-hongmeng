import { CryptoService } from './CryptoService';
import { FileService } from './FileService';
import {
  ArticlePackageManifest, AudioManifest, PackAudioAsset, PackDialoguePair, PackDialogueTurn,
  PackExample, PackFile, PackManifest, PackPairPhrase, PackPairWord, PackPhrase, PackScenario, PackVocabulary
} from './PackageModels';
import { safeArchive, ArchiveLimits } from './SafeArchive';
import { utf8String } from './Binary';

const CORPUS_REQUIRED: string[] = [
  'data/vocabulary.json', 'data/phrases.json', 'data/examples.json', 'data/scenarios.json',
  'data/dialogue_turns.json', 'data/dialogue_pairs.json', 'data/dialogue_pair_words.json',
  'data/dialogue_pair_phrases.json', 'data/audio_manifest.json'
];
export const CORPUS_LIMITS: ArchiveLimits = {
  maxContainerBytes: 256 * 1024 * 1024, maxEntryBytes: 64 * 1024 * 1024,
  maxTotalBytes: 512 * 1024 * 1024, maxEntries: 20_000
};
export const ARTICLE_LIMITS: ArchiveLimits = {
  maxContainerBytes: 50 * 1024 * 1024, maxEntryBytes: 32 * 1024 * 1024,
  maxTotalBytes: 100 * 1024 * 1024, maxEntries: 2_000
};

export interface ValidatedCorpus {
  manifest: PackManifest; vocabulary: PackVocabulary[]; phrases: PackPhrase[]; examples: PackExample[];
  scenarios: PackScenario[]; turns: PackDialogueTurn[]; pairs: PackDialoguePair[];
  pairWords: PackPairWord[]; pairPhrases: PackPairPhrase[]; audioAssets: PackAudioAsset[];
  extractedPath: string;
}

export interface ValidatedArticlePackage { manifest: ArticlePackageManifest; extractedPath: string; }

export class PackageValidator {
  private readonly files: FileService;
  private readonly crypto: CryptoService;
  constructor(files: FileService, crypto: CryptoService) { this.files = files; this.crypto = crypto; }

  async corpus(bytes: Uint8Array, zipPath: string, extractedPath: string): Promise<ValidatedCorpus> {
    const entries = await safeArchive.extractValidated(zipPath, extractedPath, bytes, CORPUS_LIMITS);
    const names = new Set<string>(entries.map(entry => entry.name));
    this.requireEntries(names, ['manifest.json', 'checksums.sha256'].concat(CORPUS_REQUIRED));
    const checksums = await this.verifyChecksums(names, extractedPath);
    const manifest = this.json<PackManifest>(extractedPath, 'manifest.json', 1024 * 1024);
    if (manifest.schemaVersion < 2 || manifest.schemaVersion > 3) throw new Error('UNSUPPORTED_CORPUS_SCHEMA');
    if (manifest.minimumAppVersionCode > 3) throw new Error('APP_VERSION_TOO_OLD');
    const listed = new Map<string, PackFile>();
    for (const item of manifest.dataFiles) listed.set(item.path, item);
    checksums.forEach((hash, path) => {
      if (path === 'manifest.json') return;
      const item = listed.get(path);
      if (item === undefined || item.sha256.toLowerCase() !== hash) throw new Error(`MANIFEST_HASH_MISMATCH:${path}`);
      const actualSize = this.files.readPath(`${extractedPath}/${path}`, 64 * 1024 * 1024).length;
      if (item.sizeBytes !== actualSize) throw new Error(`MANIFEST_SIZE_MISMATCH:${path}`);
    });

    const vocabulary = this.json<PackVocabulary[]>(extractedPath, CORPUS_REQUIRED[0], 32 * 1024 * 1024);
    const phrases = this.json<PackPhrase[]>(extractedPath, CORPUS_REQUIRED[1], 32 * 1024 * 1024);
    const examples = this.json<PackExample[]>(extractedPath, CORPUS_REQUIRED[2], 32 * 1024 * 1024);
    const scenarios = this.json<PackScenario[]>(extractedPath, CORPUS_REQUIRED[3], 16 * 1024 * 1024);
    const turns = this.json<PackDialogueTurn[]>(extractedPath, CORPUS_REQUIRED[4], 32 * 1024 * 1024);
    const pairs = this.json<PackDialoguePair[]>(extractedPath, CORPUS_REQUIRED[5], 32 * 1024 * 1024);
    const pairWords = this.json<PackPairWord[]>(extractedPath, CORPUS_REQUIRED[6], 16 * 1024 * 1024);
    const pairPhrases = this.json<PackPairPhrase[]>(extractedPath, CORPUS_REQUIRED[7], 16 * 1024 * 1024);
    const audioAssets = this.json<AudioManifest>(extractedPath, CORPUS_REQUIRED[8], 16 * 1024 * 1024).assets;
    this.validateCorpusCounts(manifest, vocabulary, phrases, examples, scenarios, turns, pairs, audioAssets);
    this.unique(vocabulary.map(item => item.id)); this.unique(vocabulary.map(item => item.normalizedTerm));
    this.unique(phrases.map(item => item.id)); this.unique(examples.map(item => item.id));
    this.unique(scenarios.map(item => item.id)); this.unique(turns.map(item => item.id));
    this.unique(pairs.map(item => item.id)); this.unique(audioAssets.map(item => item.id));
    this.validateCorpusRelationships(vocabulary, phrases, examples, scenarios, turns, pairs, pairWords, pairPhrases, audioAssets, names);
    return { manifest, vocabulary, phrases, examples, scenarios, turns, pairs, pairWords, pairPhrases,
      audioAssets, extractedPath };
  }

  async articles(bytes: Uint8Array, zipPath: string, extractedPath: string): Promise<ValidatedArticlePackage> {
    const entries = await safeArchive.extractValidated(zipPath, extractedPath, bytes, ARTICLE_LIMITS);
    const names = new Set<string>(entries.map(entry => entry.name));
    this.requireEntries(names, ['manifest.json', 'checksums.sha256']);
    await this.verifyChecksums(names, extractedPath);
    const manifest = this.json<ArticlePackageManifest>(extractedPath, 'manifest.json', 4 * 1024 * 1024);
    if (manifest.schemaVersion < 1 || manifest.schemaVersion > 2 || manifest.packageId !== 'bess-article') {
      throw new Error('UNSUPPORTED_ARTICLE_SCHEMA');
    }
    this.unique(manifest.articles.map(article => article.id));
    for (const article of manifest.articles) {
      if (article.title.trim().length === 0 || article.topic.trim().length === 0 || article.paragraphs.length === 0) throw new Error('INVALID_ARTICLE');
      if (article.durationMs <= 0 || article.durationMs > 30 * 60 * 1000) throw new Error('INVALID_ARTICLE_DURATION');
      if (article.contentScope !== 'BESS' && article.contentScope !== 'UNSPECIFIED') throw new Error('INVALID_CONTENT_SCOPE');
      if (article.audioFile !== `audio/${article.id}.m4a` || !names.has(article.audioFile)) throw new Error('ARTICLE_AUDIO_MISSING');
      for (const paragraph of article.paragraphs) {
        if (paragraph.textEn.trim().length === 0 || paragraph.textZh.trim().length === 0) throw new Error('INVALID_ARTICLE_PARAGRAPH');
        if (manifest.schemaVersion >= 2 && (paragraph.startMs === null || paragraph.startMs === undefined ||
          paragraph.endMs === null || paragraph.endMs === undefined || paragraph.startMs < 0 ||
          paragraph.endMs <= paragraph.startMs || paragraph.endMs > article.durationMs)) throw new Error('INVALID_ARTICLE_CUES');
      }
    }
    return { manifest, extractedPath };
  }

  private async verifyChecksums(names: Set<string>, root: string): Promise<Map<string, string>> {
    const text = utf8String(this.files.readPath(`${root}/checksums.sha256`, 4 * 1024 * 1024));
    const checksums = new Map<string, string>();
    for (const rawLine of text.split(new RegExp('\\r?\\n'))) {
      const line = rawLine.trim(); if (line.length === 0) continue;
      const match = new RegExp('^([0-9a-fA-F]{64})\\s+(.+)$').exec(line);
      if (match === null || checksums.has(match[2])) throw new Error('INVALID_CHECKSUM_FILE');
      checksums.set(match[2], match[1].toLowerCase());
    }
    for (const name of names) {
      if (name === 'checksums.sha256' || name.endsWith('/')) continue;
      const expected = checksums.get(name);
      if (expected === undefined) throw new Error(`CHECKSUM_NOT_LISTED:${name}`);
      const bytes = this.files.readPath(`${root}/${name}`, 64 * 1024 * 1024);
      if ((await this.crypto.sha256(bytes)).toLowerCase() !== expected) throw new Error(`CHECKSUM_MISMATCH:${name}`);
    }
    checksums.forEach((_hash, name) => {
      if (!names.has(name)) throw new Error(`CHECKSUM_ENTRY_MISSING:${name}`);
    });
    return checksums;
  }

  private validateCorpusCounts(m: PackManifest, v: PackVocabulary[], p: PackPhrase[], e: PackExample[],
    s: PackScenario[], t: PackDialogueTurn[], d: PackDialoguePair[], a: PackAudioAsset[]): void {
    if (m.counts.vocabulary !== v.length || m.counts.phrases !== p.length || m.counts.examples !== e.length ||
      m.counts.scenarios !== s.length || m.counts.dialogueTurns !== t.length ||
      m.counts.dialoguePairs !== d.length || m.counts.audioAssets !== a.length) throw new Error('MANIFEST_COUNTS_MISMATCH');
  }

  private validateCorpusRelationships(vocabulary: PackVocabulary[], phrases: PackPhrase[], examples: PackExample[],
    scenarios: PackScenario[], turns: PackDialogueTurn[], pairs: PackDialoguePair[], pairWords: PackPairWord[],
    pairPhrases: PackPairPhrase[], assets: PackAudioAsset[], names: Set<string>): void {
    if (vocabulary.some(item => item.id.startsWith('WIND-') || item.contentSource === 'WIND')) throw new Error('WIND_CONTENT_FORBIDDEN');
    const scenarioIds = new Set<string>(scenarios.map(item => item.id));
    const turnById = new Map<string, PackDialogueTurn>();
    for (const turn of turns) turnById.set(turn.id, turn);
    const grouped = new Map<string, PackDialogueTurn[]>();
    for (const turn of turns) {
      if (!scenarioIds.has(turn.scenarioId)) throw new Error('ORPHAN_TURN');
      const group = grouped.get(turn.scenarioId) ?? []; group.push(turn); grouped.set(turn.scenarioId, group);
      if (turn.audioAssetId === null || turn.audioAssetId === undefined || turn.audioAssetId.length === 0) throw new Error('TURN_AUDIO_MISSING');
    }
    grouped.forEach(group => {
      group.sort((a, b) => a.turnNo - b.turnNo);
      group.forEach((turn, index) => {
        if (turn.turnNo !== index + 1 || turn.speaker !== (index % 2 === 0 ? 'CUSTOMER' : 'SALES_ENGINEER')) throw new Error('INVALID_DIALOGUE_ALTERNATION');
      });
    });
    const pairIds = new Set<string>(pairs.map(item => item.id)); const wordIds = new Set<string>(vocabulary.map(item => item.id));
    const phraseIds = new Set<string>(phrases.map(item => item.id));
    for (const pair of pairs) {
      const customer = turnById.get(pair.customerTurnId); const sales = turnById.get(pair.salesTurnId);
      if (customer === undefined || sales === undefined || customer.speaker !== 'CUSTOMER' ||
        sales.speaker !== 'SALES_ENGINEER' || sales.turnNo !== customer.turnNo + 1 ||
        pair.referenceCoreEn.trim().length === 0 || pair.referenceChineseHint.trim().length === 0 ||
        pair.formalAlternatives.length < 2) throw new Error('INVALID_DIALOGUE_PAIR');
    }
    if (pairWords.some(item => !pairIds.has(item.pairId) || !wordIds.has(item.wordId)) ||
      pairPhrases.some(item => !pairIds.has(item.pairId) || !phraseIds.has(item.phraseId))) throw new Error('INVALID_PAIR_REFERENCE');
    for (const phrase of phrases) if (!phrase.textEn || !phrase.textZh || !phrase.audioAssetId) throw new Error('INVALID_PHRASE');
    for (const example of examples) if (!example.textEn || !example.textZh || !example.audioAssetId) throw new Error('INVALID_EXAMPLE');
    for (const word of vocabulary) if (1 + examples.filter(item => item.linkedTermIds.includes(word.id)).length < 2) throw new Error('WORD_EXAMPLES_MISSING');
    for (const phrase of phrases) if (examples.filter(item => item.linkedTermIds.includes(phrase.id)).length < 2) throw new Error('PHRASE_EXAMPLES_MISSING');
    for (const asset of assets) if (!names.has(asset.relativePath)) throw new Error(`AUDIO_MISSING:${asset.id}`);
  }

  private json<T>(root: string, relative: string, maxBytes: number): T {
    const text = utf8String(this.files.readPath(`${root}/${relative}`, maxBytes));
    this.validateJsonDepth(text, 32);
    return JSON.parse(text) as T;
  }
  private requireEntries(names: Set<string>, required: string[]): void {
    for (const name of required) if (!names.has(name)) throw new Error(`MISSING_ENTRY:${name}`);
  }
  private unique(values: string[]): void {
    const seen = new Set<string>(); for (const value of values) { if (!value || seen.has(value)) throw new Error(`DUPLICATE_ID:${value}`); seen.add(value); }
  }
  private validateJsonDepth(text: string, maximum: number): void {
    let depth = 0; let inString = false; let escaped = false;
    for (const char of text) {
      if (inString) {
        if (escaped) escaped = false; else if (char === '\\') escaped = true; else if (char === '"') inString = false;
      } else if (char === '"') inString = true;
      else if (char === '{' || char === '[') { depth++; if (depth > maximum) throw new Error('JSON_TOO_DEEP'); }
      else if (char === '}' || char === ']') { depth--; if (depth < 0) throw new Error('INVALID_JSON'); }
    }
    if (depth !== 0 || inString) throw new Error('INVALID_JSON');
  }
}
