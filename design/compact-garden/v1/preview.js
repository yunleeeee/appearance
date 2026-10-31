/* Static visual proof only. No DDL, lifecycle, picking or fruit-state code. */
(() => {
  'use strict';
  const params = new URLSearchParams(location.search);
  const background = ['desktop', 'complex', 'dark', 'light'].includes(params.get('background')) ? params.get('background') : 'desktop';
  const state = params.get('state') === 'all' ? 'all' : 'flowers';
  document.documentElement.dataset.background = background;
  document.documentElement.dataset.state = state;
  const image = (href, width, height, clip) => `<image href="${href}" width="${width}" height="${height}"${clip ? ` clip-path="url(#${clip})"` : ''}/>`;
  const plants = [
    {id:'bud', crop:[187,350,399,501], root:[395,848], at:34, scale:0.165, lean:-4, divide:566},
    {id:'bloom', crop:[677,72,485,779], root:[873,848], at:131, scale:0.187, lean:1, divide:448},
    {id:'nodding', crop:[1296,340,401,511], root:[1493,848], at:246, scale:0.175, lean:5, divide:660}
  ];
  const flowerDefs = plants.map(p => `<clipPath id="${p.id}"><rect x="${p.crop[0]}" y="${p.crop[1]}" width="${p.crop[2]}" height="${p.crop[3]}"/></clipPath><clipPath id="${p.id}-head"><rect x="0" y="0" width="1816" height="${p.divide}"/></clipPath><clipPath id="${p.id}-foliage"><rect x="0" y="${p.divide}" width="1816" height="866"/></clipPath>`).join('');
  const flowers = `<svg id="flowers" viewBox="-2 -3 289 148" aria-label="错落生长的三株莓玫瑰，仅展示外观"><defs>${flowerDefs}</defs>${plants.map(p => `<g data-visual-slot="${p.id}" transform="translate(${p.at} 145) rotate(${p.lean}) scale(${p.scale}) translate(${-p.root[0]} ${-p.root[1]})" clip-path="url(#${p.id})"><g clip-path="url(#${p.id}-head)">${image('flowers-source.png',1816,866)}</g><g class="foliage" clip-path="url(#${p.id}-foliage)">${image('flowers-source.png',1816,866)}</g></g>`).join('')}</svg>`;
  const trellis = `<svg id="trellis" viewBox="29 38 1401 1022" aria-label="仅展示状态可见的葡萄架"><defs><clipPath id="fruit"><rect x="203" y="310" width="153" height="163"/><rect x="616" y="328" width="141" height="166"/><rect x="1016" y="310" width="142" height="161"/></clipPath></defs><g class="trellis-secondary">${image('trellis-source.png',1456,1080)}</g>${image('trellis-source.png',1456,1080,'fruit')}</svg>`;
  document.getElementById('plants').innerHTML = trellis + flowers;
  // Apply the same purely visual transform to every layer at every viewport.
  const fit = () => document.getElementById('plants').style.transform = `scale(${Math.min(innerWidth / 1555, innerHeight / 1012)})`;
  fit();
  addEventListener('resize', fit);
  document.title = `${state === 'all' ? '完整组合' : '花朵常驻'} · ${background} · 轻盈像素挂件`;
  window.visualProof = Object.freeze({background,state,reference:{width:1555,height:1012},flowerBounds:{width:289,height:148},trellisBounds:{width:400,height:292},trellisBottomOffset:72,staticOnly:true});
})();
