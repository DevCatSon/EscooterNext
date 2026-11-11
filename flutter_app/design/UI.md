# Mobile interface

The October redesign follows the supplied scooter-companion references: the vehicle is the focal point, live status stays near it, and the most useful controls are visible together. No manufacturer branding, map, account service or unsupported ride-history feature is implied.

## Hierarchy and navigation

- Scooter: fixed vehicle overview with battery and a consistently labelled Live speed tile; trip/total distance and voltage; confirmed quick controls and coloured riding modes; Lock and Find.
- Tuning: speed selection and reported value, followed by acceleration and brake settings.
- Sensors: battery/electrical readings and temperatures first. Battery-pack, motor/brake signal and firmware details expand on demand.
- Settings: individually rounded vehicle/control/app rows. Units and Auto reconnect are directly accessible here. The duplicate Control page is removed; dashboard quick controls and Tuning remain their single destinations. Feature visibility uses green pill switches. About/privacy and diagnostics have dedicated pages.
- Connection, lock, lighting, compartments and feature selection use the same components and type scale. Text describes the current state or an action rather than a slogan.

## Visual system

Popups share a tinted surface, an accent icon, a soft border/shadow and clear action buttons. Both unit menus use the selected theme’s primary palette. Unit options retain their icons and show selection with a border and check indicator as well as color. Dialog content scrolls at large text sizes; labels are not shrunk. The shared implementation is [dialogs.dart](../lib/ui/dialogs.dart).

The lock panel retains its centered card and theme-colored padlock. A reported lock fades in the backdrop and gently lifts the card into place. A confirmed unlock crossfades the padlock open and fades the panel away. Pending commands keep the reported state; the overlay blocks controls immediately while locked. The outgoing unlocked panel has no actions or accessibility focus. Disconnect removes it immediately, and Reduce Motion removes these animations.

Use 4/8/12/16/24-point spacing and 16-point page margins. Cards/menu rows have 22-point corners; control rows use 20-point horizontal padding, an 84-point minimum height and 12-point gaps. The selected theme tints the app backdrop gradient, cards, controls and navigation in both appearances. Ocean, Mint, Sunset, Violet, Graphite and a custom RGB color are available. Green switches retain white thumbs, while primary actions use the selected palette. Main titles are 20 points, control labels 18, section headings 16, body text 14–16, and supporting labels 12–13. Large numbers identify live data. Numeric values use tabular figures.

Maintain labelled navigation and actions. Selected controls show both colour and explicit On/Off text. Pending controls wait for the scooter and expose their pending state to accessibility services. Missing readings remain unavailable. A disconnected scooter never displays invented readings.

The dashboard stays within its viewport and never scrolls. On short screens or at large text sizes, a section picker exposes Overview, Ride totals, Controls, Ride modes and Lock/Find without clipping or reducing text scale. Longer settings, sensor and setup content can scroll. Tablet home content uses two columns; secondary pages have a readable maximum width. Light/dark themes use the same hierarchy. Touch-target tests check the home screen against Android 48-point and iOS 44-point guidelines; widget tests check all four destinations at double-sized text on a 320-point phone. [Motion and setup research](MOTION_SETUP.md) records the Apple and real-app references.

## Scooter artwork

`assets/scooter.png` is an original generic vehicle illustration produced with the built-in image generation tool, using the imagegen skill. It is not a model identification or an exact representation of the connected scooter. The image is decorative and excluded from screen-reader navigation. It is stored in the project with its generated transparency preserved; no manufacturer photographs or logos were copied.

Final generation prompt:

> Use case: product-mockup. Asset type: transparent product illustration for an electric scooter companion mobile app, not a UI mockup. Primary request: a beautifully detailed photorealistic studio product render of one generic modern commuter electric kick scooter, graphite black, subtle brushed metal chassis, thick dark rubber tires, slim upright stem and handlebars, practical flat deck and rear mudguard. Three-quarter side view, front wheel to left of image, entire scooter including both wheels and handlebars visible. Composition: scooter centered, isolated on genuinely transparent background, comfortably framed with about 6% padding, landscape 4:3 composition. Soft neutral studio lighting, clean highlights that show black surfaces well on both light and dark backgrounds. No hard cast shadow, no floor, no environment. Constraints: no brand logos, no text, no watermark, no rider, no UI, no blue glow; realistic functional scooter geometry.


The Gyrocopters G30 profile uses separate [owner-reference artwork](G30_ARTWORK.md), with the same front-left camera angle and transparent product-render treatment. The generic image remains the fallback for other models.
