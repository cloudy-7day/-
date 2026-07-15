(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.MotionCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const durationMs = 1150;

  function clamp01(value) {
    return Math.min(1, Math.max(0, Number(value) || 0));
  }

  function smoothstep(start, end, value) {
    const t = clamp01((value - start) / (end - start));
    return t * t * (3 - 2 * t);
  }

  function clean(value) {
    const rounded = Math.round(value * 10000) / 10000;
    return Object.is(rounded, -0) ? 0 : rounded;
  }

  function heroFrame(progress) {
    const t = smoothstep(0.02, 0.46, clamp01(progress));
    return {
      opacity: clean(1 - t),
      yVh: clean(-38 * t),
      scale: clean(1 - 0.07 * t),
      blurPx: clean(4 * t),
    };
  }

  function cardFrame(progress, index) {
    const cardIndex = Math.min(2, Math.max(0, Number(index) || 0));
    const start = 0.28 + cardIndex * 0.075;
    const end = 0.79 + cardIndex * 0.08;
    const t = smoothstep(start, end, clamp01(progress));
    return {
      opacity: clean(t),
      yVh: clean(34 * (1 - t)),
      scale: clean(0.94 + 0.06 * t),
      saturation: clean(0.08 + 0.92 * t),
      blurPx: clean(5 * (1 - t)),
    };
  }

  return { durationMs, heroFrame, cardFrame };
});
