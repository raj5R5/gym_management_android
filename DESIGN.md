---
version: alpha
name: Iron Signal
description: An athletic gym operations interface with graphite smoked glass, volt accents, condensed headings, readable financial data and a native dimensional weight plate.
colors:
  primary: "#D8F343"
  volt: "#D8F343"
  olive: "#48620B"
  graphite: "#101213"
  dark-surface: "#1C2022"
  dark-raised: "#242A2C"
  paper: "#F1F2EC"
  white: "#FFFFFF"
  ink: "#182020"
  dark-text: "#F4F6F5"
  mint: "#DCF0E1"
  dark-mint-text: "#A7E8C1"
  coral: "#F8E1DB"
  dark-coral-text: "#FFB3A9"
typography:
  display:
    fontFamily: BarlowCondensed
    fontSize: 42px
    fontWeight: 700
  body:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.45
rounded:
  control: 8px
  card: 12px
  dialog: 16px
  sheet: 20px
spacing:
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  xxl: 32px
modes:
  light:
    background: "{colors.paper}"
    surface: "{colors.white}"
    text-primary: "{colors.ink}"
    accent: "{colors.olive}"
  dark:
    background: "{colors.graphite}"
    surface: "{colors.dark-surface}"
    text-primary: "{colors.dark-text}"
    accent: "{colors.volt}"
---

# MuscleDesk — Iron Signal

Code-derived, updated 2026-10-23 following approval of the Iron Signal preview. This replaces Titanium Ice: graphite smoked glass, volt accents, angular shapes, condensed athletic headings and a dimensional gym plate. Keep operational data readable and retain every existing route, authentication, membership, payment and photo safeguard. This document does not authorize changing business behavior.

## Sources and reuse

- [Design tokens](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/app/theme/design_tokens.dart): `AppPalette`, `AppSurfaces`, `AppTone`, spacing and radii.
- [App theme](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/app/theme/app_theme.dart): Material 3 colors, typography and component defaults. Unspecified roles inherit `ColorScheme.fromSeed` / Flutter defaults.
- [App](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/app/app.dart): light/dark themes follow the system (default `ThemeMode.system`); transparent Scaffolds sit over `TitaniumCanvas`.
- [Shared surfaces/motion](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/shared/widgets/titanium_surface.dart), [SoftPanel](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/shared/widgets/soft_panel.dart), [ProfileSection](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/shared/widgets/profile_section.dart): reuse these before introducing another panel or effect.
- [Admin shell](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/app/navigation/admin_shell.dart), [member cards](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/features/members/presentation/member_list_widgets.dart), [member profile](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/lib/features/members/presentation/member_details_cards.dart): layout references.

Prefer `Theme.of(context).colorScheme`, `textTheme` and `AppSurfaces.of(context)` in UI. If this document and code diverge, inspect the code before changing either.

## Colors

Hex values are base colors; glass and highlights composite over them.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas gradient, top-left → bottom-right | `#F1F2EC` → `#EEF1E8` | `#101213` → `#141819` |
| Surface | `#FFFFFF` | `#1C2022` |
| Raised surface | `#E8ECE4` | `#242A2C` |
| Primary / secondary | `#48620B` (`deepIce`) | `#D8F343` (`ice`) |
| On primary | `#FFFFFF` | `#182003` |
| Primary container | `#E8EED6` | `#30381B` |
| Main text (`onSurface`) | `#182020` | `#F4F6F5` |
| Secondary text (`onSurfaceVariant`) | `#52605A` | `#B5BDBD` |
| Decorative border / outlineVariant | `#C6CEC4` | `#454E51` |
| Input outline | `#78847B` | `#748182` |
| Positive surface / accent text | `#DCF0E1` / `#175938` | `#20372C` / `#A7E8C1` |
| Dues surface / accent text | `#F8E1DB` / `#A02D26` | `#422B29` / `#FFB3A9` |
| Expired surface / accent text | `#E0E5DF` / `#52605A` | `#343A3D` / `#CFD6D4` |
| Error container / error text | `#F8E1DB` / `#A02D26` | `#422B29` / `#FFB3A9` |

`AppTone.member` and `.plan` use `#E8ECE4` / `#242A2C`; `.payment` uses the primary-container colors. `.pending` **accent** is strong coral, while its **panel** is the soft dues surface. Use the appropriate foreground helper. Profile status (active/inactive/suspended) and membership lifecycle/payment status are separate concepts.

Legacy aliases `ice`, `deepIce`, `iceTint`, `ember`, `darkEmber`, `peach`, `forest`, `cream` and `lavender` now resolve to Iron Signal colors; their names do not imply orange, green or purple styling.

## Typography

