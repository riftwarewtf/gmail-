/*
 * app.js — wiring: generator, inbox polling, reader, notifications.
 */

import * as api from './api.js';
import * as store from './store.js';
import * as notify from './notify.js';
import { sanitizeHtml, buildFrameDocument, textToHtml } from './sanitize.js';

/* --------------------------------------------------------------- elements */

const $ = (id) => document.getElementById(id);

const el = {
  layout: $('layout'),
  providerSelect: $('provider-select'),
  toggleSound: $('toggle-sound'),
  toggleDesktop: $('toggle-desktop'),
  toggleTheme: $('toggle-theme'),

  usernameInput: $('username-input'),
  rerollBtn: $('reroll-btn'),
  styleSelect: $('style-select'),
  domainSelect: $('domain-select'),
  createBtn: $('create-btn'),
  generatorHint: $('generator-hint'),

  accountList: $('account-list'),
  accountCount: $('account-count'),
  accountEmpty: $('account-empty'),
  exportBtn: $('export-btn'),

  addressBar: $('address-bar'),
  backBtn: $('back-btn'),
  activeAddress: $('active-address'),
  activeProvider: $('active-provider'),
  liveStatus: $('live-status'),
  liveStatusText: $('live-status-text'),
  copyBtn: $('copy-btn'),
  refreshBtn: $('refresh-btn'),
  deleteAccountBtn: $('delete-account-btn'),

  messageList: $('message-list'),
  inboxPlaceholder: $('inbox-placeholder'),

  reader: $('reader'),
  readerClose: $('reader-close'),
  readerSubject: $('reader-subject'),
  readerFrom: $('reader-from'),
  readerImages: $('reader-images'),
  readerDelete: $('reader-delete'),
  readerAttachments: $('reader-attachments'),
  readerFrame: $('reader-frame'),
};

/* ------------------------------------------------------------------ state */

const ui = {
  messages: [],          // messages of the active mailbox, newest first
  openMessageId: null,
  openMessageFull: null,
  imagesForOpen: false,  // per-message override of the global image setting
  domains: [],
  pollTimer: null,
  pollFailures: 0,
  lastBackgroundSweep: 0,
  busy: false,
  accountSignature: null,  // guards against redundant sidebar re-renders
  messageSignature: null,  // ditto for the message list
};

const THEME_KEY = 'tempbox.theme';

/* ------------------------------------------------------------------ helpers */

function activeProvider() {
  return api.providerById(el.providerSelect.value);
}

function providerFor(account) {
  return api.providerById(account.provider);
}

