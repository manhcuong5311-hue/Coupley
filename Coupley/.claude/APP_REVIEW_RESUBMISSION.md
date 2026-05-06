# App Store Resubmission — Couple Mood Sync: CoupleyAI

This bundle responds to:
- **Guideline 3.1.2(c)** — Auto-Renewable Subscriptions (paywall disclosure)
- **Guideline 5.1.1(v)** — In-app account deletion

---

## 1. Reviewer Notes (paste into App Store Connect → "Notes for Review")

```
Reviewer notes for Couple Mood Sync: CoupleyAI

This submission addresses both rejection items from the previous review.

Guideline 3.1.2(c) — Subscription paywall

  • All prices, periods, and introductory offers now come from StoreKit
    (Product.displayPrice, SubscriptionPeriod, IntroductoryOffer).
  • The compliance disclosure is rendered directly above the purchase
    button, not in the footer fine print. It states: trial length, post-
    trial price, billing cadence, auto-renewal, and cancellation
    instructions.
  • CTA copy is unambiguous:
        - Yearly plan (with 7-day free trial): "Start 7-Day Free Trial"
        - Monthly plan (no trial):              "Subscribe — $3.99 / month"
    The previous "Continue with Monthly" wording has been removed.
  • Restore Purchases, Manage Subscription, Privacy Policy, and
    Terms of Use links are all visible on the paywall.
  • The same compliant disclosure + CTA wording is used in both the
    onboarding paywall and the standalone paywall opened from Settings.

Guideline 5.1.1(v) — Account deletion

  • Settings → Delete Account opens an in-app deletion flow.
  • The flow has 4 steps:
        1. Warning screen — explains exactly what will be deleted
           (profile, shared mood/memory data, partner connection,
           local data) and that the action is permanent.
        2. Confirmation — user must type "DELETE" to proceed.
           Email/password users also enter their password here.
        3. Re-authentication — Apple/Google users see the system
           sign-in sheet (Firebase Auth requires fresh credentials
           within 5 minutes of delete()).
        4. Deletion pipeline runs:
           a. Soft-disconnect partner (sends "your partner has
              disconnected" notice via Firestore).
           b. Hard-delete couple-shared data: messages, moods,
              reactions, syncScores, quizzes, coupleProfile,
              notifications.
           c. Delete pairing codes the user created.
           d. Clear premium ownership slot.
           e. Delete /users/{uid} Firestore document.
           f. Revoke Apple Sign-in token (for SIWA accounts) using
              Auth.auth().revokeToken(withAuthorizationCode:).
           g. Delete Firebase Auth user via user.delete().
        5. Success screen — auth state listener routes the app back
           to the Welcome screen.
  • The deletion is irreversible. Users are reminded that an active
    paid subscription must be canceled separately in
    Settings → Apple ID → Subscriptions.

Reproduction steps for review:

  Paywall:
    1. Launch the app → onboarding shows the paywall as its final step.
    2. Tap each plan to verify dynamic pricing + the disclosure block
       that appears above the CTA changes accordingly.
    3. Alternatively: Settings → Upgrade to Premium opens the same
       paywall outside onboarding.
    4. Tap "Start 7-Day Free Trial" → the StoreKit purchase sheet
       should appear with the introductory offer visible.

  Account deletion:
    1. Sign in with any provider (Apple, Google, or email/password).
    2. Open Settings (gear icon, top-right).
    3. Scroll to the bottom — "Delete Account" is the last item.
    4. Tap it → warning screen.
    5. Toggle "I understand…" → tap Continue.
    6. Type DELETE in capital letters.
       (For email accounts: also enter the account password.)
    7. Tap "Permanently Delete My Account".
       For Apple/Google: the system re-auth sheet appears.
    8. Wait for the success screen, then tap Done.
    9. The app returns to the Welcome screen and you can no longer
       sign back in with the deleted credentials.

Demo account (if needed):
  Email:    appreview-couple-a@coupley.app
  Password: REVIEW-2026!Coupley
  Email:    appreview-couple-b@coupley.app
  Password: REVIEW-2026!Coupley
  Pairing code: shown after the first account signs in. Use the second
  account to enter the code; the two accounts will be paired.

Thank you for the additional review.
```

> Note: replace the demo accounts above with your actual review accounts. If you don't use review accounts, remove that block entirely.

