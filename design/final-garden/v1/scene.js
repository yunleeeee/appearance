(function (root) {
  "use strict";

  // flower-engine.js is the accepted, frozen flower v2 engine. This wrapper
  // never moves its plants or changes their drawing/animation calculations.
  const Flower = root.FarmMotion;
  if (!Flower || typeof Flower.scene !== "function") {
    throw new Error("Load the accepted flower-engine.js before the combined scene");
  }

  const WIDTH = 384;
  const HEIGHT = 192;
  const DURATION = 12;
  const PI = Math.PI;
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const finite = (value, fallback) => Number.isFinite(value) ? value : fallback;
  const unit = value => clamp(value, 0, 1);
  const quarter = value => Math.round(value * 4) / 4;
  const halfDegree = value => Math.round(value * 2) / 2;
  const smooth = value => { const p = unit(value); return p * p * (3 - 2 * p); };

  function eventAge(time, event, length) {
    return event === null || time < event || time > event + length ? -1 : time - event;
  }

  function scene(inputTime, inputOptions) {
    const options = inputOptions || {};
    const time = clamp(finite(inputTime, 0), 0, 1000000);
    const wind = unit(finite(options.wind, 0.52));
    const still = options.reducedMotion === true;
    const visibility = ["all", "flowers", "transition"].includes(options.visibility)
      ? options.visibility : "transition";
    const transitionAt = Math.max(0, finite(options.transitionAt, 4));
    const fadeDuration = clamp(finite(options.fadeDuration, 2), 0.05, 60);
    const gardenOpacity = visibility === "all" ? 1 : visibility === "flowers" ? 0
      : 1 - smooth((time - transitionAt) / fadeDuration);
    const gustAt = options.gustAt === null || options.gustAt === false
      ? null : Math.max(0, finite(options.gustAt, 2));
    const feedAt = options.feedAt === null || options.feedAt === false
      ? null : Math.max(0, finite(options.feedAt, 1));
    const gustAge = still ? -1 : eventAge(time, gustAt, 2.6);
    const feedAge = still ? -1 : eventAge(time, feedAt, 2.1);
    const garden = [];

    const flowerOptions = Object.assign({}, options, {
      wind, reducedMotion: still, gustAt,
      flowerStageSince: finite(options.flowerStageSince, 0)
    });
    // This final assembly holds the approved main bloom, rather than making
    // the act of hiding the garden advance or restart its deadline state.
    if (!Number.isFinite(options.flowerStage) && options.flowerAuto !== true) {
      flowerOptions.flowerStage = 3;
    }
    const flowers = Flower.scene(time, flowerOptions);

    function sprite(list, layer, id, x, y, attributes) {
      list.push(Object.assign({ type: "sprite", id, layer,
        x: quarter(x), y: quarter(y), scaleX: 1, scaleY: 1,
        rotation: 0, opacity: 1 }, attributes || {}));
    }

    function line(list, layer, points, color, width, opacity) {
      list.push({ type: "line", layer,
        points: points.map(point => point.map(quarter)), color,
        width: width || 1, opacity: opacity === undefined ? 1 : unit(opacity) });
    }

    // The main vine is exactly y=130 at all three frozen flower roots. Its
    // gentle arches and breeze displacement both approach zero at these knots.
    const knots = [24, 102, 192, 282, 361];
    function vineY(x) {
      let segment = 0;
      while (segment < knots.length - 2 && x > knots[segment + 1]) segment += 1;
      const p = unit((x - knots[segment]) / (knots[segment + 1] - knots[segment]));
      const envelope = Math.pow(Math.sin(p * PI), 2);
      const baseline = 130 + (segment % 2 === 0 ? -1 : 1) * envelope * 2.2;
      if (still) return baseline;
      const idle = Math.sin(time * 1.13 - x * 0.021) * wind * 0.42;
      const gust = gustAge < 0 ? 0 : Math.sin(PI * gustAge / 2.6) *
        Math.sin(gustAge * 5.2 - x * 0.023) * (0.7 + wind * 1.1);
      const load = feedAge < 0 ? 0 : Math.sin(feedAge * 16) * Math.exp(-feedAge * 3.1) *
        Math.exp(-Math.pow((x - 68) / 44, 2)) * 0.9;
      return baseline + envelope * (idle + gust + load);
    }

    function leafMotion(x, phase) {
      if (still) return 0;
      const idle = Math.sin(time * 1.35 + phase) * wind * 2.6;
      const gust = gustAge < 0 ? 0 : Math.sin(PI * gustAge / 2.6) *
        Math.sin(gustAge * 5.8 - x * 0.021) * 5.5;
      return halfDegree(idle + gust);
    }

    // The wood stays rigid. Only the young vine and leaves react to a breeze.
    sprite(garden, "garden", "gardenTrellis", 370, 173);
    const vinePoints = [];
    for (let x = 24; x < 361; x += 3) vinePoints.push([x, vineY(x)]);
    // Explicit knots make every flower attachment exact, regardless of sampling.
    [102, 192, 282, 361].forEach(x => vinePoints.push([x, vineY(x)]));
    vinePoints.sort((a, b) => a[0] - b[0]);
    line(garden, "garden", vinePoints, "#35573b", 3);
    line(garden, "garden", vinePoints.map(p => [p[0], p[1] - 0.5]), "#7d9a43", 1);

    const leaves = [
      { x: 30, id: "gardenLeafC", rotation: -150, mirror: 1, phase: 5.9 },
      { x: 65, id: "gardenLeafA", rotation: -20, mirror: 1, phase: 0.4 },
      { x: 145, id: "gardenLeafC", rotation: 158, mirror: 1, phase: 2.1 },
      { x: 235, id: "gardenLeafB", rotation: -155, mirror: 1, phase: 4.3 },
      { x: 325, id: "gardenLeafC", rotation: 22, mirror: -1, phase: 5.2 }
    ];
    leaves.forEach(leaf => sprite(garden, "garden", leaf.id, leaf.x, vineY(leaf.x), {
      rotation: leaf.rotation + leafMotion(leaf.x, leaf.phase), scaleX: leaf.mirror
    }));

    const curlShape = [[0, 0], [0, -3], [-1, -5], [-3, -7], [-3, -10],
      [-1, -12], [2, -13], [5, -13], [7, -11], [7, -8], [5, -6],
      [2, -6], [1, -7], [1, -9], [3, -10], [4, -9]];
    [
      { x: 46, v: 1, h: -1, size: 0.75, phase: 0.2 },
      { x: 125, v: -1, h: 1, size: 0.65, phase: 1.8 },
      { x: 349, v: 1, h: -1, size: 0.7, phase: 4.2 }
    ].forEach(curl => {
      const bend = still ? 0 : Math.sin(time * 1.4 + curl.phase) * wind * 0.35 +
        (gustAge < 0 ? 0 : Math.sin(PI * gustAge / 2.6) * Math.sin(gustAge * 5 + curl.phase) * 0.75);
      const y = vineY(curl.x);
      const points = curlShape.map(p => [curl.x + p[0] * curl.h * curl.size + bend * Math.abs(p[1]) / 13,
        y + p[1] * curl.v * curl.size]);
      line(garden, "garden", points, "#35573b", 2);
      line(garden, "garden", points, "#8ba24b", 1);
    });

    [
      { x: 68, id: "gardenGrapePurple", phase: 0.7, receives: true },
      { x: 158, id: "gardenGrapeGreen", phase: 2.3 },
      { x: 306, id: "gardenGrapeGold", phase: 4.0 }
    ].forEach(grape => {
      const y = vineY(grape.x);
      const pulse = grape.receives && feedAge >= 0 && feedAge < 0.6
        ? Math.sin(PI * feedAge / 0.6) : 0;
      const recoil = grape.receives && feedAge >= 0
        ? Math.sin(feedAge * 16) * Math.exp(-feedAge * 3.2) * 7 : 0;
      const ambient = still ? 0 : Math.sin(time * 1.1 + grape.phase) * wind * 1.4;
      line(garden, "garden", [[grape.x, y], [grape.x - 1, y + 4], [grape.x, y + 7]], "#526d38", 2);
      sprite(garden, "garden", grape.id, grape.x, y + 7, {
        rotation: halfDegree(ambient + recoil), scaleX: 1 - pulse * 0.045, scaleY: 1 + pulse * 0.06
      });
    });

    // Keep only a small calyx-side stalk in the permanent ornament. The long
    // connecting stem and its side leaf belong to the garden and fade with it.
    // The frozen head/petal movement is passed through without repositioning.
    function shortStalk(points, length) {
      const kept = [points[points.length - 1].slice()];
      let remaining = length;
      for (let index = points.length - 2; index >= 0; index -= 1) {
        const next = points[index];
        const last = kept[kept.length - 1];
        const distance = Math.hypot(next[0] - last[0], next[1] - last[1]);
        if (distance <= remaining) {
          kept.push(next.slice());
          remaining -= distance;
        } else {
          const ratio = remaining / distance;
          kept.push([last[0] + (next[0] - last[0]) * ratio,
            last[1] + (next[1] - last[1]) * ratio]);
          break;
        }
      }
      return kept.reverse();
    }
    const flowerCommands = [];
    flowers.commands.forEach(command => {
      if (command.type === "line" && command.points.length >= 10) {
        garden.push(Object.assign({}, command, { layer: "garden" }));
        flowerCommands.push(Object.assign({}, command, {
          points: shortStalk(command.points, 5), layer: "flowers"
        }));
      } else if (command.id === "leaf" || command.type === "line") {
        garden.push(Object.assign({}, command, { layer: "garden" }));
      } else {
        flowerCommands.push(Object.assign({}, command, { layer: "flowers" }));
      }
    });
    const gardenCommands = garden.map(command => Object.assign({}, command, {
      opacity: (command.opacity === undefined ? 1 : command.opacity) * gardenOpacity
    }));
    const events = flowers.events.slice();
    if (visibility === "transition" && time >= transitionAt && time < transitionAt + fadeDuration) {
      events.push({ kind: "gardenFade", label: "藤蔓与葡萄淡出，花朵常驻", progress: unit((time - transitionAt) / fadeDuration) });
    }

    return Object.assign({}, flowers, {
      commands: gardenCommands.concat(flowerCommands),
      events,
      view: gardenOpacity === 0 ? "flowers" : "combined",
      visibility,
      gardenOpacity,
      transitionProgress: visibility === "transition" ? unit((time - transitionAt) / fadeDuration) : gardenOpacity === 0 ? 1 : 0,
      sourceFlowerVersion: "flower-v2.0",
      flowerPresentation: "flower-head-with-5px-calyx-stalk"
    });
  }

  const api = Object.freeze({ width: WIDTH, height: HEIGHT, duration: DURATION,
    stageLabels: Flower.stageLabels, flowerSource: Flower, scene });
  root.CombinedMotion = api;
  root.FarmMotion = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
