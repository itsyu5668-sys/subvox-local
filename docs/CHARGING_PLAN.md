# Subvox Local — Charging Plan

> **STOP — READ THIS FIRST: THE PAID VERSION IS BLOCKED**
>
> The LRS3 Auto-AVSR weights in this repo (visual-only + audio-visual,
> plus the subword LM built on the same lineage) are **non-commercial
> research use only**. You **cannot legally ship or charge for Subvox
> Local with those weights as-is** — not as a subscription, not as a
> one-time purchase, not as a paid download.
>
> Everything below is a plan for *after* that blocker is resolved.
> There is **no real checkout, no real payment code, and no real
> licence server** in this repo. The checkout URL in this doc is a
> placeholder (`https://example.com/checkout`) that Francis must
> replace. Do not ship a paid version until the LRS3 section below
> is resolved. A research-only free version is the only version
> that can ship today — see "The research-only free version option".
>
> This doc is a plan, not legal advice. If in doubt, get a lawyer
> to confirm the licence position before taking money.

## 1. Pricing recommendation — NOT FINAL

Prices are **proposed, not locked**. Francis can change them in one
place (see the constants below). Do not treat $12 / $99 as final
until the Intel-CPU latency is measured and the commercial model
question is settled — both change what the product is worth.

### Proposed prices

```python
# Pricing constants — single source of truth.
# Change these in one place; do not hard-code prices elsewhere.
PRICE_MONTHLY_USD = 12
PRICE_LIFETIME_USD = 99
TRIAL_DAYS = 7
```

| Option | Price | What it is |
|---|---|---|
| Free trial | $0 for 7 days | Full dictation, no card upfront (see §2) |
| Monthly | **$12 / month** | Ongoing access while subscribed |
| Lifetime (one-time) | **$99 one-time** | Pay once, use forever (see the lifetime caveats in §1.3) |

### 1.1 Why $12/month

Market comparators (prices as recorded from prior research — verify
them again at launch, they change):

- **Wispr Flow Pro: $15/month** (or $144/year). Free tier: $0,
  capped at 2,000 words/week.
- **Wispr Flow Growth: $23–33/month.**
- **Superwhisper: $8.49/month** (or $84.99/year, or $249.99
  lifetime). Local / offline, like Subvox Local.

$12/month sits deliberately between the two:

- **Under Wispr Pro ($15/mo).** Subvox Local cannot credibly
  charge *more* than Wispr Pro today. Wispr is cloud-backed,
  faster on weak hardware, more accurate on general speech, and
  has a team behind it. Charging above $15 before the Intel
  latency and accuracy are measured would be pricing on hope.
- **Above Superwhisper ($8.49/mo).** Superwhisper is the closest
  comp (local, offline dictation) and it is cheaper. $12 is
  justified only if Subvox Local's one thing — *silent*
  lip-reading dictation with no microphone and no sound — is
  worth ~$3.50/month extra to the buyer over Superwhisper's
  voice dictation. That is a real, narrow difference: dictating
  silently in a meeting, a library, a shared room, or late at
  night, where speaking out loud is not an option. If the buyer
  does not need silence, Superwhisper at $8.49 is the better
  deal, and the pricing should say so honestly rather than
  pretend otherwise.
- **Above Wispr Free's word cap, without copying it.** Wispr
  Free gives 2,000 words/week, then stops. Subvox Local's trial
  is time-based (7 days, unlimited words — see §2) instead of
  word-capped, because a word cap punishes exactly the heavy
  users most likely to convert, and because counting words in a
  local-only app adds metering code for no benefit. The trial
  sells the *silence*, not a word allowance.

If Intel-CPU latency turns out slow (see §7, Risks), $12/month
is too high. Re-price down — or fix the speed first — rather
than launching slow at $12.

### 1.2 Why $99 lifetime

- **It is ~8 months of monthly ($12 × 8 = $96).** A buyer who
  stays 9+ months would have paid more on monthly. That is the
  honest break-even to put on the pricing page: "pays for itself
  in about 8 months."
- **It is well under Superwhisper lifetime ($249.99).** That gap
  is the pitch: same local/offline idea, silent instead of
  spoken, at less than half Superwhisper's lifetime price.
  Do not quote Superwhisper's $249.99 as if it will never
  change — re-check it at launch.
