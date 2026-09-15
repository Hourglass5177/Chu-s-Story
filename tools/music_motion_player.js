// Playback of real rendered frames at source timestamps, without motion synthesis.
let activePlayer = null;
for (const section of document.querySelectorAll('section[data-task]')) {
  const task = section.dataset.task, canvas = section.querySelector('canvas');
  const ctx = canvas.getContext('2d'), play = section.querySelector('.play');
  const seek = section.querySelector('.seek'), out = section.querySelector('output');
  let report, frames, images, ready, running = false, current = 0, origin = 0, generation = 0;
  const stop = () => { running = false; play.textContent = '播放原速画面'; };
  const release = () => {
    stop(); ready = null; generation++;
    // A decoded 720p frame uses several MB. Keep only one excerpt decoded;
    // the canvas retains its last image when the other frames are released.
    if (images) images = new Array(images.length);
  };
  const show = (ms) => {
    current = Math.min(Number(seek.max), Math.max(0, ms));
    let frame = 0;
    while (frame + 1 < frames.length && frames[frame + 1].time_ms <= current) frame++;
    if (images[frame]?.complete && images[frame].naturalWidth) ctx.drawImage(images[frame], 0, 0, canvas.width, canvas.height);
    seek.value = String(current); out.value = `${(current / 1000).toFixed(2)} 秒 · ${frame + 1}/${frames.length}`;
  };
  const loadImage = (frame) => new Promise((resolve, reject) => {
    const image = new Image(); image.onload = () => resolve(image); image.onerror = reject;
    image.src = `${task}/${frame.file}`;
  });
  fetch(`${task}/report.json`).then(r => { if (!r.ok) throw Error(r.status); return r.json(); }).then(async r => {
    report = r; frames = r.frames; images = new Array(frames.length);
    images[0] = await loadImage(frames[0]); show(0);
  }).catch(() => {out.value = '画面记录加载失败'; play.disabled = true;});
  const preload = async () => {
    if (!report) return false;
    if (activePlayer !== release) {activePlayer?.(); activePlayer = release;}
    const version = generation;
    if (!ready) ready = Promise.all(frames.map((f, i) => images[i] ? Promise.resolve(images[i]) : loadImage(f))).then(all => {if (version === generation) images = all;});
    play.disabled = true; play.textContent = '正在准备画面';
    try { await ready; return version === generation && activePlayer === release; } catch { out.value = '有画面未能加载'; return false; }
    finally { play.disabled = false; play.textContent = '播放原速画面'; }
  };
  const tick = now => {
    if (!running) return;
    show(now - origin);
    if (current >= Number(seek.max)) {stop(); return;}
    requestAnimationFrame(tick);
  };
  play.onclick = async () => {
    if (running) {stop(); return;}
    if (!await preload()) return;
    if (current >= Number(seek.max)) current = 0;
    running = true; play.textContent = '暂停画面'; origin = performance.now() - current;
    requestAnimationFrame(tick);
  };
  seek.oninput = async () => {stop(); const target = Number(seek.value); if (await preload()) show(target);};
  const step = async direction => {
    stop(); if (!await preload()) return;
    let i = frames.findIndex(f => f.time_ms >= current);
    if (i < 0) i = frames.length - 1;
    i = Math.min(frames.length - 1, Math.max(0, i + direction)); show(frames[i].time_ms);
  };
  section.querySelector('.previous').onclick = () => step(-1);
  section.querySelector('.next').onclick = () => step(1);
  document.addEventListener('visibilitychange', () => {if (document.hidden) stop();});
}