---

## 2. Reply to the Apple reviewer (Resolution Center message)

```
Hello,

Thank you for the detailed review feedback. We have addressed both
guideline issues and the changes are included in this build.

Guideline 3.1.2(c) — Subscription paywall

We rebuilt the paywall to comply with auto-renewable subscription
disclosure rules:

  • Prices, billing periods, and the 7-day free trial are now sourced
    from StoreKit (Product.displayPrice and IntroductoryOffer), so
    users always see the exact price for their storefront.
  • An information panel sits directly above the Subscribe / Start
    Trial button. For the yearly plan it reads: "7-day free trial,
    then $29.99 / year, auto-renewing. Cancel anytime in Settings at
    least 24 hours before the period ends." The monthly plan disclosure
    omits the trial line.
  • The button label is unambiguous: "Start 7-Day Free Trial" when an
    introductory offer applies, otherwise "Subscribe — $3.99 / month".
    The previous "Continue with Monthly" wording has been removed.
  • Restore Purchases, Manage Subscription, Privacy Policy, and Terms
    of Use links are all on the paywall.

Guideline 5.1.1(v) — Account deletion

We added an in-app "Delete Account" option in Settings. The flow:

  1. Explains exactly what will be deleted and that the action is
     permanent.
  2. Requires the user to toggle "I understand" and then type DELETE
     in capital letters as a second confirmation.
  3. Re-authenticates the user (Apple / Google system sheet, or
     password for email accounts).
  4. Deletes all of the user's Firestore data, revokes the Apple
     Sign-in token where applicable, and deletes the Firebase Auth
     account.
  5. Routes the app back to Welcome.

We also remind users with an active paid subscription that they need
to cancel separately in Settings → Apple ID → Subscriptions, since
the App Store handles billing independently of account state.

Step-by-step reproduction is in the App Review notes for this build.

Please let us know if anything else needs adjustment.

Thank you,
The Coupley team
```

---

## 3. Pre-resubmission checklist

Verify each before hitting "Submit for Review":

### Paywall (Guideline 3.1.2(c))
- [ ] Both `com.coupley.premium.monthly` and `com.coupley.premium.yearly`
      are in App Store Connect with status "Ready to Submit" or
      "Approved", localized for every storefront you ship to.
- [ ] The 7-day free trial introductory offer is configured on
      `com.coupley.premium.yearly` for **new subscribers**.
- [ ] On a real device with a sandbox account:
      `Product.SubscriptionInfo.IntroductoryOffer` returns a 7-day
      free trial for the yearly product. Verify by selecting yearly
      in the paywall and confirming the disclosure shows
      "7-day free trial, then $29.99 / year".
- [ ] Selecting monthly shows the price (`$3.99 / month`) with **no**
      trial language.
- [ ] CTA label updates with the selected plan and never says
      "Continue" or "Try now".
- [ ] Tapping Restore Purchases on a fresh install with a previously
      purchased account restores access.
- [ ] Tapping Manage Subscription opens StoreKit's manage sheet
      (or App Store deep link as fallback).
