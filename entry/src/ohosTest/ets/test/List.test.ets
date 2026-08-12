import fsrsTests from './Fsrs.test';
import backupCodecTests from './BackupCodec.test';
import productContractTests from './ProductContracts.test';

export default function tests(): void {
  fsrsTests();
  backupCodecTests();
  productContractTests();
}
