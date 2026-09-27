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

Pushing to `main` (or to the development branch) runs
`.github/workflows/deploy.yml`, which publishes the repository root to GitHub
Pages. It needs **Settings → Pages → Source: GitHub Actions** set once; after
that every push redeploys.

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

The browser suite (Playwright) covers mailbox creation, persistence across
reloads, arrival notifications, the unread badge, HTML sanitisation and
script-execution blocking, image blocking, attachments, theming and the mobile
layout.
