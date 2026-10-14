import test from 'node:test';
import assert from 'node:assert/strict';
import Physics from '../physics.bend';

for (const [mass, expected] of [[1, 3], [100, 31], [10000, 314], [1000000, 3141]]) {
  test(`mass ratio ${mass}: ${expected} collisions, conserved energy, valid events`, () => {
    let state = Physics.initial(mass);
    let maxDrift = 0;
    while (!Physics.finished(state) && state.count < 10000) {
      const next = Physics.next(state);
      assert.equal(next.count, state.count + 1);
      assert.ok(Number.isFinite(next.time) && next.time >= state.time);
      assert.ok(next.x >= 0 && next.y >= next.x - 0.0001);
      assert.ok(Number.isFinite(next.v) && Number.isFinite(next.w));
      const drift = Math.abs(Physics.energy(next) / (mass / 2) - 1);
      maxDrift = Math.max(maxDrift, drift);
      if (!next.wall) {
        const before = state.v + mass * state.w;
        const after = next.v + mass * next.w;
        assert.ok(Math.abs(after - before) / mass < 0.000001);
        assert.ok(next.v <= next.w);
        assert.equal(next.x, next.y);
      } else {
        assert.equal(next.x, 0);
        assert.equal(next.v, -state.v);
        assert.equal(next.w, state.w);
      }
      state = next;
    }
    assert.ok(Physics.finished(state));
    assert.equal(state.count, expected);
    assert.ok(maxDrift < 0.0005, `energy drift ${maxDrift}`);
    assert.deepEqual(Physics.next(state), state);
    assert.deepEqual(Physics.run(10000n, Physics.initial(mass)), state);
  });
}

test('equal masses exchange velocities, then bounce off the wall', () => {
  const first = Physics.next(Physics.initial(1));
  assert.equal(first.time, 2);
  assert.equal(first.v, -1);
  assert.equal(first.w, 0);
  assert.equal(first.wall, false);
  const second = Physics.next(first);
  assert.equal(second.time, 3);
  assert.equal(second.v, 1);
  assert.equal(second.wall, true);
});

test('fuel limits are explicit and do not claim an unfinished count is final', () => {
  const initial = Physics.initial(100);
  assert.deepEqual(Physics.run(0n, initial), initial);
  const partial = Physics.run(2n, initial);
  assert.equal(partial.count, 2);
  assert.equal(Physics.finished(partial), false);
});
