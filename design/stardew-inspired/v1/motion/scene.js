(function (root) {
  "use strict";

  // The renderer resolves sprite IDs through manifest.json. x/y always denote
  // that sprite's native support anchor, never the upper-left image corner.
  const WIDTH = 384;
  const HEIGHT = 192;
  const DURATION = 16;
  const LABELS = ["含苞", "待放", "初绽", "盛放", "萎垂", "凋零"];
  const STARTS = [0, 2, 4, 6, 10, 13];
  const PI = Math.PI;
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const finite = (value, fallback) => Number.isFinite(value) ? value : fallback;
  const snap = value => Math.round(value);
  const unit = value => clamp(value, 0, 1);
  const ease = value => { const p = unit(value); return p * p * (3 - 2 * p); };

  function eventAt(value, fallback) {
    if (value === null || value === false) return null;
    return finite(value, fallback);
  }

  function activeAge(time, start, length) {
    if (start === null || time < start || time >= start + length) return -1;
    return time - start;
  }

  function scene(inputTime, inputOptions) {
    const options = inputOptions || {};
    const time = clamp(finite(inputTime, 0), 0, 1000000);
    // Twelve changes per second preserve the quiet, deliberate pixel cadence.
    const sampled = Math.floor(time * 12) / 12;
    const start = clamp(finite(options.cycleStart, 0), 0, 1000000);
    const lifeTime = Math.max(0, time - start);
    const wind = unit(finite(options.wind, 0.46));
    const still = options.reducedMotion === true;
    const feedAt = eventAt(options.feedAt, start + 2.4);
    const gustAt = eventAt(options.gustAt, start + 6.2);
    const feedAge = still ? -1 : activeAge(sampled, feedAt, 2.1);
    const gustAge = still ? -1 : activeAge(sampled, gustAt, 2.6);
    const commands = [];
    const events = [];

    const hasManualStage = Number.isFinite(options.flowerStage);
    let stage = hasManualStage ? Math.round(clamp(options.flowerStage, 0, 5)) : 0;
    if (!hasManualStage) {
      for (let i = 1; i < STARTS.length; i += 1) {
        if (lifeTime >= STARTS[i]) stage = i;
      }
    }
    const stageStart = hasManualStage
      ? finite(options.flowerStageSince, start)
      : start + STARTS[stage];
    const stageAge = Math.max(0, time - stageStart);

    function sprite(id, x, y, properties) {
      commands.push(Object.assign({ type: "sprite", id,
        x: snap(x), y: snap(y), scaleX: 1, scaleY: 1, rotation: 0, opacity: 1 }, properties || {}));
    }

    function line(points, color, width, opacity) {
      commands.push({ type: "line", points: points.map(p => [snap(p[0]), snap(p[1])]),
        color, width: width || 1, opacity: opacity === undefined ? 1 : unit(opacity) });
    }

    function rect(x, y, w, h, color, opacity) {
      commands.push({ type: "rect", x: snap(x), y: snap(y), w: snap(w), h: snap(h),
        color, opacity: unit(opacity) });
    }

    function vineY(x) {
      // A young vine winds above and below the rigid trellis crossbar. This
      // fixed shape remains when motion is reduced; it is not an idle wiggle.
      const baseline = 102 + snap(Math.sin(x * 0.057 + 0.55) * 2.5);
      if (still) return baseline;
      const idle = Math.sin(sampled * 1.15 - x * 0.019) * 0.65 * wind;
      const gust = gustAge < 0 ? 0 : Math.sin(PI * gustAge / 2.6) *
        Math.sin(gustAge * 5.2 - x * 0.022) * (1.0 + wind * 1.2);
      const load = feedAge < 0 ? 0 : Math.exp(-feedAge * 3.1) *
        Math.sin(feedAge * 16) * Math.exp(-Math.pow((x - 78) / 50, 2)) * 1.1;
      return baseline + snap(idle + gust + load);
    }

    function leafMotion(x, phase) {
      if (still) return 0;
      const idle = Math.sin(sampled * 1.5 + phase) * wind * 3;
      const gust = gustAge < 0 ? 0 : Math.sin(PI * gustAge / 2.6) *
        Math.sin(gustAge * 6 - x * 0.023) * 7;
      return snap(idle + gust);
    }

    // The wooden structure does not drift with the wind. The young vine and
    // its child sprites share the same sampled support coordinates above it.
    sprite("trellis", 370, 145);
    const trunkPoints = [];
    for (let x = 25; x <= 357; x += 4) trunkPoints.push([x, vineY(x)]);
    trunkPoints.push([361, vineY(361)]);
    line(trunkPoints, "#365727", 3);
    line(trunkPoints.map(p => [p[0], p[1] - 1]), "#749b35", 1);

    // Short pixel curls grow from the same vine nodes. Their tip can bend a
    // pixel in a gust, while every root remains attached to the main stem.
    const curlShape = [[0, 0], [0, -3], [-1, -5], [-3, -7], [-3, -10],
      [-1, -12], [2, -13], [5, -13], [7, -11], [7, -8], [5, -6],
      [2, -6], [1, -7], [1, -9], [3, -10], [4, -9]];
    [
      { x: 54, vertical: 1, horizontal: -1, size: 1, phase: 0.2 },
      { x: 132, vertical: -1, horizontal: 1, size: 0.85, phase: 1.8 },
      { x: 181, vertical: 1, horizontal: 1, size: 0.9, phase: 3.0 },
      { x: 342, vertical: -1, horizontal: -1, size: 0.8, phase: 4.2 }
    ].forEach(curl => {
      const rootY = vineY(curl.x);
      const tipBend = still ? 0 : Math.sin(sampled * 1.4 + curl.phase) * wind * 0.5 +
        (gustAge < 0 ? 0 : Math.sin(PI * gustAge / 2.6) * Math.sin(gustAge * 5 + curl.phase) * 1.1);
      const points = curlShape.map(point => {
        const distance = Math.abs(point[1]) / 13;
        return [curl.x + point[0] * curl.horizontal * curl.size + tipBend * distance,
          rootY + point[1] * curl.vertical * curl.size];
      });
      line(points, "#365727", 2);
      line(points, "#88a63d", 1);
    });

    const leaves = [
      { x: 30, id: "leafC", rotation: -150, mirror: 1, phase: 5.9 },
      { x: 45, id: "leafA", rotation: -23, mirror: 1, phase: 0.1 },
      { x: 98, id: "leafB", rotation: 24, mirror: -1, phase: 1.3 },
      { x: 145, id: "leafC", rotation: 160, mirror: 1, phase: 2.2 },
      { x: 195, id: "leafA", rotation: 27, mirror: -1, phase: 3.1 },
      { x: 255, id: "leafB", rotation: -155, mirror: 1, phase: 4.4 },
      { x: 326, id: "leafC", rotation: 19, mirror: -1, phase: 5.2 },
      { x: 350, id: "leafC", rotation: 160, mirror: -1, phase: 6.8 }
    ];
    leaves.forEach(leaf => sprite(leaf.id, leaf.x, vineY(leaf.x), {
      rotation: leaf.rotation + leafMotion(leaf.x, leaf.phase), scaleX: leaf.mirror
    }));

    [
      { x: 78, id: "grapePurple", phase: 0.7, receives: true },
      { x: 166, id: "grapeGreen", phase: 2.3, receives: false },
      { x: 282, id: "grapeGold", phase: 4.0, receives: false }
    ].forEach(grape => {
      const y = vineY(grape.x);
      const pulse = grape.receives && feedAge >= 0 && feedAge < 0.6
        ? Math.sin(PI * feedAge / 0.6) : 0;
      const recoil = grape.receives && feedAge >= 0
        ? Math.sin(feedAge * 16) * Math.exp(-feedAge * 3.2) * 8 : 0;
      const ambient = still ? 0 : Math.sin(sampled * 1.1 + grape.phase) * wind * 1.6;
      line([[grape.x, y], [grape.x - 1, y + 4], [grape.x, y + 6]], "#526d2a", 2);
      sprite(grape.id, grape.x, y + 6, {
        rotation: snap(ambient + recoil), scaleX: 1 - pulse * 0.055, scaleY: 1 + pulse * 0.075
      });
    });

    const flowerSupports = [
      { x: 110, stage: 0, phase: 0.8 },
      { x: 226, stage, phase: 2.1, main: true },
      { x: 310, stage: 3, phase: 4.6 }
    ];
    flowerSupports.forEach(flower => {
      const x = flower.x;
      const y = vineY(x) - 1;
      const settle = !still && flower.main && stage > 0 && stageAge < 0.65
        ? Math.sin(stageAge * 18) * Math.exp(-stageAge * 7) * 2.5 : 0;
      const movement = still ? 0 : Math.sin(sampled * 1.15 + flower.phase) * wind * 1.4;
      sprite("flower" + flower.stage, x, y, {
        rotation: snap(movement + settle),
        // The dried cel faces the opposite way in the generated source. Mirror
        // around its support to preserve the left-bowing wilting silhouette.
        scaleX: flower.stage === 5 ? -1 : 1
      });
    });

    // Only an actual growth feedback creates these three tiny square motes.
    // There is no permanent glitter field around the desktop ornament.
    if (feedAge >= 0 && feedAge < 0.85) {
      const p = feedAge / 0.85;
      [-1, 0, 1].forEach((direction, index) => {
        rect(78 + direction * (4 + p * 9), vineY(78) + 13 - p * 17 - index * 2,
          index === 1 ? 2 : 1, index === 1 ? 2 : 1,
          index === 1 ? "#f5d56b" : "#f9e7aa", (1 - p) * 0.9);
      });
    }

    // This keypose represents overdue, not successful task completion. The
    // residual flower remains. Only its loose petal detaches and settles.
    const petalStart = hasManualStage ? stageStart + 0.2 : start + 13.2;
    const petalAge = stage === 5 && !still ? activeAge(sampled, petalStart, 2.6) : -1;
    if (petalAge >= 0) {
      const p = petalAge / 2.6;
      const px = 214 + petalAge * 6 + Math.sin(petalAge * 3.3) * 4;
      const py = 84 + petalAge * 5 + petalAge * petalAge * 7;
      sprite("petal", px, py, {
        rotation: snap(petalAge * 74 - 20),
        opacity: p < 0.8 ? 1 : 1 - ease((p - 0.8) / 0.2)
      });
      events.push({ kind: "petal", label: "落瓣", progress: unit(p) });
    }
    if (feedAge >= 0) events.push({ kind: "feed", label: "葡萄回弹", progress: unit(feedAge / 2.1) });
    if (gustAge >= 0) events.push({ kind: "gust", label: "一阵微风", progress: unit(gustAge / 2.6) });
    if (stage > 0 && stageAge < 0.65) events.push({ kind: "flower", label: LABELS[stage], progress: unit(stageAge / 0.65) });

    return {
      commands,
      stage,
      stageLabel: LABELS[stage],
      progress: hasManualStage ? STARTS[stage] / DURATION : unit(lifeTime / DURATION),
      stageAge,
      events
    };
  }

  const api = Object.freeze({ duration: DURATION, width: WIDTH, height: HEIGHT,
    stageLabels: Object.freeze(LABELS.slice()), scene });
  root.FarmMotion = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