- [ ] Privacy Policy + EULA links open valid pages (verify the URL is
      reachable: https://manhcuong5311-hue.github.io/Coupley/).
- [ ] Footer fine print is present and readable.
- [ ] Onboarding paywall (final step of the welcome flow) has the
      same disclosure + CTA wording as the Settings paywall.

### Account deletion (Guideline 5.1.1(v))
- [ ] Settings → Delete Account is reachable in 1 tap from any
      authenticated state (paired or unpaired).
- [ ] Warning step lists what gets deleted in plain language.
- [ ] "I understand" toggle is required before Continue is enabled.
- [ ] Confirmation step requires typing "DELETE" exactly.
- [ ] For email/password accounts, the password field also appears.
- [ ] For Apple accounts, the system sign-in sheet appears when the
      user taps "Permanently Delete My Account".
- [ ] For Google accounts, the OAuth web flow appears.
- [ ] After successful deletion:
      - [ ] `users/{uid}` no longer exists in Firestore.
      - [ ] Couple-shared data (messages, moods, etc.) is gone for the
            former couple ID.
      - [ ] Pairing codes the user created are gone.
      - [ ] Firebase Auth user is gone (cannot sign in again with the
            same credentials).
      - [ ] For Apple sign-in: revokeToken was called (visible in
            Firebase Auth logs).
      - [ ] App returns to the Welcome screen.
- [ ] Active subscribers see the "remember to cancel your subscription"
      reminder on both the warning and success screens.
- [ ] Re-running the same flow on a paired account also notifies the
      partner via the existing "your partner has disconnected" banner.

### Build hygiene
- [ ] Build configuration is **Release**, not Debug.
- [ ] App version + build number incremented.
- [ ] No NSLog / print statements expose user IDs or tokens in
      release logs.
- [ ] Sandbox testing on a real device, not just the simulator
      (StoreKit configuration files behave differently on hardware).

---

## 4. Suggested screen-recording flow

A 60–90 second recording is enough. Apple Review prefers a single
unbroken clip that shows both fixes end-to-end.

### Recording 1 — Paywall compliance (~30s)
1. Launch the app from a fresh install or signed-out state.
2. Reach the paywall (either through onboarding's final step or via
   Settings → Upgrade to Premium).
3. Show the **yearly plan selected** — point the cursor / pause for
   ~2s on the disclosure line above the button so reviewers can read
   "7-day free trial, then $29.99 / year, auto-renewing. Cancel
   anytime in Settings at least 24 hours before the period ends."
4. Tap **monthly plan** — the disclosure should change to remove the
   trial language and the CTA should update to
   "Subscribe — $3.99 / month".
5. Switch back to yearly. Tap **Start 7-Day Free Trial** to show the
   StoreKit purchase sheet appearing (you can dismiss it without
   completing the purchase).

### Recording 2 — Account deletion (~45s)
1. Sign into any account (Apple is the most thorough demo because it
   exercises revokeToken).
2. Open Settings (gear icon top-right of dashboard).
3. Scroll to **Delete Account** (last row).
4. Show the warning screen — let it sit ~2s so the bullet list is
   readable.
5. Toggle "I understand…" → Continue.
6. Type **DELETE** into the field.
7. Tap "Permanently Delete My Account".
8. The Apple re-auth sheet appears — complete it with Face ID / Touch
   ID.
9. The deleting screen shows briefly with status updates.
10. Success screen — tap **Done**.
11. App returns to the Welcome screen.
12. (Optional but powerful) Try to sign in again with the deleted
    Apple ID — Firebase rejects the old credential and treats it as
    a brand-new sign-up, proving deletion took effect.

Save both clips at native iPhone resolution (1170 × 2532 for an
iPhone 15 / 16). Apple accepts .mov or .mp4 up to ~500 MB.

---

## 5. File-by-file change manifest

| File | Change |
|------|--------|
| `Features/Premium/Models/PremiumModels.swift` | Added `fallbackDisplayPrice` / `fallbackPeriodLabel`. `priceLabel` now derives from them. Removed `trialSubtitle`. Updated `savingsBadge` copy. |
| `Features/Premium/PremiumStore.swift` | New helpers: `product(for:)`, `displayPrice(for:)`, `displayPeriod(for:)`, `priceWithPeriod(for:)`, `introductoryOfferDescription(for:)`, `hasIntroductoryOffer(for:)`, `paywallDisclosure(for:)`, `openManageSubscriptions()`. UIKit import added for the manage-subscription scene lookup. |
| `Features/Premium/Views/PremiumPaywallView.swift` | Compliance refactor: dynamic StoreKit pricing, disclosure pinned above CTA, unambiguous CTA labels, Manage Subscription action, Restore Purchases left visible. |
| `Features/Onboarding/Views/OnboardingFlowView.swift` | Same disclosure + CTA wording as the standalone paywall. |
| `Features/Auth/Services/AppleSignInCoordinator.swift` | `AppleSignInResult` now carries Apple's `authorizationCode` for token revoke. |
| `Features/Auth/Services/AccountDeletionService.swift` | **New.** Re-auth + Firestore wipe + Apple revoke + `Auth.delete()`. |
| `Features/Settings/Views/DeleteAccountView.swift` | **New.** 4-step user-facing deletion flow. |
| `Features/Settings/Views/SettingsView.swift` | New `Delete Account` section pushed into the existing settings list. |
| `Core/SessionStore.swift` | Added `prepareForDeletion()` so the `users/{uid}` listener can be detached before the document is deleted (avoids a UI flicker between deletion phases). |
