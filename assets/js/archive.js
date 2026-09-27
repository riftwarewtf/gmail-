/*
 * archive.js — local mail retention.
 *
 * Every backend here drops messages after a few days; the addresses themselves
 * are permanent, the mail is not. So each message is copied into IndexedDB the
 * first time it is seen and kept regardless of what the provider does with it
 * afterwards. An archived-only message still lists and still opens.
 *
 * IndexedDB is unavailable in some private modes and can be evicted under
 * storage pressure, so every call here degrades to a no-op rather than
 * throwing: the archive is a bonus on top of the provider, never a dependency.
 */

const DB_NAME = 'tempbox-archive';
const STORE = 'messages';
const PER_MAILBOX_CAP = 500;

let dbPromise = null;

function open() {
  if (dbPromise) return dbPromise;

  dbPromise = new Promise((resolve) => {
    try {
      if (!('indexedDB' in window)) return resolve(null);
      const req = indexedDB.open(DB_NAME, 1);

      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORE)) {
          const store = db.createObjectStore(STORE, { keyPath: 'key' });
          store.createIndex('accountId', 'accountId', { unique: false });
        }
      };

      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
      req.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });

  return dbPromise;
}

function tx(db, mode) {
  return db.transaction(STORE, mode).objectStore(STORE);
}

function promisify(request) {
  return new Promise((resolve) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(null);
  });
}

const keyFor = (accountId, id) => `${accountId}\u0000${id}`;

/**
 * Store or update one message. A summary is stored on first sight; opening the
 * message later upgrades the same row with the body, so `full` says whether
 * this row is complete.
 */
export async function put(accountId, message, { full = false } = {}) {
  const db = await open();
  if (!db || !message || !message.id) return;

  try {
    const store = tx(db, 'readwrite');
    const existing = await promisify(store.get(keyFor(accountId, message.id)));

    // Never let a later summary overwrite a body we already captured.
    const merged = existing && existing.full && !full
      ? { ...existing, ...message, html: existing.html, text: existing.text,
          attachments: existing.attachments, full: true }
      : { ...(existing || {}), ...message, full: full || !!(existing && existing.full) };

    store.put({
      ...merged,
      key: keyFor(accountId, message.id),
      accountId,
      archivedAt: (existing && existing.archivedAt) || Date.now(),
    });
  } catch {
    /* archive is best-effort */
  }
}

export async function putMany(accountId, messages) {
  for (const message of messages || []) await put(accountId, message);
}

/** Every archived message for a mailbox, newest first. */
export async function list(accountId) {
  const db = await open();
  if (!db) return [];

  try {
    const index = tx(db, 'readonly').index('accountId');
    const rows = await promisify(index.getAll(IDBKeyRange.only(accountId)));
    return (rows || []).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  } catch {
    return [];
  }
}

/** One archived message, or null. Only rows with a body are useful to a reader. */
export async function get(accountId, id, { requireFull = false } = {}) {
  const db = await open();
  if (!db) return null;

  try {
    const row = await promisify(tx(db, 'readonly').get(keyFor(accountId, id)));
    if (!row) return null;
    if (requireFull && !row.full) return null;
    return row;
  } catch {
    return null;
  }
}

export async function remove(accountId, id) {
  const db = await open();
  if (!db) return;
  try {
    tx(db, 'readwrite').delete(keyFor(accountId, id));
  } catch {
    /* best-effort */
  }
}

export async function clearMailbox(accountId) {
  const db = await open();
  if (!db) return;
  try {
    const store = tx(db, 'readwrite');
    const keys = await promisify(store.index('accountId').getAllKeys(IDBKeyRange.only(accountId)));
    (keys || []).forEach((key) => store.delete(key));
  } catch {
    /* best-effort */
  }
}

/** Keep the newest PER_MAILBOX_CAP rows for a mailbox. */
export async function prune(accountId) {
  const rows = await list(accountId);
  if (rows.length <= PER_MAILBOX_CAP) return;
  const doomed = rows.slice(PER_MAILBOX_CAP);
  for (const row of doomed) await remove(accountId, row.id);
}

/**
 * Merge what the provider still has with what we kept. The provider's copy
 * wins where both exist; anything only we have is flagged so the UI can say
 * where it came from.
 */
export async function merge(accountId, liveMessages) {
  const archived = await list(accountId);
  if (!archived.length) return liveMessages;

  const liveIds = new Set(liveMessages.map((m) => m.id));
  const onlyArchived = archived
    .filter((row) => !liveIds.has(row.id))
    .map((row) => ({
      id: row.id,
      from: row.from || { name: '', address: '' },
      subject: row.subject || '',
      intro: row.intro || '',
      seen: row.seen !== false,
      createdAt: row.createdAt,
      hasAttachments: !!row.hasAttachments,
      archived: true,
    }));

  if (!onlyArchived.length) return liveMessages;

  return [...liveMessages, ...onlyArchived].sort(
    (a, b) => new Date(b.createdAt) - new Date(a.createdAt)
  );
}

export async function count(accountId) {
  const rows = await list(accountId);
  return rows.length;
}

/** Everything we hold for a mailbox, as JSON, so it can leave this browser. */
export async function exportMailbox(accountId) {
  const rows = await list(accountId);
  return JSON.stringify(
    rows.map(({ key, accountId: _a, ...rest }) => rest),
    null,
    2
  );
}
