/*
 * api.js — provider layer for disposable mailbox backends.
 *
 * mail.tm and mail.gw run the same API surface, so one client speaks to both
 * and we can fail over when one is rate-limited or down. Both enforce roughly
 * 8 requests/second per IP and answer 429 when you exceed it, so every call
 * goes through a serialising queue with a minimum gap and honours Retry-After.
 */

export const PROVIDERS = [
  { id: 'mailtm', label: 'mail.tm', base: 'https://api.mail.tm' },
  { id: 'mailgw', label: 'mail.gw', base: 'https://api.mail.gw' },
];

export function providerById(id) {
  return PROVIDERS.find((p) => p.id === id) || PROVIDERS[0];
}

/** Serialises requests with a floor on the gap between them. */
class RequestQueue {
  constructor(minGapMs) {
    this.minGapMs = minGapMs;
    this.chain = Promise.resolve();
    this.lastStart = 0;
  }

  run(task) {
    const result = this.chain.then(async () => {
      const wait = this.minGapMs - (Date.now() - this.lastStart);
      if (wait > 0) await sleep(wait);
      this.lastStart = Date.now();
      return task();
    });
    // Keep the chain alive even when a task rejects.
    this.chain = result.catch(() => {});
    return result;
  }
}

const queues = new Map();
function queueFor(base) {
  if (!queues.has(base)) queues.set(base, new RequestQueue(140));
  return queues.get(base);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class ApiError extends Error {
  constructor(message, { status = 0, code = 'error', probeUrl = null } = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    // For `network` failures: the URL to open directly, which bypasses CORS and
    // shows what the server actually said.
    this.probeUrl = probeUrl;
  }
}

/**
 * One HTTP call against a provider, queued and retried.
 * Retries on 429 and on 5xx/network faults, up to `retries` times.
 */
async function request(provider, path, { method = 'GET', body, token, raw = false, retries = 3 } = {}) {
  const url = provider.base + path;

  const attempt = async (n) => {
    const headers = { Accept: raw ? '*/*' : 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) {
      headers['Content-Type'] =
        method === 'PATCH' ? 'application/merge-patch+json' : 'application/json';
    }

    let res;
    try {
      res = await fetch(url, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (networkErr) {
      if (n < retries) {
        await sleep(400 * 2 ** n);
        return attempt(n + 1);
      }
      // A thrown fetch is indistinguishable from a CORS rejection, so this
      // covers being offline, the host being blocked (DNS filters and content
      // blockers list disposable-mail domains), and the provider's edge
      // answering with a challenge page that carries no CORS headers.
      throw new ApiError(`Could not reach ${provider.label}.`, {
        code: 'network',
        probeUrl: url,
      });
    }

    if (res.status === 429 && n < retries) {
      const retryAfter = Number(res.headers.get('Retry-After'));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 700 * 2 ** n);
      return attempt(n + 1);
    }

    if (res.status >= 500 && n < retries) {
      await sleep(500 * 2 ** n);
      return attempt(n + 1);
    }

    if (!res.ok) {
      throw new ApiError(await describeFailure(res), {
        status: res.status,
        code: res.status === 429 ? 'rate_limit' : 'http',
      });
    }

    if (raw) return res.blob();
    if (res.status === 204) return null;

    const text = await res.text();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      throw new ApiError('Provider returned a response we could not read.', { code: 'parse' });
    }
  };

  return queueFor(provider.base).run(() => attempt(0));
}

/** Providers answer errors as JSON-LD; dig out something a human can read. */
async function describeFailure(res) {
  let detail = '';
  try {
    const payload = await res.json();
    detail =
      payload['hydra:description'] ||
      payload.detail ||
      payload.message ||
      (payload.violations && payload.violations[0] && payload.violations[0].message) ||
      '';
  } catch {
    /* body was not JSON — fall through to the status text */
  }

  if (res.status === 429) return 'Rate limited by the provider. Slowing down — try again in a moment.';
  if (res.status === 401) return 'Session expired for this mailbox. Re-authenticating…';
  if (res.status === 404) return 'Not found — it may already have been deleted.';
  if (res.status === 422) return detail || 'The provider rejected that address. Try a different one.';
  return detail || `Provider error ${res.status}.`;
}

/** `hydra:member` on older responses, a bare array on newer ones. */
function members(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload['hydra:member'])) return payload['hydra:member'];
  return [];
}

export async function getDomains(provider) {
  const payload = await request(provider, '/domains?page=1');
  return members(payload)
    .filter((d) => d.isActive !== false && d.isPrivate !== true)
    .map((d) => d.domain);
}

export async function createAccount(provider, address, password) {
  return request(provider, '/accounts', { method: 'POST', body: { address, password } });
}

export async function getToken(provider, address, password) {
  const payload = await request(provider, '/token', { method: 'POST', body: { address, password } });
  if (!payload || !payload.token) throw new ApiError('Provider did not return a session token.');
  return payload;
}

export async function listMessages(provider, token, page = 1) {
  const payload = await request(provider, `/messages?page=${page}`, { token });
  return members(payload);
}

export async function getMessage(provider, token, id) {
  return request(provider, `/messages/${encodeURIComponent(id)}`, { token });
}

export async function markSeen(provider, token, id, seen = true) {
  return request(provider, `/messages/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: { seen },
    token,
  });
}

export async function deleteMessage(provider, token, id) {
  return request(provider, `/messages/${encodeURIComponent(id)}`, { method: 'DELETE', token });
}

export async function deleteAccount(provider, token, accountId) {
  return request(provider, `/accounts/${encodeURIComponent(accountId)}`, { method: 'DELETE', token });
}

/** Attachments need the bearer token, so fetch as a blob rather than linking directly. */
export async function fetchAttachment(provider, token, downloadUrl) {
  const path = downloadUrl.startsWith('http')
    ? downloadUrl.replace(provider.base, '')
    : downloadUrl;
  return request(provider, path, { token, raw: true, retries: 1 });
}
