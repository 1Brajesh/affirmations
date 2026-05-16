# Affirmations Repo Notes

Standalone repo for Brajesh's private affirmations app.

Repo: `https://github.com/1Brajesh/affirmations`

## What This Repo Is

- Static HTML/CSS/JS app.
- No build step.
- No package manifest.
- No automated test suite.
- Uses Supabase for auth and data.
- This repo was extracted from the broader `brajesh` website on 2026-05-08.

## Main Files

- `index.html`
  - page shell, styles, fullscreen DOM, and module include
- `assets/js/brajesh-affirmations.js`
  - main app logic
- `assets/js/brajesh-auth.js`
  - shared Supabase auth/session helper copied from the main Brajesh repo
- `import-template.csv`
  - starter CSV for bulk import
- `supabase/20260504123000_add_brajesh_affirmations.sql`
  - affirmations schema, normalization helpers, indexes, and RLS reference
- `supabase/20260516150000_add_brajesh_user_preferences.sql`
  - per-user preferences table for synced Random theme selections

## Deployment

- This repo is intended to publish via GitHub Pages.
- Before the custom subdomain is added, the expected Pages URL is:
  - `https://1brajesh.github.io/affirmations/`
- After cutover, the intended custom domain is:
  - `https://affirmations.brajesh.com/`
- When the custom domain is ready:
  - add `CNAME` with `affirmations.brajesh.com`
  - point DNS to GitHub Pages
  - add `https://affirmations.brajesh.com/**` to Supabase allowed redirect URLs

## Access Model

- The site is private.
- Login is via Supabase email magic links.
- Admin access is checked against `brajesh_admins` through `public.is_brajesh_admin()`.
- This repo still uses the same Supabase project and the same `brajesh_affirmations` table as the main Brajesh site.
- Magic-link redirect behavior is path-aware:
  - on GitHub Pages project path, it redirects back to `/affirmations/`
  - on a custom subdomain root, it redirects back to `/`

## Data Model

- Table: `public.brajesh_affirmations`
- Main columns:
  - `id`
  - `theme`
  - `body`
  - `body_normalized`
  - `created_at`
  - `updated_at`
- Table: `public.brajesh_user_preferences`
- Main columns:
  - `user_id`
  - `random_theme_selection`
  - `random_theme_selection_customized`
  - `created_at`
  - `updated_at`
- DB uniqueness:
  - unique index on `(theme, body_normalized)`
- RLS:
  - admin-only select/insert/update/delete
  - user preferences are also admin-only, but each admin can only read and write their own preference row

## Main UI Areas

- magic-link login panel
- display setup with theme pills
- add/edit form
- CSV import/export tools
- affirmation library
- fullscreen display mode

## Important Behavior

- Built-in reserved theme:
  - `long`
- `Random` display excludes `long`.
- `Random` theme selections are now stored in `brajesh_user_preferences`, which is the source of truth across devices.
- Duplicate prevention uses normalized `theme + body`.
- CSV import accepts `affirmation,theme` or matching header synonyms.
- `long` affirmations split by authored line breaks and play one line at a time.
- Fullscreen order is shuffled once when display mode opens, then kept stable for the rest of the session.

## Fullscreen Navigation

- Right-side tap/click:
  - next affirmation
- Left-side tap/click:
  - previous affirmation
- Keyboard:
  - `Space`, `ArrowRight`, `ArrowDown` = next
  - `ArrowLeft`, `ArrowUp` = previous
  - `Escape` = exit
- `long` behavior:
  - forward steps line by line before advancing to the next affirmation
  - backward steps line by line before moving to the previous affirmation
  - mobile swipe left skips the rest of the current `long`
  - desktop skip button and `N` also skip the current `long`

## Visual Drift

- As of 2026-05-08, fullscreen mode applies one curated random skin per session.
- Each skin can change:
  - font stack
  - text color
  - accent color
  - subtle corner/background SVG motifs
- Current motif set includes:
  - sun
  - flower
  - leaf
  - wave
  - star
  - ribbon / dance-like mark
- Keep this subtle. The text remains the priority.

## Fragile Areas

- Fullscreen text fitting is historically fragile, especially on iPhone Safari.
- The current fitting logic uses delayed `requestAnimationFrame` sizing and should be treated carefully.
- Any fullscreen layout, font, or padding change should be tested with:
  - short affirmations
  - long affirmations
  - phone-sized viewport
  - desktop fullscreen

## Cache Note

- When affirmations UI changes appear not to register after deploy, check for stale cached JS.
- The page currently cache-busts the module URL in `index.html`:
  - `./assets/js/brajesh-affirmations.js?v=20260508c`
- If future JS changes appear missing in production, bump that query-string version.

## Useful Starting Point

When rehydrating this repo, read:

1. `README.md`
2. `index.html`
3. `assets/js/brajesh-affirmations.js`
4. `assets/js/brajesh-auth.js`
5. `supabase/20260504123000_add_brajesh_affirmations.sql`
6. `supabase/20260516150000_add_brajesh_user_preferences.sql`