function relativeTime(iso) {
  const then = new Date(iso).getTime();
  if (!Number.isFinite(then)) return '';
  const secs = Math.max(0, Math.round((Date.now() - then) / 1000));
  if (secs < 45) return 'just now';
  const mins = Math.round(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(then).toLocaleDateString();
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function senderName(msg) {
  const from = msg && msg.from;
  if (!from) return 'Unknown sender';
  return from.name || from.address || 'Unknown sender';
}

function senderLine(msg) {
  const from = msg && msg.from;
  if (!from) return '';
  return from.name && from.address ? `${from.name} <${from.address}>` : from.address || from.name || '';
}

function setStatus(text, kind = '') {
  el.liveStatusText.textContent = text;
  el.liveStatus.classList.toggle('is-live', kind === 'live');
  el.liveStatus.classList.toggle('is-error', kind === 'error');
}

function setHint(text, isError = false, link = null) {
  el.generatorHint.textContent = text;
  el.generatorHint.classList.toggle('hint--error', isError);

  if (link) {
    el.generatorHint.appendChild(document.createTextNode(' '));
    const a = document.createElement('a');
    a.href = link.href;
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.textContent = link.label;
    el.generatorHint.appendChild(a);
  }
}

function describe(err) {
  return err instanceof api.ApiError || err instanceof Error
    ? err.message
    : 'Something went wrong.';
}

/* ------------------------------------------------------------------- theme */

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  try { localStorage.setItem(THEME_KEY, theme); } catch { /* ignore */ }
  if (ui.openMessageFull) renderBody(ui.openMessageFull);
}

function initTheme() {
  let saved = null;
  try { saved = localStorage.getItem(THEME_KEY); } catch { /* ignore */ }
  if (!saved) {
    saved = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches
      ? 'light'
      : 'dark';
  }
  applyTheme(saved);
}

/* ------------------------------------------------------------ auth plumbing */

/** Returns a usable token for the mailbox, re-authenticating if the old one died. */
async function tokenFor(account) {
  if (account.token) return account.token;
  const provider = providerFor(account);
  const session = await api.getToken(provider, account.address, account.password);
  store.updateAccount(account.id, { token: session.token, accountId: session.id || account.accountId });
  return session.token;
}

/** Runs `fn(token)`, refreshing the token once if the provider says it expired. */
async function withToken(account, fn) {
  let token = await tokenFor(account);
  try {
    return await fn(token);
  } catch (err) {
    if (err instanceof api.ApiError && err.status === 401) {
      store.updateAccount(account.id, { token: null });
      token = await tokenFor(account);
      return fn(token);
    }
    throw err;
  }
}

/* ---------------------------------------------------------------- domains */

async function loadDomains({ allowFailover = true } = {}) {
  const provider = activeProvider();
  el.domainSelect.innerHTML = '<option value="">loading…</option>';
  el.createBtn.disabled = true;

  try {
    const domains = await api.getDomains(provider);
    if (!domains.length) throw new api.ApiError('No domains are available right now.');
    ui.domains = domains;
    el.domainSelect.innerHTML = domains
      .map((d) => `<option value="${d}">@${d}</option>`)
      .join('');
    el.createBtn.disabled = false;
    setHint('Addresses are real and receive real mail.');
    return;
  } catch (err) {
    ui.domains = [];
    el.domainSelect.innerHTML = '<option value="">unavailable</option>';
    el.createBtn.disabled = true;

    // An unreachable provider is worth one silent try on the other one before
    // bothering the user about it.
    if (allowFailover && err.code === 'network') {
      const other = api.PROVIDERS.find((p) => p.id !== provider.id);
      if (other) {
        el.providerSelect.value = other.id;
        notify.toast({
          title: `${provider.label} unreachable`,
          body: `Trying ${other.label} instead.`,
          tone: 'warn',
          timeout: 4000,
        });
        return loadDomains({ allowFailover: false });
      }
    }

    if (err.code === 'network') {
      // The browser will not say why a fetch failed, so point at the one check
      // that distinguishes a blocker from the provider refusing the request.
      setHint(
        `Could not reach ${provider.label}, and the browser will not say why. ` +
        'Most often a DNS or content blocker — disposable-mail domains are on ' +
        'most blocklists — or the provider challenging your IP. Open this to ' +
        'see what the server actually returns:',
        true,
        { href: err.probeUrl || `${provider.base}/domains`, label: `${provider.label}/domains ›` }
      );
    } else {
      setHint(`${describe(err)} Try the other provider.`, true);
    }
  }
}

/* ------------------------------------------------------------ create flow */

async function createMailbox() {
  if (ui.busy) return;
  const provider = activeProvider();
  const domain = el.domainSelect.value;
  if (!domain) {
    setHint('No domain available — switch provider and try again.', true);
    return;
  }

  const typed = store.normalizeUsername(el.usernameInput.value);
  const custom = typed.length >= 3;
  let username = custom ? typed : store.generateUsername(el.styleSelect.value);

  ui.busy = true;
  el.createBtn.classList.add('is-busy');
  el.createBtn.disabled = true;
  notify.primeAudio(); // this click is our chance to unlock audio

  try {
    let created = null;
    // A generated name that collides is worth one silent retry; a typed one is not.
    for (let attempt = 0; attempt < (custom ? 1 : 3); attempt += 1) {
      const address = `${username}@${domain}`;
      const password = store.generatePassword();
      try {
        const account = await api.createAccount(provider, address, password);
        const session = await api.getToken(provider, address, password);
        created = {
          id: `${provider.id}:${address}`,
          accountId: (account && account.id) || session.id || null,
          address,
          password,
          provider: provider.id,
          token: session.token,
          createdAt: new Date().toISOString(),
          unread: 0,
          knownIds: [],
          primed: false,
        };
        break;
      } catch (err) {
        const collision = err instanceof api.ApiError && (err.status === 422 || err.status === 400);
        if (!collision || custom || attempt === 2) throw err;
        username = store.generateUsername(el.styleSelect.value);
      }
    }

    if (!created) throw new api.ApiError('Could not find a free address. Try again.');

    if (store.getAccounts().some((a) => a.id === created.id)) {
      setHint('That mailbox is already in your list.', true);
      store.setActive(created.id);
    } else {
      store.addAccount(created);
      setHint('Mailbox ready — send something to it.');
      notify.toast({ title: 'Mailbox created', body: created.address, tone: 'good' });
    }

    el.usernameInput.value = '';
    renderAccounts();
    await selectAccount(store.getActive().id);
  } catch (err) {
    setHint(describe(err), true);
    notify.toast({ title: 'Could not create mailbox', body: describe(err), tone: 'warn' });
  } finally {
    ui.busy = false;
    el.createBtn.classList.remove('is-busy');
    el.createBtn.disabled = false;
  }
}

/* -------------------------------------------------------- account rendering */

function renderAccounts(force = false) {
  const accounts = store.getAccounts();
  const active = store.getActive();

  // Polling runs every few seconds; rebuilding an unchanged list would fight
  // the user for hover, focus and text selection.
  const signature = accounts
    .map((a) => `${a.id}|${a.unread || 0}|${a.id === (active && active.id) ? 1 : 0}`)
    .join(',');
  if (!force && signature === ui.accountSignature) return;
  ui.accountSignature = signature;

  el.accountCount.textContent = String(accounts.length);
  el.accountEmpty.hidden = accounts.length > 0;
  el.accountList.innerHTML = '';

  accounts.forEach((account) => {
    const li = document.createElement('li');
    li.className = 'account' + (active && account.id === active.id ? ' is-active' : '');
    li.tabIndex = 0;
    li.setAttribute('role', 'button');

    const main = document.createElement('div');
    main.className = 'account__main';

    const address = document.createElement('span');
    address.className = 'account__address';
    address.textContent = account.address;
    address.title = account.address;

    const meta = document.createElement('span');
    meta.className = 'account__meta';
    meta.textContent = `${api.providerById(account.provider).label} · ${relativeTime(account.createdAt)}`;

    main.append(address, meta);

    const badge = document.createElement('span');
    badge.className = 'account__badge';
    badge.textContent = account.unread > 99 ? '99+' : String(account.unread || 0);
    badge.hidden = !account.unread;

    li.append(main, badge);

    const open = () => selectAccount(account.id);
    li.addEventListener('click', open);
    li.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        open();
      }
    });

    el.accountList.appendChild(li);
  });

  refreshUnreadBadge();
}

