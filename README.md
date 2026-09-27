# TempBox — disposable inbox generator

Generate throwaway email addresses that receive **real mail**, with live
notifications. No build step, no server, no account — a static page that talks
straight to a public disposable-mail provider from your browser.

![checks](https://img.shields.io/badge/browser%20tests-36%2F36-brightgreen)

## What it does

- **Generates working addresses** on demand — word-pair (`amberthicket41`),
  person-like (`alex.hayes8134`) or random (`k7q2m9x4vb1r`), or type your own.
- **Receives actual email.** Anything sent to a generated address lands in the
  inbox within a few seconds.
- **Notifies you four ways:** an in-page toast, a desktop notification, a
  synthesised chime, and an unread count painted into the favicon and tab title.
- **Keeps many mailboxes at once.** Background mailboxes are polled too, so a
  notification fires even when you are looking at a different inbox.
- **Renders mail safely.** Bodies are sanitised and displayed in a sandboxed
  iframe with scripting disabled; remote images are blocked until you ask for
  them, so tracking pixels do not fire on open.
- **Downloads attachments**, deletes messages and mailboxes, exports every
  address and password as JSON.
- Dark and light themes, and a one-pane-at-a-time layout on phones.

## How it works

`mail.tm` and `mail.gw` expose the same public API, so the client speaks to
either and you can switch provider if one is rate-limited or down.

```
index.html
assets/css/style.css
assets/js/
  api.js        provider layer — request queue, 429 backoff, token refresh
  store.js      localStorage persistence + address/password generation
  notify.js     toasts, desktop notifications, chime, favicon badge
  sanitize.js   HTML mail scrubbing and remote-image blocking
  app.js        UI wiring and the polling loop
```

Both providers cap you at roughly 8 requests/second, so every call is
serialised through a queue with a minimum gap and retries on `429` honouring
`Retry-After`. The active mailbox is polled every 3.5s while the tab is
visible, 12s when hidden, with exponential backoff on failure; other mailboxes
are swept every 20s.

Addresses, passwords and session tokens live in `localStorage` on your own
machine. Nothing is sent anywhere except the mail provider.

## Running it locally

Any static server will do — ES modules need `http://`, not `file://`:

```bash
npx http-server -p 8123 .
# then open http://127.0.0.1:8123
```

## Deploying

`.github/workflows/deploy.yml` publishes the repository root to GitHub Pages on
every push to the default branch.

Pages has to be switched on once by hand — a workflow's `GITHUB_TOKEN` is not
allowed to create a Pages site, so `enablement: true` cannot do it for you:

1. Open <https://github.com/riftwarewtf/gmail-/settings/pages>
2. Under **Build and deployment → Source**, pick **GitHub Actions**
3. Re-run the latest job at
   <https://github.com/riftwarewtf/gmail-/actions> (or push anything)

The site then lands at **https://riftwarewtf.github.io/gmail-/** and every
later push redeploys it automatically.

## If it says a provider is unreachable

A browser never tells a page *why* a `fetch` failed, so "could not reach" covers
three different problems. If the selected provider fails, the app silently tries
the other one; if both fail it shows a link straight to the provider's
`/domains` endpoint. Open it — what you see there identifies the cause:

| What the link shows | What it means |
| --- | --- |
| JSON (a list of domains) | The host is fine; the request was blocked in the page. Check for a content blocker or extension. |
| Nothing loads / DNS error | A DNS or content blocker is eating the domain. Disposable-mail hosts are on most blocklists — common with AdGuard, NextDNS, Pi-hole, school and carrier filters. |
| A Cloudflare challenge or "sorry" page | The provider is challenging your IP. Try another network — shared mobile IPs get this a lot. |

## Notes and limits

- Mailboxes are disposable by design. Providers expire them on their own
  schedule — treat every address as temporary.
- Anyone who knows an address can read its mail. Do not use one for anything
  you care about, and never for password resets on a real account.
- Desktop notifications need permission, and browsers only grant it from a
  click — use the bell button in the header.
- This is a **disposable-mail client**, not a Gmail account generator. It
  creates mailboxes on providers that offer them publicly; it does not create
  accounts on Google or any other provider that does not.

## Testing

`tests/e2e.js` covers mailbox creation, persistence across
reloads, arrival notifications, the unread badge, HTML sanitisation and
script-execution blocking, image blocking, attachments, theming and the mobile
layout. `tests/e2e-offline.js` covers provider failover and the
unreachable-provider diagnostic.
