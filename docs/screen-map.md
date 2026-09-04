# Screen map — web → SwiftUI

| Web (SeanVasey/vizion) | iOS | Notes |
| --- | --- | --- |
| `middleware.ts` + `(app)/layout.tsx` gate | `AppEnvironment.gate` → `RootView` | config · session · onboarding · closed-access |
| `(auth)/sign-in` + `AuthHero` + `SignInForm` | `AuthGateView` · `AuthHero` · `SignInForm` | Google/GitHub via `ASWebAuthenticationSession`; magic link; password; **plus** Sign in with Apple, native-only (ADR-0006) |
| `(auth)/set-password` + `SetPasswordForm` | `SetPasswordView` | `PasswordRule` shared |
| `ScreenHeader` / `BottomNav` / `NewPromptFab` | `ScreenHeader` · `MainTabView` (TabView) · `NewPromptButton` | Tab icons are the web's strokes as template images |
| `(app)/enhance` + `EnhanceComposer` | `EnhanceScreen` · `EnhanceComposer` · `EnhanceViewModel` | |
| `ModeRig` | `ModeRigView` | six cells, sliding Laser lens, blurb strip |
| `TargetPicker` (+ budget dial) | `TargetPickerSheet` | grouped by developer; Auto row; budget segmented |
| `ThinkingDial` + `HoldSlider` | `ThinkingDialSheet` + `DepthMeter` | segmented ladder now; hold-capsule later (ledger) |
| Shape / Depth rails (`SegmentedRail`) | `VZSegmented` rows in `EnhanceComposer.rails` | re-pick clears |
| `TemplateSheet` | `TemplateSheet` | `PromptTemplate.all` |
| `AttachmentTray` · `MediaPrivacySheet` · roles · generate | `AttachmentTrayView` · `MediaPrivacySheet` · `EnhanceViewModel.Attachment` | images only in this pass; video/audio in the ledger |
| `StreamProgress` / `StreamingResult` / `PartialOutput` | `StreamProgressView` | monotonic ticker from `EnhanceStreamState` |
| `TransformationDiff` (+ `segments`, `CompareSheet`) | `ResultView` · `DiffText` | Copy/Use/Save/Share/Export; Polish review; Clarify questions; refine chips; original collapsible |
| `savePromptWithOutbox` | `SavePromptSheet` → `LibraryRepository.savePrompt` | duplicate → "Save as new version"; no offline outbox yet |
| `(app)/library` + `LibraryBrowser` | `LibraryScreen` · `LibraryBrowser` · `LibraryViewModel` | server-side filter + keyset paging |
| `LibraryFilterSheet` | `LibraryFilterSheet` | facets from `LibraryFacets.reduce` |
| `CollectionSheet` | `CollectionSheet` | |
| `DraftsToolbar` / `DraftsList` | drafts view inside `LibraryBrowser` · `DraftEditorSheet` | optimistic-concurrency edit |
| `ActivityFeed` | `ActivityFeedView` | |
| `(app)/library/[id]` + `PromptDetail` | `PromptDetailScreen` · `PromptDetailViewModel` | history, restore, compare, revise |
| `(app)/profile` + `SettingsPanel` sections | `SettingsScreen` + `Identity/Account/Defaults/Appearance/DataPrivacy/Owner/About` sections | |
| `AvatarCropper` | `ImageProcessing.avatarPNG` (center square) | interactive crop in the ledger |
| `MediaManager` | `DataPrivacySection` stored-media list | |
| `/auth/delete-account` | `DELETE /api/account` (companion) | typed DELETE confirmation |
| `ThemeManager` / `ThemeToggle` | `preferredColorScheme` from `UIStore.theme`; theme segmented in Settings | |
| `AmbientNebula` | `AmbientBackground` | reduced by Reduced Effects + Reduce Motion |
| `Footer` | `VizionFooter` | monograms from the same potrace paths |
| `draft-param.ts` / Shortcuts runbook | `DeepLink` + `DraftParam` + `onOpenURL` | `vizion://enhance?draft=` |
| Service worker / offline.html | — | native app; no shell caching needed |
