/*
 * notify.js — the notification layer.
 *
 * Four channels, each independently degradable: an in-page toast, a desktop
 * notification, a short synthesised chime, and an unread badge painted into the
 * favicon plus the document title. Nothing here throws into the caller; a
 * blocked permission or a suspended audio context just means one channel is
 * quiet.
 */

let audioCtx = null;
let toastHost = null;
let baseTitle = document.title;

/* ------------------------------------------------------------------ toasts */

function ensureToastHost() {
  if (toastHost && document.body.contains(toastHost)) return toastHost;
  toastHost = document.createElement('div');
  toastHost.className = 'toast-host';
  toastHost.setAttribute('role', 'status');
  toastHost.setAttribute('aria-live', 'polite');
  document.body.appendChild(toastHost);
  return toastHost;
}

/**
 * @param {{title: string, body?: string, tone?: 'info'|'good'|'warn'|'mail', onClick?: Function, timeout?: number}} opts
 */
export function toast({ title, body = '', tone = 'info', onClick, timeout = 6000 }) {
  const host = ensureToastHost();
  const el = document.createElement('div');
  el.className = `toast toast--${tone}`;

  const heading = document.createElement('div');
  heading.className = 'toast__title';
  heading.textContent = title;
  el.appendChild(heading);

  if (body) {
    const sub = document.createElement('div');
    sub.className = 'toast__body';
    sub.textContent = body;
    el.appendChild(sub);
  }

  const close = document.createElement('button');
  close.className = 'toast__close';
  close.type = 'button';
  close.setAttribute('aria-label', 'Dismiss');
  close.textContent = '×';
  close.addEventListener('click', (ev) => {
    ev.stopPropagation();
    dismiss();
  });
  el.appendChild(close);

  if (onClick) {
    el.classList.add('toast--clickable');
    el.addEventListener('click', () => {
      onClick();
      dismiss();
    });
  }

  host.appendChild(el);
  requestAnimationFrame(() => el.classList.add('is-in'));

  let timer = setTimeout(dismiss, timeout);
  el.addEventListener('mouseenter', () => clearTimeout(timer));
  el.addEventListener('mouseleave', () => {
    timer = setTimeout(dismiss, 2500);
  });

  function dismiss() {
    clearTimeout(timer);
    el.classList.remove('is-in');
    setTimeout(() => el.remove(), 220);
  }

  return dismiss;
}

/* ------------------------------------------------------------------- sound */

/** Two descending tones — audible without being a jump-scare. */
export function chime() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    if (!audioCtx) audioCtx = new Ctx();
    if (audioCtx.state === 'suspended') audioCtx.resume();

    const now = audioCtx.currentTime;
    [
      { freq: 880, at: 0 },
      { freq: 1318.5, at: 0.11 },
    ].forEach(({ freq, at }) => {
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, now + at);
      gain.gain.setValueAtTime(0.0001, now + at);
      gain.gain.exponentialRampToValueAtTime(0.16, now + at + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + at + 0.32);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(now + at);
      osc.stop(now + at + 0.35);
    });
  } catch {
    /* Audio unavailable — silent is an acceptable outcome. */
  }
}

/** Browsers only allow an AudioContext to start from a user gesture. */
export function primeAudio() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    if (!audioCtx) audioCtx = new Ctx();
    if (audioCtx.state === 'suspended') audioCtx.resume();
  } catch {
    /* no-op */
  }
}

/* ------------------------------------------------------- desktop notifications */

export function desktopSupported() {
  return typeof Notification !== 'undefined';
}

export function desktopPermission() {
  return desktopSupported() ? Notification.permission : 'unsupported';
}

export async function requestDesktopPermission() {
  if (!desktopSupported()) return 'unsupported';
  if (Notification.permission !== 'default') return Notification.permission;
  try {
    return await Notification.requestPermission();
  } catch {
    return Notification.permission;
  }
}

/**
 * @param {{title: string, body?: string, tag?: string, onClick?: Function}} opts
 */
export function desktop({ title, body = '', tag, onClick }) {
  if (!desktopSupported() || Notification.permission !== 'granted') return null;
  try {
    const n = new Notification(title, {
      body,
      tag,
      icon: badgeDataUrl(0, true),
      badge: badgeDataUrl(0, true),
      silent: true, // our own chime handles audio, so we don't stack two sounds
    });
    n.onclick = () => {
      window.focus();
      if (onClick) onClick();
      n.close();
    };
    return n;
  } catch {
    return null;
  }
}

/* ------------------------------------------------ favicon + title unread badge */

let badgeLink = null;

function ensureBadgeLink() {
  if (badgeLink && document.head.contains(badgeLink)) return badgeLink;
  document.querySelectorAll('link[rel~="icon"]').forEach((l) => l.remove());
  badgeLink = document.createElement('link');
  badgeLink.rel = 'icon';
  badgeLink.type = 'image/png';
  document.head.appendChild(badgeLink);
  return badgeLink;
}

/** Draws an envelope, with a count bubble when there is unread mail. */
function badgeDataUrl(count, plain = false) {
  const size = 64;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (!ctx) return '';

  ctx.fillStyle = '#5b8cff';
  roundRect(ctx, 6, 14, 52, 36, 7);
  ctx.fill();

  // Envelope flap.
  ctx.strokeStyle = 'rgba(255,255,255,.92)';
  ctx.lineWidth = 5;
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ctx.moveTo(11, 19);
  ctx.lineTo(32, 36);
  ctx.lineTo(53, 19);
  ctx.stroke();

  if (!plain && count > 0) {
    ctx.fillStyle = '#ff4d4f';
    ctx.beginPath();
    ctx.arc(47, 17, 16, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#fff';
    ctx.font = 'bold 20px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(count > 99 ? '99+' : String(count), 47, 18);
  }

  return canvas.toDataURL('image/png');
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

export function setUnreadBadge(count) {
  try {
    ensureBadgeLink().href = badgeDataUrl(count);
  } catch {
    /* Canvas blocked (some privacy modes) — the title still carries the count. */
  }
  document.title = count > 0 ? `(${count}) ${baseTitle}` : baseTitle;
}

export function setBaseTitle(title) {
  baseTitle = title;
  document.title = title;
}