function refreshUnreadBadge() {
  const total = store.getAccounts().reduce((sum, a) => sum + (a.unread || 0), 0);
  notify.setUnreadBadge(total);
}

/* ------------------------------------------------------- mailbox selection */

async function selectAccount(id) {
  store.setActive(id);
  const account = store.getActive();

  closeReader();
  ui.messages = [];
  ui.messageSignature = null;
  el.messageList.innerHTML = '';

  if (!account) {
    el.addressBar.hidden = true;
    el.inboxPlaceholder.hidden = false;
    renderAccounts();
    return;
  }

  el.addressBar.hidden = false;
  el.activeAddress.textContent = account.address;
  el.activeProvider.textContent = api.providerById(account.provider).label;
  el.inboxPlaceholder.hidden = false;
  el.inboxPlaceholder.querySelector('.placeholder__title').textContent = 'Waiting for mail';
  el.inboxPlaceholder.querySelector('.placeholder__body').textContent =
    `Send anything to ${account.address} — it shows up here within a few seconds.`;

  setStatus('checking…');
  el.layout.classList.add('pane-inbox');
  renderAccounts();

  try {
    await pollAccount(account, { foreground: true });
    ui.pollFailures = 0;
    setStatus('live', 'live');
  } catch (err) {
    // The polling loop below will keep retrying; just say so rather than
    // failing the whole selection.
    setStatus('retrying…', 'error');
  }

  restartPolling();
}

/* ----------------------------------------------------------------- polling */

/**
 * Fetch one mailbox. Returns the messages that are genuinely new since the
 * last sweep, so the caller can decide whether to make noise about them.
 */
