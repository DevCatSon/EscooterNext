# Motion and scooter setup

Research reviewed on 2026-10-20. The implementation is original Flutter code; the applications below were studied for interaction patterns, not copied or added as dependencies.

Motion/accessibility guidance was checked again on 2026-10-21 for build 10. Popups use a 240 ms fade with a small 0.96-to-1 scale and 0.025-height offset; unit selection animates color/border feedback without delaying the action. These are app choices, not Apple timing specifications. Reduce Motion removes popup movement and sets route/selection durations to zero. Selection is also visible through labels, icons, a border and a check indicator. Dialog content remains scrollable at large text sizes.

The persistent app gradient sits behind the navigator. Flutter's Android fade-forwards transition normally paints a solid surface during navigation; the app supplies a transparent fill so that the backdrop remains unchanged. Closing the Demo connection page retains its current content during the exit rather than briefly rebuilding it as Disconnected. A frame-pixel regression verifies the gradient during this path, and a control run with the old solid fill reproduces the color change.

Build 11 uses the same primary blue for both unit menus. The existing lock card enters with a 300 ms fade and small vertical offset, then fades away with an open padlock only after an unlocked status arrives. It blocks touches from the first locked frame; the outgoing unlocked snapshot is noninteractive and excluded from accessibility. Disconnect removes the overlay immediately. Reduce Motion makes these transitions immediate. These timings are app choices, not Apple specifications.

## Primary guidance

[Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion) recommends purposeful, brief feedback, familiar system transitions, optional motion, and avoiding unnecessary animation for frequent interactions. The app therefore uses Flutter's Cupertino navigation transitions on iOS, short fades between setup stages, and colour transitions when a reported control/mode state changes. Tabs keep their platform navigation behavior. Dashboard numbers use brief interpolation, while stored readings and screen-reader values update immediately; first readings, missing values, unit changes and Reduce Motion bypass interpolation.

[Apple HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) favours brief, optional, task-based onboarding, postponing nonessential configuration and explaining a necessary permission in context. Setup prepares the rider, searches for the actual scooter, then confirms the connection. It does not introduce accounts, mandatory customization, a feature slideshow, legal screens or extra permission prompts. Existing saved devices reconnect automatically in the foreground when enabled; first-launch setup and manual disconnect behavior are documented in docs/ONBOARDING.md at the repository root.

[Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) calls for larger text, comfortable targets and information conveyed by more than colour. Eco/Drive/Sport have green/blue/red accents, their labels, a selected border and persistent mode icons. The fixed dashboard uses a section picker when a very short screen or large text cannot fit all controls at once. It never relies on clipped content or shrinking the user's text scale.

[SwiftUI Animation.smooth](https://developer.apple.com/documentation/swiftui/animation/smooth) describes a non-bouncy spring preset. That informs the restrained approach; this app does **not** claim to reproduce SwiftUI's spring physics. Custom feedback uses a 200 ms colour transition and setup content a 300 ms eased fade. These durations are app choices, not values prescribed by Apple. Navigation uses the Flutter platform component rather than an invented iOS slide curve.

Reduce Motion removes custom stage animations, sets control/appearance transition durations to zero, suppresses page transitions and replaces the repeating search spinner with a static indicator. Search/connection status remains visible as text. Old setup content cannot receive touches or screen-reader focus during a fade.

## Real application references

### Flipper iOS

Reviewed revision `2c1c8531953110631ca471251280a1602d118011`:

- [InstructionView.swift](https://github.com/flipperdevices/Flipper-iOS-App/blob/2c1c8531953110631ca471251280a1602d118011/Flipper/iOS/UI/Welcome/Instruction/InstructionView.swift): preparation precedes the Connect action.
- [ConnectionView.swift](https://github.com/flipperdevices/Flipper-iOS-App/blob/2c1c8531953110631ca471251280a1602d118011/Flipper/iOS/UI/Welcome/Connection/ConnectionView.swift): discovery, selected-device connection, help, cancellation, timeout and Bluetooth issues are separate states.
- [BluetoothAccessView.swift](https://github.com/flipperdevices/Flipper-iOS-App/blob/2c1c8531953110631ca471251280a1602d118011/Flipper/iOS/UI/Welcome/Connection/Issues/BluetoothAccessView.swift): access problems have an explanation and an app-settings action.

Applied here: a preparation step, explicit Find action, real discovery results, persistent actionable errors, connection help, cancellation and a success state driven by the connection controller. Manufacturer graphics and legal/account flows were not reused.

### isowords

Reviewed revision `c727d3a7c49cf0c98f2fa4f24c562f81e30165f7`:

- [OnboardingView.swift](https://github.com/pointfreeco/isowords/blob/c727d3a7c49cf0c98f2fa4f24c562f81e30165f7/Sources/OnboardingFeature/OnboardingView.swift): explicit steps and actions, cancellation and a completion delegate keep onboarding separate from the core feature.

Applied here: explicit Prepare/Connect/Ready states, a voluntary Close action, controller-driven success and a deliberate Open dashboard action. The game's long tutorial, timed instruction advances and sound effects are not appropriate for a scooter connection flow.

## Verification and limits

Widget tests exercise permission timing, discovered-device connection, denied access, closing while authorization is pending, cancelling an in-flight connection, successful completion, fixed dashboard geometry, mode colours, large-text access to all compact sections, landscape layout and Reduce Motion. Existing frame/controller tests still validate the wire behavior. A successful build or simulated connection is not evidence of physical scooter/iPhone operation.
