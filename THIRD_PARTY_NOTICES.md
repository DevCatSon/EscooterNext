# Third-party notices and provenance

The root [MIT license](LICENSE) and Flutter [MIT notice](flutter_app/LICENSE) retain the original **2026 Dev Cat** copyright. Project maintenance/changes are attributed to **DevCatSon**. These notices do not relicense dependencies or separately licensed tool code.

## Application dependencies

Flutter and Dart, Flutter packages and their platform plugins, AndroidX libraries used by those plugins, Kotlin, Gradle and the Android toolchain retain their upstream licenses. Dependency versions are recorded in `flutter_app/pubspec.lock` and `flutter_app/android/` build files. Flutter's **About → Open-source licenses** page uses Flutter's license registry; it is not an inventory of every external build tool or Apple/Android SDK.

Before distributing a binary, review the resolved dependency/native-framework notices for that build and retain any required attribution. Do not assume the project MIT license covers the Flutter engine, plugin native libraries or SDKs.

## xcross tool patches

The files `flutter_app/tool/xcross-2.0.6-*.patch` modify [xcross v2.0.6](https://github.com/arxdeus/xcross/tree/v2.0.6), pinned to commit `c28c6bc4a5a3e64888a1303ede777be49f34390b`.

Upstream identifies its license as **GNU AGPL-3.0**, copyright **2026 Artemis Kushner**. The included upstream context and these tool modifications are provided under that license, with modification authorship **2026 DevCatSon**. The [complete upstream license](flutter_app/tool/licenses/xcross-AGPL-3.0.txt) is included. The patches change Swift build-plan handling, raster icon packaging/version forwarding, serial Windows Swift compilation and certificate preservation; they do not change the upstream license.

`prepare_xcross.ps1` fetches upstream source into ignored build storage and applies the published patches so the modified tool can be rebuilt. No xcross executable, Apple SDK, authentication cache, signing key or provisioning profile is committed. The application source and the development tool are separate components; review generated/embedded native code and all relevant license terms before distributing Windows-built iOS artifacts. This notice does not certify the licensing of a particular output bundle.

## Artwork and design references

The generic scooter illustration is generated project artwork, not a verified model photo. The G30 illustration was generated from owner-supplied reference photos; see [G30 artwork provenance and prompts](flutter_app/design/G30_ARTWORK.md). It depicts visible Gyrocopters/G30 branding as part of that model, without implying manufacturer affiliation. The source photographs and RAW/EXIF data are not redistributed. Icon artwork is drawn by the project's [icon generator](flutter_app/tool/generate_icons.py). Record new model-image provenance and permission before adding assets. The supplied UI screenshots are visual references and are not redistributed in this repository as app assets.

[UI provenance](flutter_app/design/UI.md) and [motion/setup research](flutter_app/design/MOTION_SETUP.md) identify the primary guidance and open-source applications studied. Their source was used as research, not vendored as app dependencies. Preserve original notices if future contributions actually copy upstream code or assets.