- **It is cash up front for Francis.** Lifetime brings money in
  now, with no monthly churn to manage. That matters for a
  one-person product with no billing team.

Lifetime caveats — put these in the terms, not in small print
nobody reads:

- Lifetime means the *current major version* of Subvox Local
  (e.g. v1.x), on macOS, for one person, on up to 2 Macs
  (see §3 for the key rules). It does not promise free upgrades
  forever to a hypothetical v2 rebuild, and it does not promise
  support forever. Say that plainly at purchase time.
- Lifetime buyers are the hardest to support if the commercial
  model swap (see §5) changes accuracy or speed later. Do not
  sell lifetime until the commercial model is chosen and
  measured — otherwise you are selling a promise about a model
  you have not shipped yet.

### 1.3 What is NOT recommended (and why)

- **No free-forever tier with a word cap.** Copying Wispr Free
  (2,000 words/week) would put Subvox Local in a head-to-head
  word-count fight with a much larger, cloud-backed company.
  It loses that fight.
  The 7-day trial is the free tier.
- **No $15+/month at launch.** That is Wispr Pro's price. Until
  Subvox Local is measured on Francis's Intel i5 and beats
  Wispr on the *silent* use case in a real demo, it has not
  earned Wispr's price.
- **No lifetime above $149.** Above that, the buyer starts
  comparing against Superwhisper lifetime ($249.99) and asking
  why a one-person app costs nearly as much. $99 keeps the
  "cheap enough to try" feeling.

### 1.4 Price is config, not code

The constants at the top of this section are the proposal for
where prices should live once payment code exists (one module,
one place — e.g. a `pricing.py` / Swift constants file, to be
created only when the paid build starts). Until then they live
here, in this doc, only.

- Francis changes `PRICE_MONTHLY_USD` / `PRICE_LIFETIME_USD`
  in one place and the UI, checkout description, and receipts
  all read from there. No price is hard-coded in a second file.
- Prices in this doc are in USD. If Stripe / Lemon Squeezy /
  Paddle is set to another currency later, the constants change
  there, not in scattered strings.

## 2. Trial flow — 7 days, no card upfront

### 2.1 The choice: 7 days, full product, no card

- **Length: 7 days** from first launch (first time dictation
  runs, not install time — installing and downloading ~6 GB of
  models can eat a day on slow internet, and the trial should
  not burn while models download).
- **No card upfront.** Asking for a card before the user has
  silently dictated one sentence kills conversion for a
  product whose whole pitch is "try it, it feels like magic."
  It also avoids storing card details for people who never
  convert. Payment details are collected only at purchase,
  on the provider's checkout page (see §4), never inside the app.
- **Full product during trial.** No word cap, no feature lock,
  no watermark. The trial user gets the same fast setup, the
  same LoRA adapt, the same Qwen cleanup. The only difference
  from paid is the clock.

Why 7 days and not 14 or 30:

- 7 days is long enough to do the fast setup (2 minutes),
  dictate in real meetings / real work for a few days, and
  decide. Lip-reading dictation either clicks in the first
  week or it does not — a 30-day trial mostly gives people
  23 extra days to forget about it.
- Wispr Free is effectively an unlimited-time trial with a
  2,000-word/week cap. A 7-day unlimited trial is a *different*
  shape, not a worse one: it trades "free forever, capped"
  for "free for a week, uncapped." That difference should be
  on the pricing page, in plain words.

### 2.2 What counts as trial use

- Trial starts on first successful dictation (or first fast
  setup, whichever is first). Installing the app, downloading
  models, and running `doctor` do **not** start the clock.
- Trial use = dictation (hold-to-talk, paste at cursor) and
  fast setup / LoRA adapt. Browsing settings, reading the
  transcript history, and importing personal text do not
  consume trial — they are setup, not use.
- The trial clock is stored locally (see §3, same key file).
  The app shows "Trial: X days left" in the menu bar, every
  day, so expiry is never a surprise.

### 2.3 What happens after the trial ends

- **Dictation stops.** Holding the hotkey shows a short
  "Trial ended — activate to keep dictating" message, with a
  button to buy / enter a licence key. It does not paste,
  it does not record, it does not silently keep working.
