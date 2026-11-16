# Apna Sajhedari

Responsive partnership-accounting prototype for a small private business group.

## Current build
- Responsive dashboard for phone, tablet and desktop
- Add members and initial capital
- Record business income and expenses
- Automatically calculate each member's capital percentage
- Allocate net profit or loss proportionally to invested capital
- Member-wise report, transaction ledger, JSON backup and restore

## Important: current demo storage
This first version stores data in the browser's local storage on the current device only. It does **not** yet provide shared live data, secure member logins, or cloud backups. Do not enter real/private financial records until cloud authentication, database policies, backups and audit logging are configured and tested.

## Publish with GitHub Pages
1. Open repository Settings → Pages.
2. Under Build and deployment, choose Deploy from a branch.
3. Select branch `main` and folder `/ (root)`, then Save.
4. After deployment, open the Pages URL shown there.

## Next production step
Connect a hosted database and authentication (for example Supabase), enforce per-group access policies, add invitation/join flow, immutable audit history and verified backups. Profit allocation is currently a simple demo formula: (member capital ÷ total member capital) × (income − expenses). Agree on accounting rules and have them reviewed before using it for actual distributions.
