/*
 * providers.js — one adapter per disposable-mail backend.
 *
 * Each adapter normalises a different API into the same shape so the UI never
 * knows which one it is talking to:
 *
 *   id, label, host, capabilities
 *   probe()                        cheap reachability check
 *   domains()                      -> string[]
 *   createMailbox({username, domain}) -> { address, creds }
 *   messages(account)              -> Summary[]   newest first
 *   message(account, id)           -> Full
 *   markSeen?(account, id)         server-side read state, when offered
 *   deleteMessage?(account, id)
 *   deleteMailbox?(account)
 *   attachment?(account, att)      -> Blob
 *
 * Summary: { id, from:{name,address}, subject, intro, seen, createdAt, hasAttachments }
 * Full:    Summary & { html, text, attachments:[{id,filename,size,downloadUrl}] }
 *
 * `creds` is an opaque per-provider blob that gets persisted with the mailbox.
 * Adapters that refresh credentials call the `save` callback they are handed.
 */

import { ApiError, request, postJson, graphql } from './http.js';

/* ------------------------------------------------------------------ helpers */

/** "Acme <a@b.test>" -> { name: 'Acme', address: 'a@b.test' } */
function parseAddress(raw) {
  const text = String(raw || '').trim();
  const angled = text.match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  if (angled) {
    return { name: angled[1].replace(/^["']|["']$/g, '').trim(), address: angled[2].trim() };
  }
  return { name: '', address: text };
}

function firstLine(text, limit = 120) {
  return String(text || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit);
}

/**
 * Inline a value as a GraphQL string literal.
 *
 * Passing arguments as literals rather than declared variables means the query
 * does not have to know whether the schema types an argument as String! or ID!
 * — a mismatch there is a validation error, and we cannot test these schemas
 * from here. JSON string escaping is a subset of GraphQL's, so this is safe.
 */
const lit = (value) => JSON.stringify(String(value));

/**
 * Try each query in turn, moving on only when the server rejects it as
 * malformed. Field names differ between these schemas and a wrong guess is a
 * 400, so the fallbacks trade one round trip for not breaking outright.
 */
async function graphqlFirstAccepted(url, queries, label) {
  let lastError;
  for (const query of queries) {
    try {
      return await graphql(url, query, {}, { label, retries: 1 });
    } catch (err) {
      const schemaRejection = err.status === 400 || err.code === 'graphql';
      if (!schemaRejection) throw err;
      lastError = err;
    }
  }
  throw lastError;
}

/** `hydra:member` on API Platform responses, a bare array on newer ones. */
function members(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload['hydra:member'])) return payload['hydra:member'];
  return [];
}

/* ------------------------------------------- mail.tm / mail.gw (same codebase) */

function makeMailTmAdapter({ id, label, base }) {
  const json = (path, opts = {}) =>
    request(base + path, {
      ...opts,
      headers: { Accept: 'application/json', ...(opts.headers || {}) },
      label,
    });

  const authed = (token, path, opts = {}) =>
    json(path, { ...opts, headers: { Authorization: `Bearer ${token}`, ...(opts.headers || {}) } });

  /** Tokens expire; re-authenticate once with the stored password. */
  async function token(account, save) {
    if (account.creds.token) return account.creds.token;
    const session = await postJson(
      `${base}/token`,
      { address: account.address, password: account.creds.password },
      { label }
    );
    if (!session || !session.token) throw new ApiError(`${label} did not return a session token.`);
    save({ ...account.creds, token: session.token, accountId: session.id || account.creds.accountId });
    return session.token;
  }

  async function withToken(account, save, fn) {
    let t = await token(account, save);
    try {
      return await fn(t);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        save({ ...account.creds, token: null });
        t = await token({ ...account, creds: { ...account.creds, token: null } }, save);
        return fn(t);
      }
      throw err;
    }
  }

  function toSummary(m) {
    return {
      id: m.id,
      from: m.from || { name: '', address: '' },
      subject: m.subject || '',
      intro: m.intro || '',
      seen: !!m.seen,
      createdAt: m.createdAt,
      hasAttachments: !!m.hasAttachments,
    };
  }

  return {
    id,
    label,
    host: new URL(base).host,
    base,
    capabilities: { customName: true, serverSeen: true, deleteMessage: true, deleteMailbox: true, attachments: true },

    probe: () => json('/domains?page=1', { retries: 0 }),

    async domains() {
      const payload = await json('/domains?page=1');
      const list = members(payload)
        .filter((d) => d.isActive !== false && d.isPrivate !== true)
        .map((d) => d.domain);
      if (!list.length) throw new ApiError(`${label} has no domains available right now.`);
      return list;
    },

    async createMailbox({ username, domain, password }) {
      const address = `${username}@${domain}`;
      const account = await postJson(`${base}/accounts`, { address, password }, { label });
      const session = await postJson(`${base}/token`, { address, password }, { label });
      return {
        address,
        creds: {
          password,
          token: session.token,
          accountId: (account && account.id) || session.id || null,
        },
      };
    },

    async messages(account, save) {
      const payload = await withToken(account, save, (t) => authed(t, '/messages?page=1'));
      return members(payload).map(toSummary);
    },

    async message(account, save, id) {
      const m = await withToken(account, save, (t) => authed(t, `/messages/${encodeURIComponent(id)}`));
      return {
        ...toSummary(m),
        html: Array.isArray(m.html) ? m.html.join('\n') : m.html || '',
        text: m.text || '',
        attachments: m.attachments || [],
      };
    },

    markSeen(account, save, id) {
      return withToken(account, save, (t) =>
        authed(t, `/messages/${encodeURIComponent(id)}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/merge-patch+json' },
          body: JSON.stringify({ seen: true }),
        })
      );
    },

    deleteMessage(account, save, id) {
      return withToken(account, save, (t) =>
        authed(t, `/messages/${encodeURIComponent(id)}`, { method: 'DELETE' })
      );
    },

    deleteMailbox(account, save) {
      if (!account.creds.accountId) return Promise.resolve();
      return withToken(account, save, (t) =>
        authed(t, `/accounts/${encodeURIComponent(account.creds.accountId)}`, { method: 'DELETE' })
      );
    },

    attachment(account, save, att) {
      const path = att.downloadUrl.startsWith('http')
        ? att.downloadUrl.replace(base, '')
        : att.downloadUrl;
      return withToken(account, save, (t) => authed(t, path, { raw: true, retries: 1 }));
    },
  };
}

/* ------------------------------------------------------------------ maildrop */

/*
 * Maildrop has no accounts at all: every mailbox name is already live, so a
 * "created" mailbox is just a name we remember. Read state is tracked locally
 * because the API does not carry one.
 */
const MAILDROP_ENDPOINT = 'https://api.maildrop.cc/graphql';

const maildrop = {
  id: 'maildrop',
  label: 'maildrop.cc',
  host: 'api.maildrop.cc',
  base: MAILDROP_ENDPOINT,
  capabilities: { customName: true, serverSeen: false, deleteMessage: false, deleteMailbox: false, attachments: false },

  probe: () =>
    graphql(MAILDROP_ENDPOINT, `query{inbox(mailbox:${lit('ping')}){id}}`, {},
      { retries: 0, label: 'maildrop.cc' }),

  domains: async () => ['maildrop.cc'],

  createMailbox: async ({ username }) => ({
    address: `${username}@maildrop.cc`,
    creds: { mailbox: username },
  }),

  async messages(account) {
    const box = lit(account.creds.mailbox);
    const data = await graphqlFirstAccepted(
      MAILDROP_ENDPOINT,
      [
        `query{inbox(mailbox:${box}){id headerfrom subject date}}`,
        `query{inbox(mailbox:${box}){id headerfrom date}}`,
      ],
      'maildrop.cc'
    );

    const inbox = (data && data.inbox) || [];
    return inbox
      .map((m) => ({
        id: m.id,
        from: parseAddress(m.headerfrom),
        subject: m.subject || '',
        intro: '',
        seen: false, // resolved against locally stored ids by the caller
        createdAt: m.date || new Date().toISOString(),
        hasAttachments: false,
      }))
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  },

  async message(account, save, id) {
    const box = lit(account.creds.mailbox);
    const mid = lit(id);

    // The body field is named differently across revisions of this schema, and
    // the subject may only exist on the header type. Narrow down until one is
    // accepted; the caller fills any gap from the inbox listing it already has.
    const data = await graphqlFirstAccepted(
      MAILDROP_ENDPOINT,
      [
        `query{message(mailbox:${box},id:${mid}){id headerfrom subject date body html}}`,
        `query{message(mailbox:${box},id:${mid}){id headerfrom headersubject date body html}}`,
        `query{message(mailbox:${box},id:${mid}){id headerfrom date body html}}`,
        `query{message(mailbox:${box},id:${mid}){id headerfrom date data html}}`,
        `query{message(mailbox:${box},id:${mid}){id html}}`,
      ],
      'maildrop.cc'
    );

    const m = (data && data.message) || {};
    const text = m.body || m.data || '';

    return {
      id: m.id || id,
      from: parseAddress(m.headerfrom),
      subject: m.subject || m.headersubject || '',
      intro: firstLine(text),
      seen: true,
      createdAt: m.date || new Date().toISOString(),
      hasAttachments: false,
      html: m.html || '',
      text,
      attachments: [],
    };
  },
};

/* ------------------------------------------------------------------ dropmail */

/*
 * DropMail issues a session and assigns the address itself, so custom names
 * are not offered. The client token in the URL is any random string.
 */
function dropmailEndpoint() {
  let token = null;
  try {
    token = localStorage.getItem('tempbox.dropmail.token');
  } catch {
    /* storage unavailable — fall through to a per-load token */
  }
  if (!token) {
    const bytes = new Uint8Array(12);
    crypto.getRandomValues(bytes);
    token = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
    try {
      localStorage.setItem('tempbox.dropmail.token', token);
    } catch {
      /* not persisted; a fresh token each load still works */
    }
  }
  return `https://dropmail.me/api/graphql/${token}`;
}

const dropmail = {
  id: 'dropmail',
  label: 'dropmail.me',
  host: 'dropmail.me',
  get base() {
    return dropmailEndpoint();
  },
  capabilities: { customName: false, serverSeen: false, deleteMessage: false, deleteMailbox: false, attachments: false },

  probe: () =>
    graphql(dropmailEndpoint(), '{domains{name}}', {}, { retries: 0, label: 'dropmail.me' }),

  async domains() {
    const data = await graphql(dropmailEndpoint(), '{domains{name}}', {}, { label: 'dropmail.me' });
    const list = ((data && data.domains) || []).map((d) => d.name).filter(Boolean);
    if (!list.length) throw new ApiError('dropmail.me has no domains available right now.');
    return list;
  },

  async createMailbox() {
    // The session's address is assigned by the provider; username is ignored.
    const data = await graphql(
      dropmailEndpoint(),
      'mutation{introduceSession{id expiresAt addresses{address}}}',
      {},
      { label: 'dropmail.me' }
    );

    const session = data && data.introduceSession;
    const address = session && session.addresses && session.addresses[0] && session.addresses[0].address;
    if (!address) throw new ApiError('dropmail.me did not return an address.');

    return { address, creds: { sessionId: session.id, expiresAt: session.expiresAt } };
  },

  async messages(account) {
    const sid = lit(account.creds.sessionId);
    const data = await graphqlFirstAccepted(
      dropmailEndpoint(),
      [
        `query{session(id:${sid}){mails{id fromAddr headerSubject text receivedAt}}}`,
        `query{session(id:${sid}){mails{id fromAddr headerSubject text}}}`,
        `query{session(id:${sid}){mails{id fromAddr text}}}`,
      ],
      'dropmail.me'
    );

    const mails = (data && data.session && data.session.mails) || [];
    return mails
      .map((m) => ({
        id: String(m.id),
        from: parseAddress(m.fromAddr),
        subject: m.headerSubject || '',
        intro: firstLine(m.text),
        seen: false,
        createdAt: m.receivedAt || new Date().toISOString(),
        hasAttachments: false,
      }))
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  },

  async message(account, save, id) {
    const sid = lit(account.creds.sessionId);
    const data = await graphqlFirstAccepted(
      dropmailEndpoint(),
      [
        `query{session(id:${sid}){mails{id fromAddr headerSubject text html receivedAt}}}`,
        `query{session(id:${sid}){mails{id fromAddr headerSubject text receivedAt}}}`,
        `query{session(id:${sid}){mails{id fromAddr text}}}`,
      ],
      'dropmail.me'
    );

    const mails = (data && data.session && data.session.mails) || [];
    const m = mails.find((x) => String(x.id) === String(id));
    if (!m) throw new ApiError('That message is no longer in the session.');

    return {
      id: String(m.id),
      from: parseAddress(m.fromAddr),
      subject: m.headerSubject || '',
      intro: firstLine(m.text),
      seen: true,
      createdAt: m.receivedAt || new Date().toISOString(),
      hasAttachments: false,
      html: m.html || '',
      text: m.text || '',
      attachments: [],
    };
  },
};

/* ------------------------------------------------------------------ registry */

export const PROVIDERS = [
  makeMailTmAdapter({ id: 'mailtm', label: 'mail.tm', base: 'https://api.mail.tm' }),
  makeMailTmAdapter({ id: 'mailgw', label: 'mail.gw', base: 'https://api.mail.gw' }),
  maildrop,
  dropmail,
];

export function providerById(id) {
  return PROVIDERS.find((p) => p.id === id) || PROVIDERS[0];
}

/**
 * Probe every backend at once and report what this device can actually reach.
 * Blockers and CORS rejections are indistinguishable from here, so the result
 * is only ever "answered" or "did not answer".
 *
 * @returns {Promise<Array<{provider: object, ok: boolean, error: Error|null}>>}
 */
export function probeAll() {
  return Promise.all(
    PROVIDERS.map((provider) =>
      provider
        .probe()
        .then(() => ({ provider, ok: true, error: null }))
        .catch((error) => ({ provider, ok: false, error }))
    )
  );
}

export { ApiError };