- **Setup stays.** The user's fast-setup LoRA adapt, personal
  LM, corrections, and settings are **kept, not deleted**.
  If they buy later (a week or a month later), they pick up
  where they left off — no re-doing the 10 sentences.
- **No data is held hostage.** Transcript history stays
  readable/exportable after expiry. Locking a user's own
  words behind payment is the fastest way to earn a refund
  demand and a bad review.
- **No auto-charge.** Because no card was taken upfront,
  there is nothing to charge. Expiry is a stop, not a bill.
  Say that on the pricing page: "No card upfront, no
  surprise charge."

### 2.4 Trial abuse — keep it simple

- One trial per Mac (machine identifier stored with the
  trial record, locally). Reinstalling does not reset it.
- Do not build fingerprinting, server-side trial tracking,
  or fraud detection for v1. A local-only app cannot enforce
  trials perfectly, and pretending it can adds complexity
  for little revenue. If trial abuse becomes a real problem
  (not a hypothetical one), revisit it then.

## 3. Licence key flow — offline-first

Design principle: **the licence check must never send audio,
video, transcripts, or dictation history anywhere.** The app is
local-only for dictation, and the licence check must not break
that promise.

### 3.1 Key format (proposal — do NOT generate real keys yet)

```
SUBVOX-XXXX-XXXX-XXXX
```

- Prefix `SUBVOX-`, then 3 groups of 4 characters.
- Characters: uppercase letters + digits, excluding confusing
  ones (no `0`/`O`, no `1`/`I`, no `l`). Example shape only:
  `SUBVOX-7K2Q-9M4D-8X3P` is a *format example, not a real key*.
- **No real keys are generated in this repo.** Keys are issued
  by the payment provider (Stripe / Lemon Squeezy / Paddle —
  see §4) or by a small key-issuing step Francis runs after a
  sale. Do not invent keys, do not commit a key list to git.

### 3.2 Where the key lives

- **Offline key file** in Application Support, e.g.:
  `~/Library/Application Support/Subvox Local/license.json`
  (exact path to be confirmed when the Swift app is built —
  this doc proposes the location, the app does not implement
  it yet).
- The file stores: the key itself, the plan (monthly /
  lifetime), the purchase / expiry date, and the trial start
  date. It stores **no audio, no video, no transcript**.
- The file is plain JSON, human-readable, so Francis (or the
  user, if they ask support) can inspect it without a special
  tool. Do not encrypt it with a key Francis will lose — a
  lost decryption key locks out paying users.

### 3.3 Activation

1. User buys on the checkout page (see §4) and receives the
   key by email from the payment provider.
2. User pastes the key into the app (menu bar → "Activate…")
   or the app picks it up from a "Buy" button that opens the
   checkout link in the browser.
3. App validates the key format locally, writes
   `license.json`, and unlocks dictation immediately.
   **Activation works fully offline** — no internet needed
   at activation time, because the key format + a local
   check is enough for v1 (see §3.5 for the optional online
   check).
