# SekhVet

A veterinary DICOM viewer for macOS. SekhVet is a fork of [Horos](https://horosproject.org)
4.0, which is based on OsiriX, with a layer of tools for veterinary radiology.

Developed and maintained by Kappa1-VRS GmbH, Zurich, Switzerland.

**Status: public beta.** See [Beta status](#beta-status) below before you rely on a function.

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

## Beta status

SekhVet 1.0 is published as a **beta**. The Horos core and most veterinary tools have been in
daily use in one practice since September 2026. Some functions have been tested on few devices
or not yet on a real device; they are marked **experimental** here and in the manuals. Version
1.0 without the beta suffix follows once these have been verified by more than one practice.

| Function | Status |
|---|---|
| Orientation letters, 2D hanging protocol, window presets | in daily use |
| Norberg angle, distraction index | in daily use |
| Point tool, double MPR, convolution filters | in daily use |
| DICOMweb query / retrieve / send | in daily use |
| Image and PDF import, rename patient, display settings | in daily use |
| Hanging protocol in the 3D MPR | **experimental**, rebuilt in September 2026, device verification running |
| Opening protocols, two-view radiograph hanging | **experimental**, device verification running |
| Spine labeling | **experimental**, counting logic still being adjusted |
| Ultrasound calibration from a neighbouring image | **experimental**, one device tested (Mindray Vetus 9) |
| MPR double-click zoom | rare black or white view after the double-click; safeguards in build 92, diagnostic line in the system log |
| macOS 27 | one test installation; daily use is on macOS 26 |

What a beta means here: no function is known to corrupt data, measurements are reproducible on
the devices tested, but wording, defaults and edge cases will still change between builds. Keep
Horos or OsiriX installed alongside if you depend on them; SekhVet does not touch their data.

## Why this fork exists

Horos is a good viewer, but it thinks in human terms: A/P and S/I orientation letters, hanging
protocols for an upright patient, no spine counting with 13 thoracic vertebrae, no Norberg
angle. Upstream Horos has seen almost no maintenance since 2025.

SekhVet keeps the Horos core untouched — database, 2D viewer, 3D MPR, volume rendering, CPR,
fusion, subtraction, key images, export, DICOM networking, plugins — and adds what is missing
in daily veterinary work. It is a maintenance fork, not an upstream contribution: no ARC, no
Metal, no Swift rewrite.

## What SekhVet adds

Everything below lives in the **Vet Tools** menu unless stated otherwise.

| | |
|---|---|
| **Orientation letters** | Cr/Cd and D/V instead of A/P and S/I, in 2D, MPR and on the 3D orientation cube |
| **Hanging protocol** | Presets Head/Spine, Limbs, Custom; orientation rules per preset; keyword rules per study description; rotation and flip rules per radiography device; works in the 3D MPR too |
| **Opening protocols** | Which series open on double-click, in which layout and with which window; templates for MR head, spine and stifle; two-view radiographs hang VD left, lateral right |
| **Window presets** | Modality and description rules for window level and width on opening |
| **Spine labeling** | Click counter for dog/cat, rabbit and horse; disc labels; rename with recount; labels stored as ROIs and shown in all planes, with the vertebral level in the transverse view |
| **Norberg angle** | Hip dysplasia measurement on the VD pelvis: draggable femoral head circles, radius grip and mouse wheel, live angle, value stored with the study |
| **Distraction index** | PennHIP-style laxity measurement on the distraction view, sharing the femoral head circles with the Norberg angle; optional risk level |
| **Point tool** | One click shows the same location in all other open series of the study |
| **Double MPR** | Two MPR windows of one study stay in sync: crosshair, planes, thickness, rotation, zoom per view |
| **MPR extras** | Convolution filters on all three planes, larger crosshair hit zones, quiet cursor, no high-dynamic-range dialog |
| **Ultrasound** | Length measurements on frames without calibration data borrow the calibration of a neighbouring frame with the same depth scale |
| **Rename patient** | Writes name, ID, birth date and sex into the DICOM files of one or more studies, or takes the identity from an existing patient |
| **Display** | Screen area per monitor, readable annotation text, dark mode, modality colours in the database |
| **DICOMweb** | QIDO-RS search, WADO-RS retrieve as a stream, STOW-RS send; Basic Auth in the keychain |
| **Import** | Photos and PDFs into a study as DICOM, optionally attached to an existing study |
| **Feedback** | Send Feedback… opens a prepared e-mail with build and macOS version |

Removed from Horos: the Horos Cloud plugin and the hourly update check.

## Documentation

- [`docs/Manual-EN.md`](docs/Manual-EN.md) — user guide, English
- [`docs/Anleitung-DE.md`](docs/Anleitung-DE.md) — Bedienungsanleitung, Deutsch
- [`docs/DISCLAIMER.md`](docs/DISCLAIMER.md) — regulatory status, wording in English and German

## Requirements

- Apple Silicon Mac (M1 or later). There is no Intel build.
- macOS 12 Monterey or later. Tested on macOS 26 Tahoe; one test installation on macOS 27.
- For DICOMweb: a server offering QIDO-RS and WADO-RS, for example Orthanc with the DICOMweb
  plugin.

## Install

Download the zip from the [releases page](https://github.com/3v3nFloW/sekhvet/releases),
unzip it and drag `SekhVet.app` to `/Applications`. Beta builds are marked as pre-releases.
The SHA-256 of each zip is in the release notes.

SekhVet is ad-hoc signed and **not notarised**, so macOS blocks the first launch. Afterwards go
to **System Settings › Privacy & Security › "Open Anyway"**. Since macOS 15 the right-click ›
Open workaround no longer exists. The alternative:

```sh
xattr -d com.apple.quarantine /Applications/SekhVet.app
```

On first launch SekhVet shows a one-time notice that it is not a certified medical device.

SekhVet keeps its own database (`~/Documents/SekhVet Data`), preferences
(`vet.kappa1.sekhvet.horos`), plugin folder (`~/Library/Application Support/SekhVet/Plugins`)
and DICOM port (11113 instead of 11112), so it can sit next to an existing Horos or OsiriX
installation without touching it.

SekhVet does not check for updates. New builds are published on the releases page. Quit the
running copy before replacing it; database and settings are kept.

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
feedback template). The beta carries the version string `1.0 beta`; releases are tagged
`v1.0-beta.<build>` until 1.0 final. The public repository receives one commit per release on
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

## Contributing

Bug reports and pull requests are welcome. Please keep in mind that this is a maintenance fork:
changes to the viewer core (`DCMView`, `MPR*`, `ROI`) need a measurement check on a real image,
not just "looks right".

If SekhVet is useful to you, a voluntary contribution helps keep development going —
**Vet Tools › Contribute to SekhVet…** in the application, or the link at
[kappa1.vet](https://kappa1.vet). The amount is free to choose; there is no service, licence or
extra feature in return.
