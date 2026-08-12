import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { concatBytes, hex } from './Binary';

const GCM_NONCE_BYTES = 12;
const GCM_TAG_BYTES = 16;

export class CryptoService {
  random(length: number): Uint8Array {
    return cryptoFramework.createRandom().generateRandomSync(length).data;
  }

  async sha256Bytes(input: Uint8Array): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: input });
    const digest = await md.digest();
    return digest.data;
  }

  async sha256(input: Uint8Array): Promise<string> {
    return hex(await this.sha256Bytes(input));
  }

  async deriveKey(password: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
    const normalized = password.normalize('NFC');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: normalized,
      salt: salt,
      iterations: iterations,
      keySize: 32
    };
    return (await cryptoFramework.createKdf('PBKDF2|SHA256').generateSecret(spec)).data;
  }

  async encryptAesGcm(plain: Uint8Array, password: string, salt: Uint8Array,
    nonce: Uint8Array, iterations: number, aad: Uint8Array): Promise<Uint8Array> {
    if (nonce.length !== GCM_NONCE_BYTES) throw new Error('INVALID_NONCE');
    const key = await this.deriveKey(password, salt, iterations);
    try {
      const keyBlob: cryptoFramework.DataBlob = { data: key };
      const symKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey(keyBlob);
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: nonce },
        aad: { data: aad },
        authTag: { data: new Uint8Array(GCM_TAG_BYTES) },
        algName: 'GcmParamsSpec'
      };
      const cipher = cryptoFramework.createCipher('AES256|GCM');
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
      const encrypted = await cipher.update({ data: plain });
      params.authTag = await cipher.doFinal(null);
      return concatBytes([encrypted.data, params.authTag.data]);
    } finally {
      key.fill(0);
    }
  }

  async decryptAesGcm(cipherTextAndTag: Uint8Array, password: string, salt: Uint8Array,
    nonce: Uint8Array, iterations: number, aad: Uint8Array): Promise<Uint8Array> {
    if (nonce.length !== GCM_NONCE_BYTES || cipherTextAndTag.length < GCM_TAG_BYTES) {
      throw new Error('INVALID_GCM_INPUT');
    }
    const cipherText = cipherTextAndTag.slice(0, cipherTextAndTag.length - GCM_TAG_BYTES);
    const tag = cipherTextAndTag.slice(cipherTextAndTag.length - GCM_TAG_BYTES);
    const key = await this.deriveKey(password, salt, iterations);
    try {
      const symKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: key });
      const params: cryptoFramework.GcmParamsSpec = {
        iv: { data: nonce },
        aad: { data: aad },
        authTag: { data: tag },
        algName: 'GcmParamsSpec'
      };
      const cipher = cryptoFramework.createCipher('AES256|GCM');
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const plain = await cipher.update({ data: cipherText });
      await cipher.doFinal(null);
      return plain.data;
    } finally {
      key.fill(0);
    }
  }
}

export const cryptoService = new CryptoService();
