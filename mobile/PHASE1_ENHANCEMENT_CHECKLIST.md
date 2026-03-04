# Phase-1 Mobile Enhancement Checklist

## Goal
Stabilize UX on small devices, improve copy consistency, and establish reusable UI architecture without large refactors.

## Scope (Phase-1)
- Wallet pack card stability and responsive behavior
- Core wording consistency (`Expert`, `Listener`, `Speaker`)
- Avatar fallback correctness by gender
- Critical screen CTA clarity and non-overlapping layouts

## Implemented in this phase
- [x] Remove skip action from voice verification UI
  - File: `lib/listener/listener_form/voice_selection_page.dart`
- [x] Update profile label to `Apply As Expert`
  - File: `lib/user/nav/profile.dart`
- [x] Fix wallet recharge badge overlap
  - File: `lib/user/nav/profile/wallet.dart`
- [x] Improve wallet grid behavior for very small screens
  - File: `lib/user/nav/profile/wallet.dart`
- [x] Female avatar fallback/profile option alignment
  - Files:
    - `lib/user/user_form/user_profile.dart`
    - `lib/user/widgets/top_bar.dart`

## Next recommended tasks (high impact)
1. **Create shared design tokens**
   - Add `lib/ui/theme/app_tokens.dart`
   - Move repeated colors/radius/spacing/typography constants from:
     - `lib/user/nav/profile/wallet.dart`
     - `lib/listener/listener_form/voice_selection_page.dart`
     - `lib/user/widgets/expert_card.dart`

2. **Extract reusable UI primitives**
   - Add:
     - `lib/ui/widgets/primary_cta_button.dart`
     - `lib/ui/widgets/info_card.dart`
     - `lib/ui/widgets/status_chip.dart`
   - Replace repeated button/card/chip code in wallet/profile/home cards.

3. **Copy and terminology cleanup (user-facing only)**
   - Audit and normalize wording:
     - `Expert` for user-facing discovery and profile action
     - keep backend/internal model names unchanged
   - Start with:
     - `lib/user/nav/profile.dart`
     - `lib/user/screens/home_screen.dart`
     - `lib/user/widgets/top_bar.dart`

4. **API-state UX hardening**
   - Add consistent loading/empty/error blocks for user-facing network lists:
     - `lib/user/screens/home_screen.dart`
     - `lib/user/nav/profile/wallet.dart`
   - Standardize retry behavior and message tone.

5. **Accessibility and readability pass**
   - Increase minimum touch targets to 44dp where needed.
   - Ensure key text remains readable at small widths and with large font scaling.

## Validation checklist
- Test on narrow screen widths (<= 340px, 360px, 393px)
- Verify no horizontal overflow in wallet cards
- Verify avatar fallback by gender when no custom avatar is set
- Verify voice verification path requires explicit `Continue`
- Verify profile action label is consistent in all menu states

## Success metrics
- Zero card overflow/overlap in wallet section
- Consistent user-facing terminology across primary screens
- Reduced UI bugs from duplicate style/layout definitions
- Improved conversion flow clarity (wallet + onboarding)
