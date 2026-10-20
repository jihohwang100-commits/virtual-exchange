# Virtual Exchange v2

## Rules included
- Each new account receives ₩300,000 once.
- `ASTR / Aster Robotics` starts at ₩1,500 per share with a 10,000-share supply.
- The creator account owns all 10,000 ASTR shares; ordinary users start with zero shares.
- Order prices must be multiples of ₩10.
- Only a profile with server-side `role='admin'` can publish news using `publish_news`.
- Market state is stored in Supabase, not on the creator's phone.

## Setup
1. Create a Supabase project and open SQL Editor.
2. Before running SQL, edit `creator@example.com` in the `exchange_settings` seed row to the email the creator will use, OR update the setting after running the schema and before the creator signs up.
3. Run `schema.sql` in a fresh project.
4. In `index.html`, set `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY`.
5. Host `index.html` on GitHub Pages or Netlify, then set Supabase Auth Site URL and Redirect URLs to the deployed URL.
6. Create the creator account first using the exact creator email. The trigger grants admin role and 10,000 ASTR shares. Ordinary accounts get ₩300,000 and no shares.
7. If creator already registered before the schema was installed, follow the commented backfill SQL in `schema.sql` and replace the email placeholder carefully.

## Important limitations
This is a starter, not yet a complete live exchange. `place_limit_order` reserves cash/shares and records a limit order, but an order matching engine is not included yet. It therefore does not execute buys/sells or update the market price. Before public use, add and test a transactional matching engine, order cancellation/refunds, partial fills, position/cash settlement, price-history writes, grouped bid/ask depth, and realtime subscriptions.
- All users' trading history and market state persist in the database while any phone is offline.
- News publishing is enforced by a server-side RPC and admin role. Do not trust a hidden UI button as security.
- Never put the Supabase `service_role` key in browser code.
- Use RLS and test with separate normal-user and admin accounts before sharing.
