# Van Stock Pro — Preview

This repository is isolated from the live Van Stock Pro repository.

## Safety boundary
- This preview must connect only to a dedicated Supabase test project.
- Never copy the live project's URL or publishable key into this repository.
- Never use a Supabase service-role key in browser code.
- Do not merge or deploy preview changes to production without explicit approval.

## Supabase preview setup
1. Create a separate Supabase project for testing.
2. In `supabase-config.js`, replace the two placeholders with that test project's Project URL and publishable (or anon) key.
3. Open `supabase/preview-schema.sql` and run the complete script in the preview project's Supabase SQL Editor only. It creates the app's current cloud tables plus a `job_records` table for the planned job-first workflow. It does not drop or truncate data.
4. In Supabase Authentication settings, choose whether email confirmation is required for test accounts. Create a preview-only test login in the preview app.
5. Add the preview site's URL to the test project's Authentication URL configuration.
4. Add the preview site's URL to the test project's Authentication URL configuration.

Until a separate test project is configured, sign-in and cloud data features are intentionally unavailable. Do not use production credentials as a workaround.
