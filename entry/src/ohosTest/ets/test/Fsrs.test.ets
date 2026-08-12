import { describe, expect, it } from '@ohos/hypium';
import { FsrsScheduler } from '../../../main/ets/domain/Fsrs';
import { FsrsState, Rating } from '../../../main/ets/domain/Models';

export default function fsrsTests(): void {
  describe('FSRS v6 golden vectors', () => {
    const base = Date.parse('2024-01-01T12:00:00Z');
    const scheduler = new FsrsScheduler();

    it('first good matches shared golden vector', 0, () => {
      const card = scheduler.review({ state: FsrsState.NEW, step: null, stability: null,
        difficulty: null, dueAtEpochMs: base, lastReviewAtEpochMs: null }, Rating.GOOD, base);
      expect(card.state).assertEqual(FsrsState.LEARNING);
      expect(card.step).assertEqual(1);
      expect(card.dueAtEpochMs).assertEqual(base + 10 * 60 * 1000);
      expect(Math.abs((card.stability ?? 0) - 2.3065) < 0.0000001).assertTrue();
    });

    it('first easy immediately enters review', 0, () => {
      const card = scheduler.review({ state: FsrsState.NEW, step: null, stability: null,
        difficulty: null, dueAtEpochMs: base, lastReviewAtEpochMs: null }, Rating.EASY, base);
      expect(card.state).assertEqual(FsrsState.REVIEW);
      expect(card.dueAtEpochMs).assertEqual(base + 8 * 86400000);
      expect(Math.abs((card.stability ?? 0) - 8.2956) < 0.0000001).assertTrue();
    });

    it('first hard uses five and a half minute step', 0, () => {
      const card = scheduler.review({ state: FsrsState.NEW, step: null, stability: null,
        difficulty: null, dueAtEpochMs: base, lastReviewAtEpochMs: null }, Rating.HARD, base);
      expect(card.state).assertEqual(FsrsState.LEARNING);
      expect(card.dueAtEpochMs).assertEqual(base + 330000);
    });
  });
}
