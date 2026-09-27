/*
 * sanitize.js — scrub incoming HTML mail before it is rendered.
 *
 * The message body is ultimately shown inside a sandboxed iframe with scripting
 * switched off, so this is the second of two layers rather than the only one.
 * It also handles remote-image blocking, which is what actually stops tracking
 * pixels from reporting that you opened the mail.
 */

const FORBIDDEN_TAGS = new Set([
  'SCRIPT', 'IFRAME', 'OBJECT', 'EMBED', 'APPLET', 'FORM', 'INPUT', 'BUTTON',
  'SELECT', 'TEXTAREA', 'BASE', 'META', 'LINK', 'FRAME', 'FRAMESET', 'NOSCRIPT',
  'PORTAL', 'SVG', 'MATH',
]);

const SAFE_URL = /^(https?:|mailto:|tel:|cid:|data:image\/(png|jpe?g|gif|webp|bmp);base64,)/i;

/**
 * @param {string} html      raw message HTML
 * @param {boolean} loadImages  when false, remote images are held back
 * @returns {{html: string, blockedImages: number}}
 */
export function sanitizeHtml(html, loadImages) {
  const doc = new DOMParser().parseFromString(String(html || ''), 'text/html');
  let blockedImages = 0;

  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_ELEMENT);
  const doomed = [];
  const blockedImgs = [];

  while (walker.nextNode()) {
    const el = /** @type {Element} */ (walker.currentNode);

    if (FORBIDDEN_TAGS.has(el.tagName)) {
      doomed.push(el);
      continue;
    }

    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      const value = attr.value;

      // Inline event handlers, in any casing.
      if (name.startsWith('on')) {
        el.removeAttribute(attr.name);
        continue;
      }

      if ((name === 'href' || name === 'src' || name === 'srcset' || name === 'action') &&
          value && !SAFE_URL.test(value.trim())) {
        el.removeAttribute(attr.name);
        continue;
      }

      // `style` can pull remote resources via url(); drop those specifically.
      if (name === 'style' && /url\s*\(/i.test(value) && !loadImages) {
        el.setAttribute('style', value.replace(/url\s*\([^)]*\)/gi, 'none'));
      }
    }

    if (el.tagName === 'IMG') {
      const src = el.getAttribute('src') || '';
      if (/^https?:/i.test(src) && !loadImages) {
        blockedImgs.push(el);
        blockedImages += 1;
      }
    }

    if (el.tagName === 'A') {
      el.setAttribute('target', '_blank');
      el.setAttribute('rel', 'noopener noreferrer nofollow');
    }
  }

  // Mutate after walking so the tree walker is not invalidated mid-traversal.
  doomed.forEach((el) => el.remove());

  // A src-less <img> renders as a broken-image icon, which reads as an error
  // rather than a deliberate block — swap in a labelled placeholder instead.
  blockedImgs.forEach((img) => {
    const pill = img.ownerDocument.createElement('span');
    pill.setAttribute('data-blocked', '1');
    pill.textContent = 'image blocked';
    img.replaceWith(pill);
  });

  return { html: doc.body.innerHTML, blockedImages };
}

/** Wrap a message body in a self-contained document for the sandboxed iframe. */
export function buildFrameDocument(bodyHtml, dark) {
  const fg = dark ? '#e7e9ee' : '#16181d';
  const bg = dark ? '#14161b' : '#ffffff';
  const link = dark ? '#7db2ff' : '#1a5fd0';
  const muted = dark ? '#3a3f4b' : '#d9dde5';

  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: ${dark ? 'dark' : 'light'}; }
  html, body { margin: 0; padding: 0; }
  body {
    font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    color: ${fg}; background: ${bg}; padding: 18px; word-break: break-word;
  }
  img { max-width: 100%; height: auto; }
  [data-blocked] {
    display: inline-block; vertical-align: middle;
    border: 1px dashed ${muted}; border-radius: 999px; padding: 2px 10px;
    font-size: 11.5px; opacity: .65; white-space: nowrap;
  }
  a { color: ${link}; }
  table { max-width: 100% !important; border-collapse: collapse; }
  pre, code { white-space: pre-wrap; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  blockquote {
    margin: 0 0 0 8px; padding-left: 12px; border-left: 3px solid ${muted}; opacity: .85;
  }
</style></head><body>${bodyHtml}</body></html>`;
}

/** Plain-text bodies: escape, then linkify. */
export function textToHtml(text) {
  const escaped = String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  const linked = escaped.replace(
    /\b(https?:\/\/[^\s<]+)/g,
    '<a href="$1" target="_blank" rel="noopener noreferrer nofollow">$1</a>'
  );

  return `<div style="white-space:pre-wrap">${linked}</div>`;
}
