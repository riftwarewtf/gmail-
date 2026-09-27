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

Four backends sit behind one adapter interface, so the UI never knows which
one is serving it. **Auto** probes all of them at once on load and uses the
first that answers; the picker marks the ones that did not.

| Backend | Accounts | Custom names | Read state | Delete | Attachments |
| --- | --- | --- | --- | --- | --- |
| mail.tm | yes | yes | server | yes | yes |
| mail.gw | yes | yes | server | yes | yes |
| maildrop.cc | none | yes | local | no | no |
| dropmail.me | session | provider-assigned | local | no | no |

mail.tm and mail.gw run the same codebase, so one adapter covers both. maildrop
has no accounts at all — a mailbox name is already live, which also means
anyone using the same name sees the same inbox. dropmail issues a session and
picks the address itself.

Capabilities are declared per adapter and the UI follows them: the name field
disables itself for a backend that assigns addresses, the delete button hides
where deletion is not offered, and read state falls back to localStorage where
the API carries none.

```
index.html
assets/css/style.css
assets/js/
  http.js       shared transport — request queue, 429 backoff, error shaping
  providers.js  one adapter per backend + the reachability probe
  store.js      localStorage persistence + address/password generation
  notify.js     toasts, desktop notifications, chime, favicon badge
  sanitize.js   HTML mail scrubbing and remote-image blocking
  app.js        UI wiring and the polling loop
```

mail.tm and mail.gw cap you at roughly 8 requests/second, so every call is
serialised per host through a queue with a minimum gap and retries on `429`
honouring `Retry-After`. The active mailbox is polled every 3.5s while the tab is
visible, 12s when hidden, with exponential backoff on failure; other mailboxes
are swept every 20s.

Addresses, passwords and session tokens live in `localStorage` on your own
machine. Nothing is sent anywhere except the mail provider.

## Asset versioning

Module URLs carry a `?v=` that matches the **build stamp in the footer**, so a
browser cannot pin the page to a half-old deploy — one stale module would
otherwise hold every import it pulls in. Bump the number in `index.html` and in
the `import` lines of `app.js` and `providers.js` together when shipping a
change that must not be served from cache. The footer stamp tells you at a
glance which deploy a device is actually running.

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

## If it says no provider answered

A browser never tells a page *why* a `fetch` failed, so "could not reach" covers
three different problems. The app probes every backend before concluding
anything, and shows a link straight to one of their endpoints. Open it — what
you see there identifies the cause:

| What the link shows | What it means |
| --- | --- |
| JSON (a list of domains) | The host is fine; the request was blocked in the page. Check for a content blocker or extension. |
| Nothing loads / DNS error | A DNS or content blocker is eating the domain. Disposable-mail hosts are on most blocklists — common with AdGuard, NextDNS, Pi-hole, school and carrier filters. |
| A Cloudflare challenge or "sorry" page | The provider is challenging your IP. Try another network — shared mobile IPs get this a lot. |

All four backends failing at once points at the second row rather than the
provider: they are all well-known disposable-mail hosts, so one blocklist takes
out every one of them together.

## Verification status

The browser suites run against mocked backends, which covers all the app's own
logic. Against the live services:

- **mail.tm / mail.gw** — request shapes follow their documented API.
- **maildrop.cc** — listing and delivery confirmed working against the live
  service. The single-message query returns `400`. Rather than keep guessing at
  a schema that cannot be inspected from a development machine, each GraphQL
  call tries the known selections and then **introspects the type** and builds
  the query from the fields the server reports. The learned shape is cached for
  the rest of the page's life, so the cost is one extra round trip, once.
- **dropmail.me** — written from its published schema, not exercised live.

Arguments are inlined as GraphQL literals rather than declared variables, so a
query cannot fail merely because the schema types an argument `ID!` where we
guessed `String!`. Where a field is missing, the reader fills sender, subject
and date from the inbox listing it already holds, and a body that cannot be
fetched leaves the rest of the message on screen with the server's own error
rather than replacing it.

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

`tests/e2e.js` (40 checks) covers mailbox creation, persistence across
reloads, arrival notifications, the unread badge, HTML sanitisation and
script-execution blocking, image blocking, attachments, theming and the mobile
layout. `tests/e2e-offline.js` covers provider failover and the
unreachable-provider diagnostic across all four backends.
`tests/e2e-maildrop.js` covers the GraphQL selection fallback and the
body-failure path.
