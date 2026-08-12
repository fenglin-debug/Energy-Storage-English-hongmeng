import { describe, expect, it } from '@ohos/hypium';
import {
  DIRECT_AUDIO_EXTENSIONS, MAX_LOCAL_AUDIO_BYTES, MAX_LOCAL_AUDIO_DURATION_MS,
  MAX_SUBTITLE_BYTES, MAX_SUBTITLE_CUES, stableLocalArticleId
} from '../../../main/ets/data/ArticleRepositoryImpl';
import { DEFAULT_SETTINGS, DialogueSelfRating, VocabularyAssessment } from '../../../main/ets/domain/Models';

export default function productContractTests(): void {
  describe('Android aligned product contracts', () => {
    it('uses the three Android playback speeds and daily target', 0, () => {
      expect(DEFAULT_SETTINGS.playbackSpeed).assertEqual(1.0);
      expect(DEFAULT_SETTINGS.dailyNewWordTarget).assertEqual(15);
    });

    it('uses three vocabulary and scenario self-ratings', 0, () => {
      expect(Object.keys(VocabularyAssessment).length).assertEqual(3);
      expect(Object.keys(DialogueSelfRating).length).assertEqual(3);
    });

    it('keeps direct import security limits exact', 0, () => {
      expect(DIRECT_AUDIO_EXTENSIONS.join(',')).assertEqual('m4a,mp3,wav');
      expect(MAX_LOCAL_AUDIO_BYTES).assertEqual(104857600);
      expect(MAX_LOCAL_AUDIO_DURATION_MS).assertEqual(1800000);
      expect(MAX_SUBTITLE_BYTES).assertEqual(2097152);
      expect(MAX_SUBTITLE_CUES).assertEqual(10000);
    });

    it('generates stable article ids from audio hash', 0, () => {
      expect(stableLocalArticleId('0123456789abcdefabcdef0123456789abcdef0123456789abcdef0123456789'))
        .assertEqual('ART-LOCAL-0123456789ABCDEFABCD');
    });
  });
}
