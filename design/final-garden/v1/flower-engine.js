(function (root) {
  "use strict";

  const WIDTH = 384;
  const HEIGHT = 192;
  const DURATION = 20;
  const STARTS = [0, 1.5, 3, 5, 12, 16];
  const LABELS = ["含苞", "待放", "初绽", "盛放", "萎垂", "凋零"];
  // Heart→calyx vectors in native sprite coordinates. The heart is the clip
  // pivot; the calyx, not the heart, is the mechanical stalk attachment.
  const ATTACH = [[2.52, 10.35], [0.9, 10.8], [-0.9, 13.77],
    [-3.6, 18.99], [3.15, -13.14], [3.51, -12.24]];
  const TIP_Y = [108, 108, 110, 110, 94, 94];
  const PI = Math.PI;
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const finite = (value, fallback) => Number.isFinite(value) ? value : fallback;
  const unit = value => clamp(value, 0, 1);
  const quarter = value => Math.round(value * 4) / 4;
  const halfDegree = value => Math.round(value * 2) / 2;
  const smooth = value => { const p = unit(value); return p * p * (3 - 2 * p); };
  const hash = value => {
    const number = Math.sin(value * 127.1 + 311.7) * 43758.5453123;
    return number - Math.floor(number);
  };

  function rotated(vector, angle) {
    const radians = angle * PI / 180;
    return [vector[0] * Math.cos(radians) - vector[1] * Math.sin(radians),
      vector[0] * Math.sin(radians) + vector[1] * Math.cos(radians)];
  }

  // A soft push followed by a short counter-swing. Every gust finishes at rest;
  // the gaps between pushes are intentional quiet windows, not a uniform sine.
  function push(age, length) {
    if (age < 0 || age > length + 0.75) return 0;
    const attack = 0.23;
    if (age < attack) return smooth(age / attack);
    if (age < length) return 1 - smooth((age - attack) / (length - attack));
    const recovery = age - length;
    return -Math.sin(recovery * 12.5) * Math.exp(-recovery * 6) * 0.25;
  }

  function scene(inputTime, inputOptions) {
    const options = inputOptions || {};
    const time = clamp(finite(inputTime, 0), 0, 1000000);
    const cycleStart = clamp(finite(options.cycleStart, 0), 0, 1000000);
    const localTime = Math.max(0, time - cycleStart);
    const wind = unit(finite(options.wind, 0.7));
    const still = options.reducedMotion === true;
    const gustAt = options.gustAt === null || options.gustAt === false
      ? null : finite(options.gustAt, cycleStart + 7.2);
    const commands = [];
    const events = [];
    const joints = [];

    const manual = Number.isFinite(options.flowerStage);
    let stage = manual ? Math.round(clamp(options.flowerStage, 0, 5)) : 0;
    if (!manual) {
      for (let index = 1; index < STARTS.length; index += 1) {
        if (localTime >= STARTS[index]) stage = index;
      }
    }
    const stageStart = manual
      ? finite(options.flowerStageSince, cycleStart) : cycleStart + STARTS[stage];
    const stageAge = Math.max(0, time - stageStart);

    function sprite(id, x, y, attributes) {
      commands.push(Object.assign({ type: "sprite", id,
        x: quarter(x), y: quarter(y), scaleX: 1, scaleY: 1, rotation: 0, opacity: 1 }, attributes || {}));
    }

    function line(points, color, width, opacity) {
      commands.push({ type: "line", points: points.map(point => point.map(quarter)),
        color, width: width || 1, opacity: opacity === undefined ? 1 : unit(opacity) });
    }

    function rectangle(x, y, width, height, color, opacity) {
      commands.push({ type: "rect", x: quarter(x), y: quarter(y), w: width, h: height,
        color, opacity: unit(opacity) });
    }

    function force(at, plantPhase) {
      if (still || wind === 0) return 0;
      const clock = at - plantPhase;
      const slot = Math.floor(clock / 5.2);
      let value = 0;
      // Procedurally varying breeze intervals keep the flowers alive beyond
      // this twenty-second sample without ever restarting their deadline state.
      for (let index = slot - 1; index <= slot; index += 1) {
        if (index < 0) continue;
        const beginning = index * 5.2 + 0.55 + hash(index + 3) * 1.2;
        const length = 1.05 + hash(index + 19) * 0.8;
        const strength = (0.4 + hash(index + 7) * 0.35) * (hash(index + 5) > 0.45 ? 1 : -1);
        value += push(clock - beginning, length) * strength;
      }
      if (gustAt !== null) value += push(at - gustAt - plantPhase, 1.45) * 1.15;
      return value * wind;
    }

    function follower(at, lag, phase) {
      return force(at - lag, phase) * 0.52 + force(at - lag - 0.06, phase) * 0.32 +
        force(at - lag - 0.12, phase) * 0.16;
    }

    function bezier(a, b, c, d, count) {
      const points = [];
      for (let index = 0; index <= count; index += 1) {
        const p = index / count;
        const q = 1 - p;
        points.push([q * q * q * a[0] + 3 * q * q * p * b[0] + 3 * q * p * p * c[0] + p * p * p * d[0],
          q * q * q * a[1] + 3 * q * q * p * b[1] + 3 * q * p * p * c[1] + p * p * p * d[1]]);
      }
      return points;
    }

    // Wedges are anchor-local, expanded ten degrees on both sides. Neighboring
    // petal groups overlap generously so sub-pixel lag cannot expose a seam.
    function wedge(startAngle, endAngle) {
      const points = [[0, 0]];
      const radius = 36;
      for (let angle = startAngle - 10; angle <= endAngle + 10; angle += 5) {
        const radians = angle * PI / 180;
        points.push([Math.cos(radians) * radius, Math.sin(radians) * radius]);
      }
      return points;
    }
    const groups = [
      { start: 210, end: 330, lag: 0.05, direction: -1 },
      { start: -30, end: 90, lag: 0.095, direction: 1 },
      { start: 90, end: 210, lag: 0.135, direction: -1 }
    ];

    function layeredHead(head, plant, response, angle) {
      const headID = "flower" + plant.stage + "Head";
      if (plant.stage !== 3) {
        sprite(headID, head.x, head.y, { rotation: angle });
        return;
      }
      groups.forEach(group => {
        const delayed = follower(time, plant.lag + group.lag, plant.phase);
        const delta = delayed - response;
        // Differential motion at an 18px petal tip stays below one native px.
        const rotation = clamp(delta * 2.6 * group.direction, -1.2, 1.2);
        const dx = clamp(delta * 0.32 * group.direction, -0.28, 0.28);
        const dy = clamp(delta * 0.22, -0.2, 0.2);
        sprite(headID, head.x + dx, head.y + dy, {
          rotation: angle + rotation,
          clipPolygon: wedge(group.start, group.end)
        });
      });
      // A matching central crop, not a recolored replacement, conceals the
      // shared pivot while preserving the flower's plum throat and gold core.
      const coreMask = [];
      for (let index = 0; index < 8; index += 1) {
        const radians = (22.5 + index * 45) * PI / 180;
        coreMask.push([Math.cos(radians) * 5.5, Math.sin(radians) * 5.5]);
      }
      sprite("flower3Core", head.x, head.y, { rotation: angle, clipPolygon: coreMask });
    }

    const plants = [
      { x: 102, stage: 1, lag: 0.09, phase: 0.02, leafSide: -1, lean: -1.5 },
      { x: 192, stage, lag: 0.115, phase: 0.085, leafSide: 1, lean: 0, main: true },
      { x: 282, stage: 4, lag: 0.14, phase: 0.15, leafSide: -1, lean: 1.5 }
    ];

    let mainHead = null;
    plants.forEach(plant => {
      const body = force(time, plant.phase);
      const upper = follower(time, 0.035, plant.phase);
      const headResponse = follower(time, plant.lag, plant.phase);
      const wilted = plant.stage >= 4;
      const settle = !still && plant.main && plant.stage > 0 && stageAge < 0.8
        ? Math.sin(stageAge * 13) * Math.exp(-stageAge * 6) * 1.1 : 0;
      const headAngle = halfDegree(clamp(headResponse * 1.2 + (headResponse - upper) * 4 + settle, -3.5, 3.5));
      const rootPoint = [plant.x, 130];
      const lower = [plant.x + (wilted ? 8 : -1.5) + body * 0.65, 118];
      const upperPoint = [plant.x + plant.lean + (wilted ? 12 : 0) + upper * 2.05, wilted ? 88 : 104];
      const calyxTip = {
        x: quarter(plant.x + plant.lean + headResponse * 2.7),
        y: quarter(TIP_Y[plant.stage] + Math.abs(headResponse) * 0.35)
      };
      const attachment = rotated(ATTACH[plant.stage], headAngle);
      const head = {
        x: calyxTip.x - attachment[0],
        y: calyxTip.y - attachment[1]
      };
      const stemPoints = bezier(rootPoint, lower, upperPoint, [calyxTip.x, calyxTip.y], 18);
      line(stemPoints, "#254c39", 2);
      line(stemPoints.map(point => [point[0] - 0.25, point[1]]), "#638f5c", 1);

      // The leaf begins at a real sampled stem joint. It responds later than
      // the lower stem, so a push reads root→joint→leaf rather than a flat tilt.
      const attach = stemPoints[6];
      const leafResponse = follower(time, 0.07 + plant.lag * 0.2, plant.phase);
      const leafEnd = [attach[0] + plant.leafSide * 5, attach[1] - 1 + leafResponse * 0.25];
      line([attach, [(attach[0] + leafEnd[0]) / 2, attach[1] - 1], leafEnd], "#426f46", 1);
      sprite("leaf", leafEnd[0], leafEnd[1], {
        scaleX: plant.leafSide,
        rotation: halfDegree(plant.leafSide * 22 + (leafResponse - body) * 7)
      });

      layeredHead(head, plant, headResponse, headAngle);
      joints.push({ root: { x: plant.x, y: 130 }, head, calyxTip, stage: plant.stage, angle: headAngle });
      if (plant.main) mainHead = head;
    });

    // A restrained, finite bloom accent. The permanent desktop state has no
    // continuous sparkle cloud, no glow and no breathing-scale deformation.
    if (!still && stage === 3 && stageAge > 0.3 && stageAge < 0.9) {
      const progress = (stageAge - 0.3) / 0.6;
      rectangle(mainHead.x - 5 - progress * 2, mainHead.y - 8 - progress * 3,
        1, 1, "#d5af61", (1 - progress) * 0.65);
      rectangle(mainHead.x + 6 + progress, mainHead.y - 5 - progress * 3,
        1, 1, "#e3c77f", (1 - progress) * 0.55);
    }

    const petalStart = manual ? stageStart + 0.5 : cycleStart + 16.5;
    const petalAge = time - petalStart;
    if (!still && stage === 5 && petalAge >= 0 && petalAge < 3.1) {
      const progress = petalAge / 3.1;
      const birthResponse = follower(petalStart, plants[1].lag, plants[1].phase);
      const birthUpper = follower(petalStart, 0.035, plants[1].phase);
      const birthAngle = halfDegree(clamp(birthResponse * 1.2 + (birthResponse - birthUpper) * 4, -3.5, 3.5));
      const birthAttachment = rotated(ATTACH[5], birthAngle);
      const edge = rotated([-12, 8], birthAngle);
      const birthX = 192 + birthResponse * 2.7 - birthAttachment[0] + edge[0];
      const birthY = TIP_Y[5] + Math.abs(birthResponse) * 0.35 - birthAttachment[1] + edge[1];
      sprite("petal", birthX - petalAge * 4.5 + Math.sin(petalAge * 2.6) * 1.2,
        birthY + petalAge * 3.5 + petalAge * petalAge * 4.5, {
          rotation: halfDegree(-18 + petalAge * 48),
          opacity: progress < 0.84 ? 1 : 1 - smooth((progress - 0.84) / 0.16)
        });
      events.push({ kind: "petal", label: "一片花瓣轻落", progress: unit(progress) });
    }
    if (gustAt !== null && time >= gustAt && time < gustAt + 2.2) {
      events.push({ kind: "gust", label: "风过，花瓣稍后跟随", progress: unit((time - gustAt) / 2.2) });
    }

    return {
      commands,
      stage,
      stageLabel: LABELS[stage],
      stageAge,
      progress: manual ? STARTS[stage] / DURATION : unit(localTime / DURATION),
      events,
      joints,
      view: "flowers"
    };
  }

  const api = Object.freeze({ width: WIDTH, height: HEIGHT, duration: DURATION,
    stageLabels: Object.freeze(LABELS.slice()), scene });
  root.FarmMotion = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
