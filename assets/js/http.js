/*
 * http.js — the transport every provider adapter shares.
 *
 * Disposable-mail APIs are rate-limited and flaky, so requests to a given host
 * are serialised with a minimum gap and retried on 429 and 5xx. A thrown fetch
 * carries the probe URL, because the browser will not tell a page whether the
 * failure was DNS, a blocker, or a CORS rejection — opening the URL directly
 * is the only way to find out.
 */

export class ApiError extends Error {
  constructor(message, { status = 0, code = 'error', probeUrl = null } = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.probeUrl = probeUrl;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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
    this.chain = result.catch(() => {}); // keep the chain alive past a rejection
    return result;
  }
}

const queues = new Map();
function queueFor(key) {
  if (!queues.has(key)) queues.set(key, new RequestQueue(140));
  return queues.get(key);
}

/**
 * @param {string} url
 * @param {{method?: string, headers?: object, body?: any, raw?: boolean,
 *          retries?: number, queueKey?: string, label?: string}} opts
 */
export async function request(url, opts = {}) {
  const {
    method = 'GET',
    headers = {},
    body,
    raw = false,
    retries = 3,
    queueKey = new URL(url, location.href).host,
    label = queueKey,
  } = opts;

  const attempt = async (n) => {
    let res;
    try {
      res = await fetch(url, {
        method,
        headers,
        body: body === undefined ? undefined : body,
      });
    } catch {
      if (n < retries) {
        await sleep(400 * 2 ** n);
        return attempt(n + 1);
      }
      throw new ApiError(`Could not reach ${label}.`, { code: 'network', probeUrl: url });
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
      throw new ApiError(await describeFailure(res, label), {
        status: res.status,
        code: res.status === 429 ? 'rate_limit' : 'http',
        probeUrl: url,
      });
    }

    if (raw) return res.blob();
    if (res.status === 204) return null;

    const text = await res.text();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      throw new ApiError(`${label} returned a response we could not read.`, {
        code: 'parse',
        probeUrl: url,
      });
    }
  };

  return queueFor(queueKey).run(() => attempt(0));
}

/** JSON POST helper, used by the REST and GraphQL adapters alike. */
export function postJson(url, payload, opts = {}) {
  return request(url, {
    ...opts,
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...(opts.headers || {}) },
    body: JSON.stringify(payload),
  });
}

/** GraphQL over POST, surfacing the first error as an ApiError. */
export async function graphql(url, query, variables = {}, opts = {}) {
  const payload = await postJson(url, { query, variables }, opts);
  if (payload && Array.isArray(payload.errors) && payload.errors.length) {
    throw new ApiError(payload.errors[0].message || 'The provider rejected that query.', {
      code: 'graphql',
      probeUrl: url,
    });
  }
  return payload ? payload.data : null;
}

async function describeFailure(res, label) {
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
    /* not JSON — fall through to a status-based message */
  }

  if (res.status === 429) return `${label} is rate limiting us. Slowing down — try again shortly.`;
  if (res.status === 401 || res.status === 403) return `${label} refused the request.`;
  if (res.status === 404) return 'Not found — it may already have been deleted.';
  if (res.status === 422) return detail || 'That address was rejected. Try a different one.';
  return detail || `${label} returned error ${res.status}.`;
}