async function pollAccount(account, { foreground = false } = {}) {
  const provider = providerFor(account);
  const messages = await withToken(account, (token) => api.listMessages(provider, token, 1));

  // `account` is the live store object, so read this before the update below.
  const wasPrimed = !!account.primed;

  const known = new Set(account.knownIds || []);
  const fresh = messages.filter((m) => !known.has(m.id));

  const allIds = messages.map((m) => m.id);
  // Keep a bounded tail so the store does not grow without limit.
  const nextKnown = Array.from(new Set([...allIds, ...(account.knownIds || [])])).slice(0, 200);
  const unread = messages.filter((m) => !m.seen).length;

  store.updateAccount(account.id, { knownIds: nextKnown, unread, primed: true });

  if (foreground) {
    ui.messages = messages;
    renderMessages(new Set(fresh.map((m) => m.id)));
  }

  renderAccounts();

  // A mailbox loaded for the first time should not announce its backlog.
  return wasPrimed ? fresh : [];
}

function announce(account, fresh) {
  if (!fresh.length) return;
  const settings = store.getSettings();
  const active = store.getActive();
  const isActive = active && active.id === account.id;

  if (settings.sound) notify.chime();

  const first = fresh[0];
  const title = fresh.length === 1
    ? `New mail — ${senderName(first)}`
    : `${fresh.length} new messages`;
  const body = fresh.length === 1
    ? (first.subject || '(no subject)')
    : account.address;

  const open = async () => {
    if (!isActive) await selectAccount(account.id);
    if (fresh.length === 1) openMessage(first.id);
  };

  notify.toast({ title, body: `${body}\n${account.address}`.trim(), tone: 'mail', onClick: open, timeout: 9000 });

  if (settings.desktop) {
    notify.desktop({ title, body: `${body} · ${account.address}`, tag: account.id, onClick: open });
  }
}

function pollDelay() {
  if (ui.pollFailures > 0) {
    return Math.min(4000 * 2 ** ui.pollFailures, 60000);
  }
  return document.hidden ? 12000 : 3500;
}

function restartPolling() {
  clearTimeout(ui.pollTimer);
  ui.pollTimer = setTimeout(pollCycle, pollDelay());
}

async function pollCycle() {
  const active = store.getActive();

  if (active) {
    try {
      const fresh = await pollAccount(active, { foreground: true });
      announce(active, fresh);
      ui.pollFailures = 0;
      setStatus('live', 'live');
    } catch (err) {
      ui.pollFailures += 1;
      setStatus(ui.pollFailures > 2 ? 'offline — retrying' : 'retrying…', 'error');
      if (ui.pollFailures === 3) {
        notify.toast({ title: 'Lost contact with the provider', body: describe(err), tone: 'warn' });
      }
    }
  } else {
    setStatus('idle');
  }

  // Background mailboxes on a slower cadence, so notifications still fire for them.
  if (Date.now() - ui.lastBackgroundSweep > 20000) {
    ui.lastBackgroundSweep = Date.now();
    const others = store.getAccounts().filter((a) => !active || a.id !== active.id);
    for (const account of others) {
      try {
        const fresh = await pollAccount(account);
        announce(account, fresh);
      } catch {
        /* One bad mailbox should not stall the sweep. */
      }
    }
  }

  restartPolling();
}

/* ---------------------------------------------------------- message list */

function renderMessages(freshIds = new Set(), force = false) {
  const previouslySelected = ui.openMessageId;

  const signature = ui.messages
    .map((m) => `${m.id}|${m.seen ? 1 : 0}`)
    .join(',') + `#${previouslySelected || ''}`;
  if (!force && !freshIds.size && signature === ui.messageSignature) return;
  ui.messageSignature = signature;

  el.messageList.innerHTML = '';

  if (!ui.messages.length) {
    el.inboxPlaceholder.hidden = false;
    return;
  }
  el.inboxPlaceholder.hidden = true;

  ui.messages.forEach((msg) => {
    const li = document.createElement('li');
    li.className = 'message';
    if (!msg.seen) li.classList.add('is-unread');
    if (freshIds.has(msg.id)) li.classList.add('is-new');
    if (msg.id === previouslySelected) li.classList.add('is-selected');
    li.tabIndex = 0;
    li.setAttribute('role', 'button');

    const dot = document.createElement('span');
    dot.className = 'message__dot' + (msg.seen ? ' is-read' : '');

    const main = document.createElement('div');
    main.className = 'message__main';

    const top = document.createElement('div');
    top.className = 'message__top';

    const from = document.createElement('span');
    from.className = 'message__from';
    from.textContent = senderName(msg);

    const time = document.createElement('span');
    time.className = 'message__time';
    time.textContent = relativeTime(msg.createdAt);
    time.title = new Date(msg.createdAt).toLocaleString();

    top.append(from, time);

    const subject = document.createElement('div');
    subject.className = 'message__subject';
    subject.textContent = msg.subject || '(no subject)';

    main.append(top, subject);

    if (msg.intro) {
      const intro = document.createElement('div');
      intro.className = 'message__intro';
      intro.textContent = msg.intro;
      main.appendChild(intro);
    }

    li.append(dot, main);

    if (msg.hasAttachments) {
      const clip = document.createElement('span');
      clip.className = 'message__clip';
      clip.textContent = '📎';
      clip.title = 'Has attachments';
      li.appendChild(clip);
    }

    const open = () => openMessage(msg.id);
    li.addEventListener('click', open);
    li.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        open();
      }
    });

    el.messageList.appendChild(li);
  });
}

