# buildinglayer.site — public pages

Two static pages. App Store Connect requires a working URL for each:

| Page | Upload to | Used for |
|---|---|---|
| `privacy.html` | `public_html/public/` | **Privacy Policy URL** (App Store Connect → App Privacy) |
| `support.html` | `public_html/public/` | **Support URL** (App Store Connect → App Information) |

Both are reachable at the clean URL either way: the root `.htaccess` serves a
file found beside it as itself, and maps a static filename into `public/` when
that is where it lives. `public/` is the tidier home — it is the directory that
exists to hold things served to a browser.

Give App Store Connect `https://buildinglayer.site/privacy.html` and
`https://buildinglayer.site/support.html`.

No build step, no dependencies, nothing to install — plain HTML with one
Google Fonts stylesheet. Upload them and they work.

## Before you publish

**The support mailbox must exist.** Both pages give
`support@buildinglayer.site`. Create that address (or an alias) in cPanel →
Email Accounts first. A privacy page whose contact address bounces is a
rejection waiting to happen, and it is the one thing on these pages that can be
wrong without looking wrong.

If you would rather use a different address, change it in three places:

- `site/build-privacy.py` → `SUPPORT_EMAIL`
- `site/support.html` → the two `support@buildinglayer.site` occurrences
- `PRIVACY_POLICY.md` → the Contact Us section

then re-run the generator below.

## Editing the privacy policy

`privacy.html` is **generated** from `PRIVACY_POLICY.md` in the repository root.
Edit the Markdown, never the HTML, then:

```bash
python3 site/build-privacy.py server/public/privacy.html
```

Without an argument it writes to `site/privacy.html`; pass the deployment path
to regenerate in place.

The policy is kept in Markdown because that is what gets reviewed and diffed;
generating the page from it means the published version and the repository copy
cannot drift apart. App Review reads the published one, and a page that
contradicts the app's actual behaviour is a common reason for a hold.

`support.html` is written by hand — edit it directly.

Both pages share `_template.html` (header, footer, styling). Changing it means
re-running the generator for the privacy page, and applying the change by hand
to the support page.

## Keeping them honest

These pages describe what the app does. If any of the following changes, both
pages need revisiting:

- Cloud Backup becoming non-optional, or on by default without asking
- anything new being collected — analytics, crash reporting, any third-party SDK
- accounts, sign-in, or in-app purchases appearing
- the transfer-code flow changing