4. Monthly keys carry an expiry date (purchase date + 1
   month, or the provider's renewal date). Lifetime keys
   carry no expiry, only the plan name.

### 3.4 Deactivation, restore, and moving Macs

- **Deactivation:** menu bar → "Deactivate licence" removes
  `license.json` (or marks it inactive) and returns the app
  to trial-expired state. Setup data (LoRA, LM, settings)
  is kept, so re-activating later restores full use.
- **Restore:** "Restore purchase" re-prompts for the key.
  There is no App Store receipt to restore from (this is
  not an App Store app in v1), so the key *is* the restore
  mechanism. Tell buyers to keep the email with their key.
- **Moving Macs:** a key works on up to **2 Macs** (the
  buyer's main Mac + one other). That limit is a policy to
  state at purchase, not a technical lock to build in v1 —
  the app does not phone home to count Macs (see §3.5).
  If a buyer needs a third Mac, support issues a new key
  manually. Keep the rule human, not automated, for v1.

### 3.5 Optional online check — and what happens offline

- **Optional, not required.** The app may, *if* the Mac is
  online, do a single lightweight check against the payment
  provider (e.g. "is this key still valid / refunded?").
  That check sends **only the key** — no audio, no video,
  no transcripts, no usage data.
- **Offline = still works.** If there is no internet, or
  the check fails, or the provider is down, the app
  **keeps working** on the local `license.json`. A licence
  check must never lock a paying user out because their
  Wi-Fi dropped or a server was down. This is a hard rule.
- **No check on every launch.** At most once a day, in the
  background, silently. Never block dictation on a check.
- **Refunds:** if a key is refunded, Francis (or the
  provider) marks it invalid; the next online check (if any)
  will see that and the app returns to trial-expired state.
  If the user stays offline forever, the local key keeps
  working — accept that for v1 rather than building a
  licence server to chase it.

### 3.6 What is NOT built yet

No licence code exists in this repo today. No key validation,
no `license.json` writer, no online check, no activation UI.
This section is a spec for the Swift app build — do not treat
it as shipped behaviour.

## 4. Payment provider — placeholder only

### 4.1 The placeholder (do not ship this as-is)

```python
# TODO: Francis must replace this with a real checkout link.
# This is a placeholder. It is NOT a real store.
CHECKOUT_URL = "https://example.com/checkout"
```

- `https://example.com/checkout` is **not a real checkout**.
  It is the standard placeholder domain, used here only so
  the code has somewhere to point until Francis creates a
  real product. Do not publish, share, or link this URL as
  if it were a store.
- **No API keys in the repo.** No Stripe secret key, no
  Lemon Squeezy API key, no Paddle key — not in code, not in
  `.env`, not in docs. If a key is ever needed, it lives in
  the provider dashboard and in Francis's password manager,
  never in git.
- **No invented URLs.** No real Stripe / Lemon Squeezy /
  Paddle product link is claimed in this doc, because none
  exists yet. Any link Francis adds later must be copied
  from the provider dashboard, not typed from memory.

### 4.2 Provider choice — Stripe vs Lemon Squeezy vs Paddle

All three can do the same job for v1: a hosted checkout link,
a one-time ($99) and a recurring ($12/month) product, and an
email with a licence key after purchase. Pick one, not three.

| Provider | Why pick it | Watch out for |
|---|---|---|
| **Stripe** | Most flexible; Payment Links are the fastest way to a checkout URL with no code; best-known by buyers | Francis must handle sales tax / VAT himself (or add Stripe Tax); licence-key email needs Stripe + a small email step (or a tool that sends the key) |
| **Lemon Squeezy** | Merchant of record — handles sales tax / VAT for Francis; built-in licence-key issuing fits §3 well | Smaller than Stripe; check its current pricing / payout terms at signup — do not assume them from this doc |
| **Paddle** | Also merchant of record (tax handled); built for software sales | Similar check-needed on pricing / payouts; more setup than a Stripe Payment Link for a first sale |

Recommendation for v1: **start with whichever Francis can
set up fastest** — for most solo sellers that is Stripe
Payment Links or Lemon Squeezy, because both give a hosted
checkout link with no website and no code. The provider
choice does not change the app: the app only needs the
checkout URL and the key the buyer receives. Do not build
provider-specific code into the app for v1.

### 4.3 Steps to create a real product (Francis, in the dashboard)

Do these only after the LRS3 blocker (§5) is resolved — there
is no point creating a paid product for weights you cannot sell.

1. Create an account with the chosen provider (Stripe,
   Lemon Squeezy, or Paddle) and complete its identity /
   payout verification. This takes days, not minutes — start
   it early, in parallel with the model work.
2. Create **two products** (or one product with two prices):
   - "Subvox Local — Monthly", $12/month, recurring.
   - "Subvox Local — Lifetime", $99 one-time.
   Use the `PRICE_MONTHLY_USD` / `PRICE_LIFETIME_USD`
   constants from §1 — if the price changes in the doc,
   change it in the dashboard too.
3. Create a **hosted checkout link** (Stripe Payment Link /
   Lemon Squeezy checkout URL / Paddle checkout link) for
   each price. Copy the real URL from the dashboard.
4. Set the post-purchase email to include the licence key
   (Lemon Squeezy can issue keys natively; Stripe needs an
   extra step — e.g. a simple email / automation that sends
   the key after payment — do not hand-write keys per sale
   once volume grows).
5. Replace `CHECKOUT_URL` in the app with the real link(s).
   Keep the placeholder in git history only — never ship
   the app with `example.com` as the checkout.
6. Test the full loop with a test payment, a real key email,
   and activation on the Intel Mac, before announcing the
   price anywhere. A checkout that takes money but never
   delivers a working key is worse than no checkout at all.

## 5. LRS3 licence blocker — full explanation

### 5.1 What the blocker is

The lip-reading models in this repo were trained on LRS3
(Lip Reading Sentences 3, BBC television speech). The LRS3
dataset licence permits **non-commercial research use only**.

Affected weights in this repo (see `LICENSES.md` and
`MODELS.md`):

- **Auto-AVSR visual-only** (`models/vsr/`, Amanvir /
  `LRS3_V_WER19.1`, 1,001.9 MB) — the main lip reader.
  **Non-commercial research only. NO commercial use.**
- **Subword RNN LM** (`models/lm/`, Amanvir /
  `lm_en_subword`, 215.1 MB) — same LRS3 lineage.
  Treat as **non-commercial research only**.
- **Auto-AVSR audio-visual** (`models/av/`, 1,776.4 MB,
  whisper mode) — same LRS3 lineage. Treat as
  **non-commercial research only**.
- **AV-HuBERT Large** (`models/avhubert/`, 1,928.1 MB) —
  Apache 2.0 per its HF repo, *but* trained on LRS3, so
  keep the research-use caution for any commercial claim.

Not affected (per their own licences — re-check at launch):

- MediaPipe FaceLandmarker — Apache 2.0.
- Qwen3-0.6B / 1.7B (MLX) — Apache 2.0 (Qwen3, Alibaba).
  Note: on Francis's Intel i5 Mac, MLX does not run — the
  cleanup path is GGUF Qwen via CPU (llama.cpp / Ollama
  style), not MLX. That swap does not change the Qwen
  licence, but it does change speed (see §7).

The **code** in this repo is MIT / Apache 2.0 and is not the
blocker. The **weights** are the blocker.

### 5.2 What it blocks

- **Charging for the app** in any form — subscription,
  one-time, paid download — while it ships the LRS3 weights.
- **Commercial distribution** of the app with those weights
  (Mac App Store, direct download, any paid or commercial
  channel). "Free download but I charge later" does not
  dodge it if the weights are inside the shipped app.
- **Marketing the LRS3 model as a commercial product**,
  including a paid landing page that promises the current
  model's accuracy.

What it does **not** block:

- Francis building it and using it himself, for his own
  use / research, on his own Mac.
- A free, research-only release, clearly labelled as such,
  with no payment, no paid tier, and no commercial claim
  (see §5.4, option d).

### 5.3 Commercial path — options (a) to (d)

Pick **one** before any paid launch. Do not ship paid until
the chosen option is actually done, not just planned.

**(a) Get a licence for the LRS3 weights / a commercial VSR model**

- Contact the licensor / rights holder for the LRS3-trained
  weights and ask what a commercial licence costs and what
  it covers. Expect this to be slow, expensive, or a "no" —
  dataset licences for broadcast (BBC) speech are not
  typically sold to solo developers as a quick purchase.
- Alternative inside (a): licence a *different*, commercially
  licensed VSR model from a vendor that sells one, and swap
  it in place of Auto-AVSR. Price, accuracy, and Intel-CPU
  speed must all be re-measured after the swap.
- First step: find the actual licence contact (LRS3 dataset
  page / the Auto-AVSR authors) and send a short enquiry.
  Do not assume a price until they reply.

**(b) Swap to a commercially licensed model**

- Find a VSR / lip-reading model whose weights are released
  under a licence that permits commercial use (e.g. Apache
  2.0 / MIT weights, or a model trained only on
  commercially-usable data). Verify the licence on the
  model card, not on a blog post about the model.
- Swap it in, re-run the fast-setup + accuracy tests on
  Francis's Intel Mac, and update `MODELS.md` /
  `LICENSES.md` with the new weights and licence.
- Watch out: many "open" VSR models are still trained on
  LRS3 / VoxCeleb / other research-only data. The *weights*
  licence and the *training data* licence are two different
  things — both must allow commercial use.

**(c) Train your own model**

- Train a lip-reading model from scratch (or fine-tune a
  commercially-licensed base) on data Francis has the right
  to use commercially — e.g. self-recorded speech, or a
  dataset with a commercial licence.
- This is the most control and the most work: data
  collection, training compute, and accuracy that will
  almost certainly start *worse* than 19.1% WER on LRS3.
  It is a real option, not a quick fix. Do not promise a
  timeline for it until the data + compute plan exists.
- Only choose (c) if Francis actually wants to be in the
  model-training business. If he wants to ship an app,
  (b) is usually faster.

**(d) Ship a research-only free version now, paid version later**

- Release Subvox Local **free, labelled research-only**,
  with the current LRS3 weights, no payment, no checkout,
  no paid tier, and a clear note that it is non-commercial
  research use.
- Use that free release to learn: does silent dictation work
  on an Intel i5? Do people actually use it daily? What is
  the real WER on silent mouthing (not LRS3 filmed speech)?
- **Then**, once (a), (b), or (c) is done, ship the paid
  version with the commercial weights. The free users are
  the audience for the paid launch — but do not promise them
  a paid upgrade date until the model swap is real.

Option (d) is the only option that lets anything ship today.
Options (a)–(c) are the only options that let anything be
*sold*.

### 5.4 What to do first

1. **Decide the path** — (a), (b), (c), or (d)-then-(a/b/c).
   Do not start building checkout code before this decision.
2. If (a): send the licence enquiry this week. The reply
   time is the critical path — everything else waits on it.
3. If (b): shortlist 2–3 commercially-licensed VSR models,
   check each model card + training-data licence, and test
   the best one on the Intel Mac before committing.
4. If (c): scope the data + compute honestly before
   promising anything. If the scope is months, say months.
5. If (d): label the free release "Research only —
   non-commercial" in the README, the app, and any download
   page. Remove all pricing from that release so nobody
   mistakes it for a paid product.
6. **Timeline note: do not ship paid until resolved.**
   No paid launch, no checkout link, no licence-key sales,
   no App Store submission, until the chosen commercial
   path is complete and documented in `LICENSES.md`.
   A paid launch on research-only weights risks a licence
   complaint, a takedown, and refunds to every buyer.

## 6. What Francis still needs

Checklist — nothing in this section is done yet.

- [ ] **Apple Developer account — $99/year.** Needed for
  signing + notarization so macOS does not block the app
  ("cannot be opened because the developer cannot be
  verified"). Without it, one-click install does not work
  like a normal Mac app — users get Gatekeeper warnings and
  have to right-click → Open. Enrol at the Apple Developer
  site; the $99/year is separate from Subvox Local's price
  and is a cost Francis pays whether he sells 0 or 1,000 copies.
- [ ] **Payment provider account** — Stripe, Lemon Squeezy,
  or Paddle (see §4). Complete identity / payout verification
  early; it can take days.
- [ ] **Commercial model decision** — option (a), (b), (c),
  or (d) from §5.3. This is the decision that unblocks (or
  continues to block) charging.
- [ ] **Pricing decision** — confirm $12/month + $99 lifetime
  (or change the constants in §1). Do not launch with a
  price Francis has not explicitly confirmed.
- [ ] **Support email** — a real address buyers can write to
  for lost keys, refunds, and install help (e.g. a dedicated
  support@ address, not a personal inbox that gets lost).
  The key-restore flow in §3 depends on buyers being able
  to reach a human.
- [ ] **Refund policy (suggestion)** — 14-day refund, no
  questions asked, for both monthly (first month) and
  lifetime, if the app does not work on the buyer's Mac.
  Suggested wording: "If Subvox Local doesn't work on your
  Mac, email support within 14 days for a full refund."
  A clear refund policy matters more than a low price for a
  local-only app with a 6 GB download and Intel-CPU speed
  that is still unmeasured. State the policy on the checkout
  page, not only in terms nobody reads. (This is a suggestion
  — Francis decides the final policy.)
- [ ] **Intel Mac test** — measure dictation latency and WER
  on the actual Intel Core i5 Mac (PyTorch CPU for Auto-AVSR,
  GGUF Qwen for cleanup — MLX does not run on Intel).
  Pricing, trial length, and the "better than Wispr" claim
  all depend on these numbers. Do not set a launch date
  before this test.
- [ ] **One-click installer** — a real `.dmg` / `.app` bundle
  (drag to Applications, no Terminal) — the Swift wrapper in
  `swift/SubvoxLocalApp.swift` is a skeleton, untested, and
  does not build an installer yet. Paid users will not run
  `uv run` commands.

## 7. Risks

- **Licence (biggest).** Charging on LRS3 research-only
  weights is not allowed. This blocks all revenue until
  §5 is resolved. Likelihood: certain, if shipped as-is.
  Mitigation: pick (a)/(b)/(c)/(d) now, not at launch.
- **Intel CPU latency vs Wispr cloud speed.** Francis's Mac
  is an **Intel Core i5, not Apple Silicon**. MLX does not
  run on Intel. Auto-AVSR must run on PyTorch CPU and Qwen
  cleanup on GGUF / CPU, which is slower than the Apple
  Silicon path this repo was built for — and slower than
  Wispr's cloud inference. Silent dictation that lags
  several seconds per sentence will not convert a 7-day
  trial. Mitigation: measure latency on the real i5 Mac
  first; if it is too slow, fix speed (smaller / quantized
  model, fewer frames) or lower the price before launch.
- **Competition — Wispr.** Wispr Flow has a free tier,
  a $15/month Pro tier, cloud speed, and a team shipping
  weekly. Subvox Local competes on *one* thing — silence —
  not on speed, accuracy, or features. Do not pitch it as
  a Wispr replacement; pitch it as the silent option Wispr
  does not offer.
- **Competition — Superwhisper.** $8.49/month, $84.99/year,
  $249.99 lifetime, local/offline. Cheaper than the proposed
  $12/month, and already shipping. The $12 price only holds
  if silence is worth the premium to the buyer.
- **Free OS dictation.** macOS built-in Dictation (and
  Voice Control) is free, on every Mac, with no download.
  It needs a microphone and it is not silent — that is the
  only gap. If a buyer is happy speaking out loud, they do
  not need Subvox Local at any price.
- **6 GB model download friction for paid users.** The
  current model bundle is ~6.24 GB (see `MODELS.md`).
  A paying user who waits an hour for a download, then
  hits a slow Intel-CPU first run, is a refund waiting to
  happen. Mitigation: trim the bundle for the paid release
  (ship visual-only + 0.6B cleanup first; make the 1.8 GB AV
  model and 1.7B fallback optional downloads), show a real
  download progress bar, and start the trial clock only
  after models are ready (see §2.2).
- **Accuracy on silent mouthing, not filmed speech.** The
  19.1% WER figure is on LRS3 (clearly filmed speech).
  Silent webcam mouthing is harder — smaller lip movements
  — and the real WER is unmeasured. Do not put "19.1% WER"
  on a pricing page as if it were the user's accuracy.
- **Lifetime pricing risk.** $99 lifetime buyers pay once
  and expect support forever. If the commercial model swap
  (§5) changes the product, lifetime buyers are the first
  to complain. Mitigation: scope lifetime to the current
  major version in the terms (see §1.2).

## 8. Sources — competitor prices

Prices below are **market prices from prior research**, cited
here as comparators. They were not re-checked in this doc —
verify them again at launch, because they change.

- Wispr Flow Free: $0, 2,000 words/week.
- Wispr Flow Pro: $15/month or $144/year.
- Wispr Flow Growth: $23–33/month.
- Superwhisper: $8.49/month, $84.99/year, $249.99 lifetime;
  local / offline.
- Models in this repo: Auto-AVSR visual-only
  (Amanvir/LRS3_V_WER19.1), subword LM (Amanvir/lm_en_subword),
  Qwen3-0.6B-4bit (mlx-community/Qwen3-0.6B-4bit) and
  Qwen3-1.7B-4bit fallback — see `src/subvox_local/cleanup.py`
  (`LOCAL_MODEL`, `LOCAL_MODEL_FALLBACK`) and `MODELS.md`.
- Apple Developer Program: $99/year (standard programme fee —
  confirm on Apple's site at enrolment).

No other competitor prices are claimed in this doc. No
checkout URL, Stripe key, or licence server is claimed to
exist — the only checkout URL in this doc is the
`https://example.com/checkout` placeholder in §4.1.