/* --------------------------------------------------------------- the reader */

async function openMessage(id) {
  const account = store.getActive();
  if (!account) return;

  ui.openMessageId = id;
  ui.imagesForOpen = store.getSettings().images;

  el.reader.hidden = false;
  el.layout.classList.add('reader-open', 'pane-reader');
  el.readerSubject.textContent = 'Loading…';
  el.readerFrom.textContent = '';
  el.readerAttachments.hidden = true;
  el.readerAttachments.innerHTML = '';
  el.readerImages.hidden = true;
  el.readerFrame.removeAttribute('srcdoc');

  renderMessages();

  try {
    const provider = providerFor(account);
    const msg = await withToken(account, (token) => api.getMessage(provider, token, id));
    ui.openMessageFull = msg;

    el.readerSubject.textContent = msg.subject || '(no subject)';
    el.readerFrom.textContent = [
      senderLine(msg),
      new Date(msg.createdAt).toLocaleString(),
    ].filter(Boolean).join(' · ');

    renderAttachments(account, msg);
    renderBody(msg);

    if (!msg.seen) {
      try {
        await withToken(account, (token) => api.markSeen(provider, token, id, true));
        const local = ui.messages.find((m) => m.id === id);
        if (local) local.seen = true;
        store.updateAccount(account.id, {
          unread: Math.max(0, (account.unread || 0) - 1),
        });
        renderMessages();
        renderAccounts();
      } catch {
        /* Marking read is cosmetic; the body is already on screen. */
      }
    }
  } catch (err) {
    el.readerSubject.textContent = 'Could not open message';
    el.readerFrom.textContent = describe(err);
    el.readerFrame.srcdoc = buildFrameDocument(
      textToHtml(describe(err)),
      document.documentElement.dataset.theme !== 'light'
    );
  }
}

function renderBody(msg) {
  const dark = document.documentElement.dataset.theme !== 'light';
  const rawHtml = Array.isArray(msg.html) ? msg.html.join('\n') : msg.html;

  let bodyHtml;
  let blocked = 0;

  if (rawHtml && String(rawHtml).trim()) {
    const clean = sanitizeHtml(rawHtml, ui.imagesForOpen);
    bodyHtml = clean.html;
    blocked = clean.blockedImages;
  } else {
    bodyHtml = textToHtml(msg.text || '(this message has no body)');
  }

  el.readerImages.hidden = !(blocked > 0 && !ui.imagesForOpen);
  el.readerImages.textContent = `Load ${blocked} image${blocked === 1 ? '' : 's'}`;

  el.readerFrame.srcdoc = buildFrameDocument(bodyHtml, dark);
  el.readerFrame.onload = resizeFrame;
}

/** srcdoc frames stay same-origin, so the real content height is readable. */
function resizeFrame() {
  try {
    const doc = el.readerFrame.contentDocument;
    if (!doc) return;
    const height = Math.max(
      doc.body ? doc.body.scrollHeight : 0,
      doc.documentElement ? doc.documentElement.scrollHeight : 0
    );
    if (height > 0) el.readerFrame.style.height = `${height + 24}px`;
  } catch {
    el.readerFrame.style.height = '70vh';
  }
}

function renderAttachments(account, msg) {
  const list = msg.attachments || [];
  if (!list.length) {
    el.readerAttachments.hidden = true;
    return;
  }

  el.readerAttachments.hidden = false;
  el.readerAttachments.innerHTML = '';

  list.forEach((att) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'attachment';

    const name = document.createElement('span');
    name.textContent = att.filename || 'attachment';

    const size = document.createElement('span');
    size.className = 'attachment__size';
    size.textContent = formatBytes(att.size);

    btn.append('📎', name, size);
    btn.addEventListener('click', () => downloadAttachment(account, att, btn));
    el.readerAttachments.appendChild(btn);
  });
}

