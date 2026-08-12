import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { getNode, HvigorNode } from '@ohos/hvigor';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

interface AssetLock { source: string; destination: string; sha256: string; }

const node = getNode(__filename) as HvigorNode;
node.registerTask({
  name: 'prepareBessAssets',
  run() {
    const root = __dirname;
    const lockPath = path.join(root, 'assets.lock.json');
    const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8')) as { assets: AssetLock[] };
    for (const asset of lock.assets) {
      const source = path.resolve(root, asset.source);
      const destination = path.resolve(root, asset.destination);
      if (!fs.existsSync(source)) throw new Error(`Missing canonical asset: ${source}`);
      const actual = crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex');
      if (actual.toLowerCase() !== asset.sha256.toLowerCase()) {
        throw new Error(`Asset SHA-256 changed; update assets.lock.json intentionally: ${asset.source}`);
      }
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.copyFileSync(source, destination);
      const copied = crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex');
      if (copied !== actual) throw new Error(`Copied asset verification failed: ${destination}`);
    }
  }
});

export default {
  system: appTasks,
  plugins: []
};