Fonts are bundled: **Inter** for body, identity, controls and financial figures; **BarlowCondensed** for display/headline roles. Barlow Condensed 600/700 and its OFL license come from the [Google Fonts source](https://github.com/google/fonts/tree/main/ofl/barlowcondensed). Existing SpaceGrotesk assets remain for compatibility, but no longer define the theme.

| Role | Size | Weight / tracking |
| --- | --- | --- |
| displaySmall | 42 | 700 / +0.3 |
| headlineLarge | 38 | 700 / +0.3 |
| headlineMedium | 34 | 700 / +0.2 |
| headlineSmall | 30 | 700 / +0.2 |
| titleLarge (Inter) | 22 | 600 / −0.3 |
| titleMedium (Inter) | 16 | 600 / inherited |
| bodyLarge / bodyMedium / bodySmall (Inter) | 16 / 14 / 12 | 400; line heights 1.50 / 1.45 / 1.40 |
| labelLarge / labelMedium / labelSmall (Inter) | 14 / 12 / 11 | Material 3 inherited weight, usually 500 |

Exceptions: compact hero heading 34; revenue value Inter 36; metric counts Inter 28; wide dues value Inter 26; member-card dues Inter 18/700; identity name Inter 24/700; membership dates 12. Financial summaries use tabular figures. Keep currency in Inter when overriding a condensed headline role. The shell brand uses Inter labels with 1.5 tracking.

## Spacing, shape and depth

- Logical pixels: `AppSpacing.xs/sm/md/lg/xl/xxl` = **4/8/12/16/24/32**. `contentWidth` = **840**; screens use this selectively, not universally.
- `AppRadii.control/card/panel/pill` = **8/12/12/100**. Dialog/drawer 16, sheets 20, FAB/popup 12.
- Shared shadow: `#182020` at 8% light / 24% dark, blur 24, offset `(0,8)`. Elevations: Card 1, filled button 2, FAB 4, dialog 12, bottom sheet 16.
- `TitaniumCanvas` adds static primary illumination at 8% opacity. Its Dashboard-only animated variant adds slow 16-second light reflections behind the panels, isolated in a repaint boundary; operational content never moves with the light. `TitaniumGlass`: radius 12, clipped blur sigma 16, surface opacity 94% light / 92% dark; financial sheets override to 96%. Keep opaque-enough fills behind all amounts and form fields. Opt-in `AppGlass` variants use navigation opacity **66% light / 48% dark**, blur sigma **24**, and Dashboard metric opacity **84% light / 68% dark**; pending-dues glass stays at 84%. Glass color is painted once, avoiding an unintended second opaque tint.
- `SoftPanel`: radius 12, 1px border, default padding 16, optional blur sigma 14. Its white highlight is alpha-blended **into the base surface color**; do not replace this with a transparent gradient that loses the fill.

## Components and screen patterns

- **Sections:** `ProfileSection` uses a `SoftPanel`, padding 16, bottom gap 12, an accessible Inter 16/600 heading and optional subtitle. Its default compact header pairs the title with a neutral 20dp icon; `compactHeader: false` retains the previous tinted icon block where explicitly needed. Reuse this compact treatment across operational screens. `BrandMark` reuses a static native weight plate (default 52, some screens 44). Icons are Flutter Material icons, mainly outlined with existing rounded/filled exceptions.
- **Metadata:** reuse `IconLabel` for bounded, wrapping icon + text rows in billing, receipts, registration recovery and account information. Preserve the complete saved value and status text; never rely on the icon or color alone. Created/updated record metadata belong in the secondary Record details disclosure. Bring confirmed renewal/cancellation results into view after their review closes. An unexpired server-active membership that is not currently active is labeled Upcoming; this is presentation only, with the existing eligibility gate unchanged.
- **Cards:** Material Cards use a 12 radius, 1px border, 94% surface fill and zero default margin. Trainers use avatar + `ListTile`; plans reuse `SoftPanel` through `PlanSummaryCard`: prominent approximate month equivalent and exact total days, visible plan price/status, and existing Edit action. The month view uses 30 days per month and is explicitly approximate; saved days remain authoritative. A tappable calendar icon explains the units without changing the plan. Duration columns and the price/Edit footer stack for narrow or enlarged-text layouts.
- **Member/Dues cards:** full-width 168-high cover photo, initials on missing/failed images, 12-padded footer and natural text height. This is not a fixed aspect ratio or enforced 70/30 split. Directory cards show an accessible 12px active-membership dot at top-right; fully paid gets mint styling and a `Fully Paid` footer pill; debt gets coral amount text; expired gets neutral styling plus an explicit label. Expired members can still show a coral due amount. Dues cards retain the same photo/footer language and navigate to details.
- **Member details:** owner-first order: compact identity → current membership → payment summary → expandable contact/personal information and gym/trainers → membership history. Keep the 128×128 photo, radius 12, name/code, explicitly labeled profile status and Edit member; tappable saved photos reuse `MemberPhotoAvatar`, its existing viewer, scoped authenticated image/revision/fallback path. The current membership reuses `PlanDurationSummary` and `PlanDurationInfoButton`: approximate 30-day months and exact saved subscription days are prominent above the existing UTC dates and saved price. Use the membership snapshot, never the current catalog plan or remaining time. History summaries retain their compact layout. Current-plan paid/due values are compact, unboxed and explicitly scoped to that plan; the payment summary separately emphasizes verified dues across all non-cancelled memberships, including expired ones, with lifetime paid/latest payment below. `MemberPayNow` is the existing guarded collection action rendered **inline in the payment summary**, never over the content or in a reserved footer. Recovery remains beside the balance. Use the shared compact `ProfileSection` treatment for these operational sections. Explain upcoming, expired, cancelled and first-membership states without deriving eligibility from device time. Profile status, plan lifecycle and payment status remain distinct. Unknown/last-verified balances retain their explicit labels and retry paths.
- **Dashboard:** `IronHero` introduces “RUN THE FLOOR.” and the plate. Date presets/custom range remain visible, while the repeated date/timezone block is removed. The revenue card retains its period. Revenue comes first, followed immediately by full-width Pending Amount, paired Total Members/Active Plans metrics, current membership counts (active, expiring soon, expired), and quick actions. Exact inclusive bounds/timezone and metric definitions remain available in a collapsed “About these figures” section; they are not repeated above the revenue card. Paired metrics stack for narrow/large-text layouts. The overview scrolls; avoid squeezing every summary into the first viewport. Rings are decorative reveals, not achievement percentages. Retain the existing profile-status distribution component; do not invent targets, trends or historical charts without data.
- **Owner profile / drawer:** reuse `SoftPanel`, existing tokens, an authenticated 64dp square drawer photo and 96dp account photo with initials fallback. Show saved owner name and gym name, a real six-field completion count/progress and Manage profile. More retains logout; Edit owner profile is a guarded child route without bottom tabs. Forms group owner and gym details; photo selection/upload/recovery reuses the existing photo editor. Photo is optional at sign-up and does not gate account creation or app use. Never display a fabricated completion percentage or expose another account/gym/environment’s cached profile.
- **Privacy/account deletion:** public Privacy & support uses the existing `ProfileSection`, selectable URLs and labeled Open website/Copy actions; it remains reachable during session-restoration errors. Android opens public HTTPS links in the system browser, with copy fallback. Login, Sign Up and account/More expose it; account/More also offers an authenticated, password-verified deletion request. Reuse `FeedbackNotice` for unavailable/uncertain results, show a server receipt before confirming intake, and distinguish Request received from actual completed deletion. Preserve the original Logout position and busy guard. Do not invent public contacts, policy text, retention periods or a completed-deletion state.
- **3D identity:** reuse `WeightPlate` / `IronHero`; the plate is an extruded mesh projected by Flutter Canvas, with rubber/steel material tokens, a volt rim and decorative 20 KG lettering. No network asset, WebView or 3D dependency. Dashboard, Login and Owner Sign Up share the hero. Keep artwork out of dense financial/list content. The enlarged plate autoplays a seamless 10-second float/tilt loop with no Play/Pause controls, per the latest approved refinement. Compact heroes reserve 144dp for it; standard/stacked heroes reserve 176dp. Rubber grain, tangential grip holes, a bevelled rim and a metallic hub add depth. Hidden/background/reduced-motion states pause the decorative loop. The artwork is excluded from screen-reader semantics.
- **Chips:** common selected chips use primaryContainer/onSurface; Dashboard date chips explicitly use primary/onPrimary. Keep label and checkmark contrast when adding variants.
- **Buttons:** FilledButton = primary/onPrimary, minimum 48×50, padding horizontal 24/vertical 12, radius 8. OutlinedButton/TextButton minimum 48×48. `AppButtonStyles.payment` uses primary; `.warning` uses errorContainer/onErrorContainer. Busy actions retain their disabled state and progress/opening labels.
- **Forms:** reuse `FieldIcon` for a consistent 20dp semantic vocabulary (identity, contact, plan, money, status, reference). Decorative prefixes are excluded from screen-reader semantics; visible labels remain authoritative. Keep prefixed selectors `isExpanded: true` and allow natural item height so longer/large-text selections stay inside the field. Always-floating labels; filled input surface at 96%, padding 16, radius 8, outline border and primary focus border width 1.5. Helper/error text allows four lines. Existing forms use grouped sections, inline validators, keyboard types, password visibility/autofill where implemented, and busy/unsaved-exit guards.
- **Overlays:** dialogs use 97% surface/radius 16; sheets use top radius 20 and a 65% dark-canvas scrim. Payment/renewal/cancellation sheets use 96% `TitaniumGlass`, hide the default handle, scroll above keyboard insets and retain their busy-dismissal safeguards.

## Navigation and responsiveness

- `AdminShell`: app bar, gym scope, drawer and four labeled tabs: **Dashboard, Members, Trainers, Plans**. More is drawer-only; More and Edit owner profile routes omit the bottom bar. Preserve existing routes, back behavior and form guards.
- NavigationBar height 64, icons 22, 8-radius rectangular primary selection indicator; transparent frosted wrapper inset `(12,4,12,8)` inside `SafeArea`. `AppGlass.navigation` also styles the top bar; content stays clear of the bottom bar, retaining existing viewport and payment-control insets. Labels stay single-line with measured width and a 1.3 text-scaling cap for that measurement.
- `ResponsiveMemberGrid`: two columns when **available content width ≥328** and effective 14px text scale **≤1.25**; otherwise one. Gaps 12; paired cards stretch to the row's natural height. This breakpoint is not the phone's physical pixel width.
- Profile identity stacks when inner width <288 or text scale >1.4. Amount tiles stack below 300 or scale >1.3. Dashboard paired metrics use two columns when content width ≥312 and scaled 16px text ≤24; otherwise one. Login caps width at 420; signup and shared message pages at 480.
- Use existing `LayoutBuilder`, `Wrap`, flexible text, scroll views and safe/keyboard insets. There is no implemented app-wide tablet two-pane/foldable navigation system.

## States, accessibility and motion

- **Loading:** circular indicators for initial fetches/restoration; linear progress and explicit “updating/checking” copy for refresh/recovery. Skeletons/shimmer are not the current shared pattern.
- **Empty:** contextual copy, search-off/people icons and create/clear-filter actions where implemented; other lists use plain empty text.
- **Error:** `FeedbackNotice` uses errorContainer + icon + live-region message + optional Retry. Feature error wrappers provide safe messages. `FinancialRefreshStatus` labels last verified data during refresh/failure; unavailable amounts are not fabricated as zero.
- **Success/recovery:** server-confirmed results use positive sections/receipts; unresolved payment, renewal, registration and photo operations retain their existing review/retry paths. Photo permission-denial copy points to Settings/another source. There is no universal offline banner or permission-denied screen; typed failures are handled in their flows.
- Existing accessibility patterns: semantic headings, named icon-button tooltips, photo/status/date labels, live error regions and excluded decorative icons. Status is supplemented with labels, amounts or semantic announcements. Shared buttons have 48px-or-larger minimums; this is not a claim that every interactive target has been audited.
- Motion: entrance **380ms easeOutCubic**, fade + 12px translation; press scale **0.985 / 120ms easeOut**; filled-button state animation **160ms**; metric reveal **800ms**. Android routes fade/slide; iOS/macOS retain Cupertino transitions. Custom entrance/press/metric animations respect `disableAnimations` / `accessibleNavigation`; money remains exact integer-paise presentation.
- Flow-test hosts set `GymApp.animateDecorations` to false via `AmbientMotionSettings`, disabling only decorative loops while leaving route/form/financial animation timing intact. Production defaults to autoplay. Dedicated autoplay/lifecycle/reduced-motion tests use bounded pumps; do not change operational behavior to accommodate `pumpAndSettle`.
- Existing contrast/rendered-glass/reduced-motion coverage is in [surface tests](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/test/shared/widgets/titanium_surface_test.dart); responsive/payment coverage is in [member detail tests](/Users/semgroup/Desktop/FlutterProjects/gym_management_app/test/features/members/member_details_design_test.dart). This documentation inspection does not certify WCAG conformance or replace device/TalkBack checks.

## Remaining recommendations — separate work

1. Consolidate remaining literal colors/spacing/radii and legacy alias names when separately authorized; do not reinterpret the aliases' old color names.
2. Navigation labels still shrink to fit at very large text. Both directory and Dues dates now wrap at date boundaries at 12px; retain readable dates instead of reintroducing shrinking text.
3. Review responsive widths individually: the 840 cap is selective, and breakpoints differ by component. Several lists/grids eagerly build children (`Column`/`IntrinsicHeight`); evaluate virtualization if data volume grows.
4. Localization/RTL is incomplete: English copy/month abbreviations, physical left/right alignment/padding and no app localization delegates/locales configuration. Do not describe this as fully localized or RTL-ready.
5. Distinguish the current generic failure patterns from a dedicated offline/permission system. Assess missing states per feature rather than adding fake states or changing recovery behavior.
6. Recheck actual composited contrast, targets, keyboard clearance and screen-reader behavior in both themes during future UI work. Static mobile-skill findings require manual review: token definitions and inherited Flutter sizing can be flagged without proving a rendered defect.