async function downloadAttachment(account, att, btn) {
  const original = btn.textContent;
  btn.disabled = true;
  try {
    const provider = providerFor(account);
    const blob = await withToken(account, (token) =>
      api.fetchAttachment(provider, token, att.downloadUrl)
    );
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = att.filename || 'attachment';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  } catch (err) {
    notify.toast({ title: 'Download failed', body: describe(err), tone: 'warn' });
  } finally {
    btn.disabled = false;
    btn.textContent = original;
  }
}

function closeReader() {
  ui.openMessageId = null;
  ui.openMessageFull = null;
  el.reader.hidden = true;
  el.layout.classList.remove('reader-open', 'pane-reader');
  el.readerFrame.removeAttribute('srcdoc');
  el.readerFrame.style.height = '';
  renderMessages();
}

async function deleteOpenMessage() {
  const account = store.getActive();
  if (!account || !ui.openMessageId) return;
  const id = ui.openMessageId;

  try {
    const provider = providerFor(account);
    await withToken(account, (token) => api.deleteMessage(provider, token, id));
    ui.messages = ui.messages.filter((m) => m.id !== id);
    closeReader();
    renderMessages();
    notify.toast({ title: 'Message deleted', tone: 'good', timeout: 3000 });
  } catch (err) {
    notify.toast({ title: 'Could not delete message', body: describe(err), tone: 'warn' });
  }
}

async function deleteActiveAccount() {
  const account = store.getActive();
  if (!account) return;
  if (!window.confirm(`Delete ${account.address}? Any mail it holds goes with it.`)) return;

  try {
    const provider = providerFor(account);
    if (account.accountId) {
      await withToken(account, (token) => api.deleteAccount(provider, token, account.accountId));
    }
  } catch {
    // The provider expires mailboxes on its own; drop it locally regardless.
  }

  store.removeAccount(account.id);
  renderAccounts();
  const next = store.getActive();
  if (next) {
    await selectAccount(next.id);
  } else {
    closeReader();
    ui.messages = [];
    el.messageList.innerHTML = '';
    el.addressBar.hidden = true;
    el.layout.classList.remove('pane-inbox');
    el.inboxPlaceholder.hidden = false;
    el.inboxPlaceholder.querySelector('.placeholder__title').textContent = 'No mailbox selected';
    el.inboxPlaceholder.querySelector('.placeholder__body').textContent =
      'Generate one on the left, then send mail to the address.';
    setStatus('idle');
  }
  notify.toast({ title: 'Mailbox deleted', body: account.address, tone: 'good', timeout: 3000 });
}

/* ------------------------------------------------------------------ actions */

async function copyAddress() {
  const account = store.getActive();
  if (!account) return;
  const ok = await writeClipboard(account.address);
  notify.toast({
    title: ok ? 'Address copied' : 'Copy failed',
    body: ok ? account.address : 'Select the address and copy it manually.',
    tone: ok ? 'good' : 'warn',
    timeout: 2600,
  });
}

async function writeClipboard(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* fall through to the legacy path */
  }
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;opacity:0;top:0;left:0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  } catch {
    return false;
  }
}

