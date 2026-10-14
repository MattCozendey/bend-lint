import test from 'node:test';
import assert from 'node:assert/strict';
import A from '../accelerated.bend';
import D from '../precise.bend';
import Physics from '../physics.bend';

const expected = [3n, 31n, 314n, 3141n, 31415n, 314159n, 3141592n, 31415926n, 314159265n, 3141592653n, 31415926535n, 314159265358n];

for (let places = 0; places < expected.length; places++) {
  test(`${places + 1} digits: composed collisions give ${expected[places]}`, () => {
    const count = A.count(BigInt(places));
    assert.equal(count, expected[places]);
    if (places < 4) {
      assert.equal(count, BigInt(Physics.run(10000n, Physics.initial(100 ** places)).count));
    }
    const rotation = A.rotation(D.tenth(BigInt(places)));
    const firstInvalidPair = count / 2n + 1n;
    assert.equal(A.crossed(rotation, firstInvalidPair - 1n), false);
    assert.equal(A.crossed(rotation, firstInvalidPair), true);
  });
}

const value = n => n.hi + n.lo;
test('two-float arithmetic preserves the unit lost by plain F32', () => {
  const n = D.add(D.of(1e8), D.of(1));
  assert.equal(Math.fround(1e8 + 1), 1e8);
  assert.equal(value(n), 100000001);
  assert.equal(value(D.sub(n, D.of(1e8))), 1);
});

test('products, cancellation and division retain extended precision', () => {
  for (const [x, y] of [[1.0001, 0.9999], [1e8, 1e-8], [-7.12345, 3.23456], [0.000001234, 0.000005678]]) {
    const a = Math.fround(x), b = Math.fround(y);
    assert.equal(value(D.product(a, b)), a * b);
    const quotient = value(D.div(D.of(a), D.of(b)));
    assert.ok(Math.abs((quotient - a / b) / (a / b)) < 3e-14);
    assert.equal(value(D.sum(a, -a)), 0);
  }
});

test('fast powers agree with applying the collision pair repeatedly', () => {
  const rotation = A.rotation(D.tenth(2n));
  let sequential = {$: 'Rotation', re: D.of(1), im: D.of(0)};
  for (let k = 0n; k <= 160n; k++) {
    const fast = A.power(rotation, k);
    assert.ok(Math.abs(value(fast.re) - value(sequential.re)) < 1e-11);
    assert.ok(Math.abs(value(fast.im) - value(sequential.im)) < 1e-11);
    sequential = A.compose(sequential, rotation);
  }
});
