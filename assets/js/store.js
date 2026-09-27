/*
 * store.js — mailbox persistence and address generation.
 *
 * Everything lives in localStorage on the viewer's own machine; nothing is ever
 * sent anywhere except the mail provider itself. Passwords are stored because
 * the provider issues short-lived tokens and we need to re-authenticate when
 * one expires.
 */

const KEY = 'tempbox.v1';

const ADJECTIVES = [
  'amber', 'brisk', 'cobalt', 'dusky', 'ember', 'feral', 'glassy', 'hollow',
  'iron', 'jagged', 'kinetic', 'lunar', 'murky', 'nimble', 'opal', 'placid',
  'quiet', 'russet', 'slate', 'tidal', 'umber', 'velvet', 'wired', 'xenon',
  'yonder', 'zephyr', 'crooked', 'drifting', 'errant', 'frosted',
];

const NOUNS = [
  'anchor', 'basin', 'cipher', 'drifter', 'echo', 'falcon', 'gully', 'harbor',
  'inlet', 'junco', 'kestrel', 'lantern', 'marsh', 'nettle', 'orchard', 'pylon',
  'quarry', 'ridge', 'signal', 'thicket', 'undertow', 'vessel', 'willow',
  'yarrow', 'zenith', 'bramble', 'current', 'delta', 'fathom', 'grotto',
];

const FIRST_NAMES = [
  'alex', 'sam', 'jordan', 'casey', 'riley', 'morgan', 'avery', 'quinn',
  'rowan', 'emery', 'hayden', 'parker', 'reese', 'skyler', 'devon', 'blake',
  'noel', 'sasha', 'toby', 'wren',
];

const LAST_NAMES = [
  'hayes', 'brooks', 'vance', 'mercer', 'sloane', 'reyes', 'kane', 'vaughn',
  'ellis', 'doyle', 'farrow', 'grant', 'holt', 'ingram', 'keller', 'lowry',
  'nash', 'pike', 'quill', 'stark',
];

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

/** Crypto-grade digits, so two tabs opened at once don't collide. */
function digits(n) {
  const bytes = new Uint8Array(n);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => String(b % 10)).join('');
}

export function generatePassword(length = 20) {
  const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*';
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

/**
 * Build a local-part in one of three flavours.
 *   word    — amber-thicket41
 *   human   — alex.hayes8134
 *   random  — k7q2m9x4vb1r
 */
export function generateUsername(style = 'word') {
  switch (style) {
    case 'human':
      return `${pick(FIRST_NAMES)}.${pick(LAST_NAMES)}${digits(4)}`;
    case 'random': {
      const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
      const bytes = new Uint8Array(12);
      crypto.getRandomValues(bytes);
      return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
    }
    case 'word':
    default:
      return `${pick(ADJECTIVES)}${pick(NOUNS)}${digits(2)}`;
  }
}

/** Providers only accept a conservative local-part; scrub anything else out. */
export function normalizeUsername(raw) {
  return String(raw || '')
    .toLowerCase()
    .replace(/[^a-z0-9._-]/g, '')
    .replace(/^[._-]+|[._-]+$/g, '')
    .slice(0, 40);
}

function emptyState() {
  return { accounts: [], activeId: null, settings: { sound: true, desktop: false, images: false } };
}

/*
 * A stored mailbox is provider-agnostic:
 *   { id, provider, address, creds, createdAt, unread, knownIds, seenIds, primed }
 * `creds` is whatever that provider's adapter needs to get back in — a password
 * and token for mail.tm, just a mailbox name for maildrop, a session id for
 * dropmail.
 */

function read() {
  try {
    const parsed = JSON.parse(localStorage.getItem(KEY) || 'null');
    if (!parsed || !Array.isArray(parsed.accounts)) return emptyState();
    return { ...emptyState(), ...parsed, settings: { ...emptyState().settings, ...parsed.settings } };
  } catch {
    // Private mode, cleared site data, or a corrupt entry — start clean.
    return emptyState();
  }
}

function write(state) {
  try {
    localStorage.setItem(KEY, JSON.stringify(state));
  } catch {
    /* Storage unavailable or full; the session still works in memory. */
  }
}

let state = read();

export function getState() {
  return state;
}

export function getAccounts() {
  return state.accounts;
}

export function getActive() {
  return state.accounts.find((a) => a.id === state.activeId) || null;
}

export function setActive(id) {
  state.activeId = id;
  write(state);
}

export function addAccount(account) {
  state.accounts.unshift(account);
  state.activeId = account.id;
  write(state);
  return account;
}

export function updateAccount(id, patch) {
  const account = state.accounts.find((a) => a.id === id);
  if (!account) return null;
  Object.assign(account, patch);
  write(state);
  return account;
}

export function removeAccount(id) {
  state.accounts = state.accounts.filter((a) => a.id !== id);
  if (state.activeId === id) state.activeId = state.accounts.length ? state.accounts[0].id : null;
  write(state);
}

export function getSettings() {
  return state.settings;
}

export function setSetting(key, value) {
  state.settings[key] = value;
  write(state);
}

export function exportAccounts() {
  return JSON.stringify(
    state.accounts.map(({ address, provider, creds, createdAt }) => ({
      address,
      provider,
      createdAt,
      creds,
    })),
    null,
    2
  );
}

export function clearAll() {
  state = emptyState();
  write(state);
}
