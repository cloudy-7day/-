const assert = require("node:assert/strict");
const motion = require("../motion-core.js");

assert.equal(motion.durationMs, 1150);

const heroStart = motion.heroFrame(0);
const heroEnd = motion.heroFrame(0.46);
assert.deepEqual(heroStart, { opacity: 1, yVh: 0, scale: 1, blurPx: 0 });
assert.equal(heroEnd.opacity, 0);
assert.equal(heroEnd.yVh, -38);
assert.equal(heroEnd.scale, 0.93);
assert.equal(heroEnd.blurPx, 4);

const firstCardStart = motion.cardFrame(0, 0);
const firstCardEnd = motion.cardFrame(1, 0);
assert.equal(firstCardStart.opacity, 0);
assert.equal(firstCardStart.yVh, 34);
assert.equal(firstCardStart.saturation, 0.08);
assert.equal(firstCardStart.blurPx, 5);
assert.equal(firstCardEnd.opacity, 1);
assert.equal(firstCardEnd.yVh, 0);
assert.equal(firstCardEnd.scale, 1);
assert.equal(firstCardEnd.saturation, 1);
assert.equal(firstCardEnd.blurPx, 0);

assert.ok(motion.cardFrame(0.35, 0).opacity > motion.cardFrame(0.35, 2).opacity);

for (const progress of [-1, 0, 0.2, 0.5, 1, 2]) {
  const values = [
    ...Object.values(motion.heroFrame(progress)),
    ...Object.values(motion.cardFrame(progress, 2)),
  ];
  assert.ok(values.every(Number.isFinite));
}

console.log("Motion core tests passed.");
