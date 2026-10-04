# SekhVet

A veterinary DICOM viewer for macOS. SekhVet is a fork of [Horos](https://horosproject.org)
4.0, which is based on OsiriX, with a layer of tools for veterinary radiology.

Developed and maintained by Kappa1-VRS GmbH, Zurich, Switzerland.

**Status: version 1.0** (first regular release, October 2026). See [Status](#status) below before you rely on a function.

---

> ### SekhVet is not a certified medical device
>
> It is not cleared by the FDA, not CE-marked and has not undergone any formal validation.
> It is intended for use in veterinary medicine, research and education only and **must not be
> used for the diagnosis or treatment of humans**.
>
> Measurements and orientation aids are tools; the interpretation of images and the diagnosis
> remain the responsibility of the veterinarian. SekhVet is provided "as is", without warranty
> of any kind. See [`docs/DISCLAIMER.md`](docs/DISCLAIMER.md).

Veterinary devices fall outside EU Regulation 2017/745 and the Swiss MepV, which apply to devices
for human use. There is no certification scheme for veterinary imaging software in either
jurisdiction, so the absence of a certificate is the normal state of affairs rather than a
shortcoming.

---

## Status

SekhVet 1.0 is the first regular release after a public beta (builds 45–149, August to October
2026). The Horos core and the veterinary tools are in daily use in one practice. Functions that
are new in 1.0 and have been tested on few devices so far are marked **new** here and in the
manuals.

| Function | Status |
|---|---|
| Orientation letters, hanging protocol in 2D and MPR (also curved and orthogonal), opening protocols, window presets | in daily use |
| Spine labeling, Norberg angle, distraction index | in daily use |
| Point tool, double MPR, convolution filters, magnifier, free rotation | in daily use |
| DICOMweb query / retrieve (with queue) / send | in daily use |
| Image and PDF import, rename patient, import from other databases, display settings | in daily use |
| Overlay of native / contrast / bone series, in 2D and MPR | **new**, in use on CT and MR of one device since late September 2026 |
| Subtraction by location (Horos fusion, repaired) | **new**, checked on CT and MR |
| Measurement navigator; DICOMweb institution filter and automatic refresh | **new**, tested on one device since October 2026 |
| Ultrasound calibration from a neighbouring image | **new**, one device tested (Mindray Vetus 9), enabled for Mindray only by default |
| Update check against GitHub | **new**, can only be judged in use with the next release |
| macOS 27 | tested in a test installation (double MPR with a large CT, double-click zoom); daily use is on macOS 26 |

No function is known to corrupt data, and measurements are reproducible on the devices tested.
Keep Horos or OsiriX installed alongside if you depend on them; SekhVet does not touch their data.

## Why this fork exists

Horos is a good viewer, but it thinks in human terms: A/P and S/I orientation letters, hanging
protocols for an upright patient, no spine counting with 13 thoracic vertebrae, no Norberg
angle. Upstream Horos has seen almost no maintenance since 2025, and Horos 4.0.1 freezes or
crashes on macOS 27 in several viewer situations. SekhVet includes most of the macOS 27 fixes
proposed for Horos in [horosproject/horos#870](https://github.com/horosproject/horos/pull/870)
(viewer windows, VTK initialisation, process scan) plus its own fixes for toolbar icons and the
MPR double-click zoom.

SekhVet keeps the Horos core untouched — database, 2D viewer, 3D MPR, volume rendering, CPR,
fusion, subtraction, key images, export, DICOM networking, plugins — and adds what is missing
in daily veterinary work. It is a maintenance fork, not an upstream contribution: no ARC, no
Metal, no Swift rewrite.

## What SekhVet adds

Everything below lives in the **Vet Tools** menu unless stated otherwise.

| | |
|---|---|
| **Orientation letters** | Cr/Cd and D/V instead of A/P and S/I, in 2D, MPR and on the 3D orientation cube |
| **Hanging protocol** | Any number of protocols (add, rename, reorder); orientation rules per protocol; keyword rules per study description; rotation and flip rules per radiography device; works in the 3D MPR too |
| **Opening protocols** | Which series open on double-click, in which layout and with which window; templates for MR head, spine and stifle; two-view radiographs hang VD left, lateral right |
| **Window presets** | Modality and description rules for window level and width on opening; editable global WL/WW presets ("CT - Bone", "CT - Abdomen" …) |
| **Spine labeling** | Click counter for dog/cat, rabbit and horse with an editable vertebral formula per study; direction from the first two clicks; disc labels by clicking between two vertebrae; rename with recount; the vertebral level (e.g. L3, L3-L4) is shown in every transverse series of the study and in the MPR |
| **Norberg angle** | Hip dysplasia measurement on the VD pelvis: draggable femoral head circles, radius grip and mouse wheel, live angle, value stored with the study |
| **Distraction index** | PennHIP-style laxity measurement on the distraction view, sharing the femoral head circles with the Norberg angle; optional risk level |
| **Point tool** | One click shows the same location in all other open series of the study |
| **Double MPR** | Two MPR windows of one study stay in sync: crosshair, planes, thickness, rotation, zoom per view |
| **Swap / rotate windows** | ⌘H or the Swap button: two MPR windows change sides together with their 2D series; without MPR the 2D series swap; with three or more windows each moves one place on |
| **MPR extras** | Convolution filters on all three planes, larger crosshair hit zones, quiet cursor, no high-dynamic-range dialog |
| **Overlay** | Native, contrast and bone kernel of one examination stacked in one window, in 2D and in the MPR; slice, zoom and pan stay; shared measurements with a native / contrast Δ line |
| **Magnifier** | Corner magnifier while measuring a length, free magnifier with Shift |
| **Ultrasound** | Length measurements on frames without calibration data borrow the calibration of a neighbouring frame with the same depth scale |
| **Rename patient** | Writes name, ID, birth date and sex into the DICOM files of one or more studies, or takes the identity from an existing patient |
| **Display** | Screen area per monitor, readable annotation text in full colour, corner information with kVp / mA / mAs for CT and CBCT, dark mode, modality colours in the database |
| **DICOMweb** | QIDO-RS search with sortable results, WADO-RS retrieve as a stream with a queue, STOW-RS send; Basic Auth in the keychain |
| **Import** | Photos and PDFs into a study as DICOM, optionally attached to an existing study |
| **Feedback** | Send Feedback… opens a prepared e-mail with build and macOS version |

Removed from Horos: the Horos Cloud plugin, the hourly update check against the Horos server and
the plugin update check.

## Documentation

- [`docs/Manual-EN.md`](docs/Manual-EN.md) — user guide, English
- [`docs/Anleitung-DE.md`](docs/Anleitung-DE.md) — Bedienungsanleitung, Deutsch
- [`docs/DISCLAIMER.md`](docs/DISCLAIMER.md) — regulatory status, wording in English and German

## Requirements

- Apple Silicon Mac (M1 or later). There is no Intel build.
- macOS 12 Monterey or later. Tested on macOS 26 Tahoe (daily use) and macOS 27 (test installation).
- For DICOMweb: a server offering QIDO-RS and WADO-RS, for example Orthanc with the DICOMweb
  plugin.

## Install

Download the **DMG** from the [releases page](https://github.com/3v3nFloW/sekhvet/releases),
open it and drag SekhVet onto the Applications folder in the window. The zip on the same page
contains the same app. The beta builds (up to build 149) were pre-releases; 1.0 is a regular release. The SHA-256 of
each file is in the release notes.

SekhVet is ad-hoc signed and **not notarised**, so macOS blocks the first launch. Afterwards go
to **System Settings › Privacy & Security › "Open Anyway"**. Since macOS 15 the right-click ›
Open workaround no longer exists. The alternative:

```sh
xattr -d com.apple.quarantine /Applications/SekhVet.app
```

On first launch SekhVet shows a one-time notice that it is not a certified medical device.

SekhVet keeps its own database (`~/Documents/SekhVet Data`), preferences
(`vet.kappa1.sekhvet.horos`), plugin folder (`~/Library/Application Support/SekhVet/Plugins`)
and suggested DICOM port (11113 instead of 11112, once the listener is enabled), so it can sit
next to an existing Horos or OsiriX installation without touching it.

SekhVet can check GitHub once a day for a new release (asked at first start, switchable in
Preferences › General). It only tells you; you download the DMG and install it yourself. Quit the
running copy before replacing it; database and settings are kept.

**Network defaults:** the DICOM listener is off until you enable it in Preferences › Listener;
SekhVet does not announce itself via Bonjour by default; there is no plugin update check.

## Reporting problems

- **Vet Tools › Send Feedback…** in the application prepares an e-mail with build number, macOS
  version and Mac model.
- Or open an [issue](https://github.com/3v3nFloW/sekhvet/issues) using the bug report template.

Please crop or anonymise images before attaching them. Do not post screenshots or DICOM files
that show owner names, animal names or patient IDs. If a problem needs a DICOM file to
reproduce, say so in the issue and we will arrange a private way to send it.

## Build from source

Prerequisites: Xcode 26 or later, plus `cmake`, `pkg-config` and `git-lfs` from Homebrew. The
project pulls nine submodules including VTK, ITK and DCMTK; a full build takes about 15
minutes, an incremental one about 4.

```sh
git clone --recursive https://github.com/3v3nFloW/sekhvet.git horos-vet
cd horos-vet
export PATH=/opt/homebrew/bin:$PATH
export CMAKE_POLICY_VERSION_MINIMUM=3.5
xcodebuild -project Horos.xcodeproj -scheme Horos -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
```

If `xcode-select` points at the Command Line Tools rather than Xcode, set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` as well.

The product lands in `build/Build/Products/Release/Horos.app`. The bundle executable is still
named `Horos` on purpose, so existing test recipes, `pgrep` patterns and plugins keep working;
the application itself is named SekhVet.

`CMAKE_POLICY_VERSION_MINIMUM=3.5` is required because the vendored third-party projects
predate CMake 4. Further adaptations for Xcode 26 and clang 21 are marked with `Sachmet:`
comments in `Horos/Scripts/<Target>/CMake.sh` and `Make.sh`: system libpng and zlib for VTK and
ITK, C++11 for DCMTK, and codecs switched off for Grok and OpenJPEG.

Debug builds are only useful for lldb work; VTK asserts in the debug configuration where Horos
ships release. Runtime checks run through environment variables (`SEKHVET_*_TEST`) rather than
lldb — but only in a build made with the flag `SEKHVET_TESTHAKEN=1`:

```
xcodebuild ... -configuration Release -xcconfig SekhVet/SekhVet-Testhaken.xcconfig
```

A build without the flag reads none of the environment hooks (`strings Horos | grep -c SEKHVET_`
is 0; the test methods themselves stay compiled but are unreachable);
rebuild without it before installing or shipping. The hooks are declared in
`Horos/Sources/SekhmetTesthaken.h`.

## Versioning

Builds are numbered consecutively (`CFBundleVersion`, shown in the About window and in the
feedback template). The public beta (builds 45–149) was tagged `v1.0-beta.<build>` and published as
pre-releases; 1.0 is tagged `v1.0` and its DMG is named `SekhVet-1.0-build<N>-macOS.dmg`. The
update check reads the build number from that file name. The public repository receives one commit per release on
top of the Horos history, authored by Kappa1-VRS GmbH; the day-to-day history stays in the
private working repository.

## Licence and attribution

SekhVet is free software under the **GNU Lesser General Public License, version 3.0**. The full
licence texts are in [`COPYING.LESSER`](COPYING.LESSER) (LGPL-3.0) and [`COPYING`](COPYING)
(GPL-3.0, to which the LGPL refers); [`LICENSE`](LICENSE) carries the licensing history of Horos
and OsiriX.

SekhVet is a fork of Horos, which is based on OsiriX. Portions © Horos Project and © OsiriX
Foundation / Pixmeo SARL. Horos and OsiriX are trademarks of their respective owners. This
project is **not affiliated with, endorsed by or supported by** the Horos Project or Pixmeo
SARL. Please do not send SekhVet issues to them.

SekhVet itself: © 2026 Kappa1-VRS GmbH, Zurich.

## Acknowledgements

SekhVet builds on the work of others. Thank you:

- **The Horos Project** and **OsiriX** — the viewer SekhVet is built on.
- **Thales Santos ([ThalesMMS/horos](https://github.com/ThalesMMS/horos))** — fixes adapted in
  build 119: the mean projection is now kept per MPR window instead of globally, the database list
  draws its rows without side effects, the study list is refreshed in batches during imports,
  notifications are grouped, patient data is kept out of the system log, and several small fixes
  (shutter, window/level threads, C-GET progress).
- **Yves Starreveld ([ystarrev/horos](https://github.com/ystarrev/horos))** — fixes adapted in
  build 119: the database index is never deleted silently when it cannot be opened, faster
  import of large batches, search in series descriptions, the Query window toolbar and slider
  tick marks for macOS 27.
- **Hiroaki Inomata ([PHORLIX](https://github.com/Hiroaki-Inomata/PHORLIX-community))** — the idea
  of importing studies from other Horos/OsiriX databases (build 120, own implementation, with his
  kind permission), and the original Japanese resources of Horos.

Code taken from the forks above is LGPL-3.0 like SekhVet; the origin is noted in the source
comments at each place ("nach ThalesMMS/horos …", "nach ystarrev/horos …").

## Contributing

Bug reports and pull requests are welcome. Please keep in mind that this is a maintenance fork:
changes to the viewer core (`DCMView`, `MPR*`, `ROI`) need a measurement check on a real image,
not just "looks right".

If SekhVet is useful to you, a voluntary contribution helps keep development going —
**Vet Tools › Contribute to SekhVet…** in the application. The amount is free to choose; there
is no service, licence or extra feature in return.