function exportAccounts() {
  if (!store.getAccounts().length) {
    notify.toast({ title: 'Nothing to export', tone: 'warn', timeout: 2600 });
    return;
  }
  const blob = new Blob([store.exportAccounts()], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `tempbox-mailboxes-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

async function manualRefresh() {
  const account = store.getActive();
  if (!account) return;
  el.refreshBtn.disabled = true;
  setStatus('checking…');
  try {
    const fresh = await pollAccount(account, { foreground: true });
    announce(account, fresh);
    ui.pollFailures = 0;
    setStatus('live', 'live');
  } catch (err) {
    setStatus('error', 'error');
    notify.toast({ title: 'Refresh failed', body: describe(err), tone: 'warn' });
  } finally {
    el.refreshBtn.disabled = false;
    restartPolling();
  }
}

/* -------------------------------------------------------------- settings UI */

function syncSettingButtons() {
  const settings = store.getSettings();
  el.toggleSound.setAttribute('aria-pressed', String(!!settings.sound));
  const granted = notify.desktopPermission() === 'granted';
  el.toggleDesktop.setAttribute('aria-pressed', String(!!settings.desktop && granted));
}

async function toggleDesktopNotifications() {
  const settings = store.getSettings();
  if (settings.desktop) {
    store.setSetting('desktop', false);
    syncSettingButtons();
    return;
  }

  if (!notify.desktopSupported()) {
    notify.toast({ title: 'Desktop notifications unsupported', body: 'This browser does not expose the Notification API.', tone: 'warn' });
    return;
  }

  const permission = await notify.requestDesktopPermission();
  if (permission !== 'granted') {
    notify.toast({
      title: 'Notifications blocked',
      body: 'Allow notifications for this site in your browser settings, then try again.',
      tone: 'warn',
    });
    syncSettingButtons();
    return;
  }

  store.setSetting('desktop', true);
  syncSettingButtons();
  notify.desktop({ title: 'Notifications on', body: 'New mail will pop up here.' });
}

/* ------------------------------------------------------------------- events */

function bindEvents() {
  el.createBtn.addEventListener('click', createMailbox);

  el.usernameInput.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') createMailbox();
  });

  el.rerollBtn.addEventListener('click', () => {
    el.usernameInput.value = store.generateUsername(el.styleSelect.value);
    el.usernameInput.focus();
  });

  el.styleSelect.addEventListener('change', () => {
    if (el.usernameInput.value) {
      el.usernameInput.value = store.generateUsername(el.styleSelect.value);
    }
  });

  el.providerSelect.addEventListener('change', () => {
    try { localStorage.setItem('tempbox.provider', el.providerSelect.value); } catch { /* ignore */ }
    loadDomains();
  });

  el.copyBtn.addEventListener('click', copyAddress);
  el.refreshBtn.addEventListener('click', manualRefresh);
  el.deleteAccountBtn.addEventListener('click', deleteActiveAccount);
  el.exportBtn.addEventListener('click', exportAccounts);

  el.readerClose.addEventListener('click', closeReader);
  el.readerDelete.addEventListener('click', deleteOpenMessage);

  el.readerImages.addEventListener('click', () => {
    ui.imagesForOpen = true;
    if (ui.openMessageFull) renderBody(ui.openMessageFull);
  });

  el.backBtn.addEventListener('click', () => {
    el.layout.classList.remove('pane-inbox', 'pane-reader');
  });

  el.toggleSound.addEventListener('click', () => {
    const next = !store.getSettings().sound;
    store.setSetting('sound', next);
    syncSettingButtons();
    if (next) {
      notify.primeAudio();
      notify.chime();
    }
  });

  el.toggleDesktop.addEventListener('click', toggleDesktopNotifications);

  el.toggleTheme.addEventListener('click', () => {
    applyTheme(document.documentElement.dataset.theme === 'light' ? 'dark' : 'light');
  });

  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape' && !el.reader.hidden) closeReader();
  });

  // Coming back to the tab should feel instant, not "wait for the next tick".
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
      ui.pollFailures = 0;
      restartPolling();
      clearTimeout(ui.pollTimer);
      pollCycle();
    } else {
      restartPolling();
    }
  });

  window.addEventListener('online', () => {
    ui.pollFailures = 0;
    restartPolling();
  });

  // Relative timestamps go stale while the tab sits open.
  setInterval(() => {
    if (!document.hidden && ui.messages.length) renderMessages(new Set(), true);
    renderAccounts(true);
  }, 60000);
}

/* --------------------------------------------------------------------- init */

async function init() {
  initTheme();
  notify.setBaseTitle('TempBox — Disposable Inbox Generator');

  el.providerSelect.innerHTML = api.PROVIDERS
    .map((p) => `<option value="${p.id}">${p.label}</option>`)
    .join('');

  let savedProvider = null;
  try { savedProvider = localStorage.getItem('tempbox.provider'); } catch { /* ignore */ }
  if (savedProvider && api.PROVIDERS.some((p) => p.id === savedProvider)) {
    el.providerSelect.value = savedProvider;
  }

  el.usernameInput.value = store.generateUsername(el.styleSelect.value);

  syncSettingButtons();
  bindEvents();
  renderAccounts();

  await loadDomains();

  const active = store.getActive();
  if (active) {
    await selectAccount(active.id);
  } else {
    setStatus('idle');
    restartPolling();
  }
}

init();
