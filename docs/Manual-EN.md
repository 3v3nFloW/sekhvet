# SekhVet — User Guide (English)

Version 1.0 beta, build 95 · 17 September 2026

> **SekhVet is a veterinary DICOM viewer and is not a certified medical device.**
> It is not cleared by the FDA, not CE-marked and has not undergone any formal validation.
> It is intended for use in veterinary medicine, research and education only and must not be
> used for the diagnosis or treatment of humans. Measurements and orientation aids are tools;
> the interpretation of images and the diagnosis remain the responsibility of the
> veterinarian. SekhVet is provided "as is", without warranty of any kind (GNU LGPL v3).

> **Public beta.** SekhVet 1.0 is published as a beta. The Horos core and most veterinary tools
> are in daily use in one practice; some functions are marked *experimental* and have been
> tested on few devices or not yet on a real device. Section 7 lists them. Please report what
> you find (section 5.15).

## 1. What SekhVet is

SekhVet is a fork of Horos 4.0 (horosproject.org), which in turn is based on OsiriX. The
Horos core is unchanged: database, 2D viewer, 3D MPR, volume rendering, CPR, fusion,
subtraction, key images, export, DICOM networking (C-STORE, C-FIND, C-MOVE, WADO-URI),
plugins. Everything you know from Horos works the same way.

On top of that sits a layer of veterinary functions, collected in the **Vet Tools** menu,
plus a number of usability improvements. The SekhVet user interface is English.

Developed and maintained by Kappa1-VRS GmbH, Zurich, Switzerland. Licensed under the GNU
LGPL-3.0, source code on GitHub. Horos has seen almost no maintenance since 2025; SekhVet is
an independent maintenance fork, not an upstream contribution.

## 2. System requirements

| | |
|---|---|
| Mac | Apple Silicon (M1 or later). No Intel build. |
| macOS | 12 Monterey or later. Tested on macOS 26 Tahoe (daily use) and macOS 27 (build 93, test installation). |
| Display | Any display; the "Screen Area" feature is designed for wide monitors. |
| Network | For DICOMweb, a server with QIDO-RS/WADO-RS (e.g. Orthanc with the DICOMweb plugin). |

## 3. Installation

1. Download `SekhVet-1.0-beta-build95-macOS.zip` from the releases page,
   https://github.com/3v3nFloW/sekhvet/releases, and unzip it.
2. Drag `SekhVet.app` to `/Applications`. If an older SekhVet copy is already there, **quit it
   first**, then replace it. If two copies run at the same time, the second one reports
   "DICOM Listener Error" because the receive port is already taken.
3. **Gatekeeper:** SekhVet is ad-hoc signed, not notarised (no Apple Developer account).
   macOS blocks the first launch. Then go to **System Settings › Privacy & Security › "Open
   Anyway"**. Since macOS 15 the right-click › Open workaround no longer exists.
   Alternative in Terminal:
   ```
   xattr -d com.apple.quarantine /Applications/SekhVet.app
   ```
4. On first access to your Documents folder macOS asks for permission. Click "Allow",
   otherwise the database window stays empty.
5. **On first launch** SekhVet shows a one-time notice that it is not a certified medical
   device. "I understand" confirms it, "Quit" leaves the program. The notice returns only if
   its wording changes.
6. Checksum (optional): `shasum -a 256 SekhVet-1.0-beta-build95-macOS.zip` must match the value
   shown on the releases page.

**SekhVet next to Horos or OsiriX:** SekhVet has its own database (`~/Documents/SekhVet Data`),
its own preferences and its own plugin folder (`~/Library/Application Support/SekhVet/Plugins`).
Horos and OsiriX remain untouched and can stay installed side by side. SekhVet listens on DICOM
port 11113 (Horos: 11112), so both can run at the same time. The port can be changed under
Preferences › Listener.

**Updates:** SekhVet does not check for new versions. New builds appear on the GitHub releases
page. Copy a new build over the old one (quit it first); database and settings are kept.

## 4. First steps

1. Bring in studies as in Horos: drag files into the window, **File › Import**, DICOM receive on
   port 11113, or via DICOMweb (section 5.12). While data is arriving, the Dock shows the SekhVet
   emblem with an arrow.
2. Double-click a study to open it. Which series open and how they hang is decided by the
   opening protocols (5.3) and the hanging protocol (5.2). Radiograph studies with exactly two
   views hang VD on the left, lateral on the right (5.3).
3. SekhVet's own windows open inside the viewer area and live in the **Vet Tools** menu.

## 5. Vet Tools in detail

### 5.1 Veterinary orientation letters

Horos writes A/P, S/I, R/L at the image edges. SekhVet writes **Cr/Cd** (cranial/caudal),
**D/V** (dorsal/ventral) and **R/L**; in 2D, in the MPR and on the orientation cube of the 3D
windows.

The mapping is A → V, P → D, S → Cr, I → Cd; R and L stay as they are.

The letters are on out of the box. To get the Horos letters back, type in Terminal:
```
defaults write vet.kappa1.sekhvet.horos VetOrientationLetters -bool NO
```
and restart SekhVet.

### 5.2 Hanging Protocol (Vet Tools › Hanging Protocol…)

Hangs series the veterinary way: rotation and flip by rules per preset. It is purely a
display transformation; pixel data is never modified.

- **Presets:** Off · Head / Spine · Limbs · Custom. Default in the panel, per-study switching
  via the popup in the viewer toolbar.
- **Rules per preset** (individually switchable):
  "Sagittal: cranial left", "Transverse: dorsal up", "Dorsal plane: cranial up",
  "Patient left on the right side of the image".
- **Keywords:** table "study/series description contains … → preset". A match overrides the
  default. Example: "elbow", "shoulder", "carpus" → Limbs.
- **Radiographs (DX/CR):** rule per source (station/modality → rotation, flip). Images from a
  device that "always comes in wrong" hang correctly from the first opening.
- **Apply Hanging Protocol to Open Viewers** applies the preset to all open windows.
- **Take from screen** copies the orientation of the open windows into the selected protocol.
- Also works in the **3D MPR**: the three planes are rotated so the letters are right
  (sagittal Cr left, transverse D up, dorsal Cr up), even if the planes were oblique before.
  Popup in the MPR toolbar. The last straightened position of a series is remembered per preset
  and restored the next time it opens.
- Localizers and oblique series are flagged, not rotated.
- Window/level is not touched here (see 5.4).

With preset **Off**, SekhVet behaves like Horos and restores the last saved orientation.

### 5.3 Opening protocols (Vet Tools › Opening Protocols (which series open)…)

Defines per modality and body region **which series** open on double-click, in which layout
and with which window/level. If a protocol matches, it does everything; if none matches, Horos
opens the study as usual.

- **Detection** from the first file of each series: region from series name, protocol name
  and body part; for CT the window rule (e.g. Soft tissue, Bone) from the convolution kernel
  and the contrast phase (native / contrast as a whole word); for MR the sequence name.
- **Templates** for MR head (2×2: T2 sag · T2 tra · T1 tra · T1 tra post contrast), spine (1×2)
  and stifle (1×4); everything is editable. Empty tiles can be filled black.
- **Take from screen:** open the study the way it should look, then press the button; the
  positions of the selected protocol are filled from the open windows.
- **Two-view radiographs:** if a study contains exactly two radiographs of the same body part,
  the VD/DV view hangs on the left and the lateral view on the right. Switch and side choice
  ("lateral on the left") in the same panel.

### 5.4 Window/level on opening (Vet Tools › Window Presets (WL/WW on open)…)

Rules "modality + description contains … → window values" (e.g. Bone (vet), Soft tissue) that
apply when a series opens. The opening protocols (5.3) use the same rule names.

### 5.5 Spine Labeling (Vet Tools › Spine Labeling…)

Count vertebrae by clicking, in CT MPR and MR stacks.

1. Open the panel: choose species (**Dog / Cat 7-13-7-3**, **Rabbit 7-12-7-4**,
   **Horse 7-18-6-5** = C-T-L-S), start label (e.g. L1) and counting direction.
2. Click with the point tool: every click places the next label; transitions
   C7→T1→…→L7→S1→…→Cd1 are automatic.
3. **Alt-click** places a disc label ("L1-L2").
4. **⌫** removes the last label, **Esc** ends labeling.
5. **Rename with recount:** double-click a point, change its name (e.g. L1 → T13); all
   subsequent labels of the series are renumbered.

Labels are ordinary point ROIs, stored in the database and visible in all MPR planes. In the
transverse view, "▶ Spine level: L3" appears top left for the nearest vertebra. Toolbar
button "Spine Labeling" in 2D and MPR windows.

### 5.6 Norberg angle (Vet Tools › Norberg Angle (Hip Dysplasia) — Place / Reset)

Hip dysplasia assessment on the VD pelvis (extended view). The menu item or the **Norberg
Angle** toolbar button places two femoral head circles (R blue, L red) and two points for the
cranial acetabular rim in the frontmost 2D window.

- **Move a circle:** grab it at the centre and drag (large hit zone).
- **Change the radius:** drag the yellow grip outside the circle, or use the **mouse wheel**
  over the circle.
- **Acetabular rim:** drag the point onto the cranial acetabular edge.
- The angle is drawn live (arm, arc, value at 10 o'clock for R, 2 o'clock for L) and stored in
  the point's name ("Norberg R: 104.3°"). It stays in the database and returns the next time
  the study is opened.
- **Reset:** run the menu item or button again → the measurement is placed afresh in the
  centre of the window.
- **Delete Norberg Measurement** (menu or the "Delete Norberg" toolbar button) removes it.
- Screen left = patient right (VD convention). Flipping the image does not change the
  assignment.

The angle measured is the inner angle between the line connecting the two centres and the
line centre → acetabular rim, in millimetres via the image's pixel spacing, rounded to 0.1°.
A rim point placed caudally instead of cranially yields the same inner angle; the point belongs
on the cranial rim. **Not included:** Flückiger score and automatic hip grade. Grading
according to FCI or another scheme is done by the veterinarian.

### 5.7 Distraction index (Vet Tools › Distraction Index (PennHIP) — Place / Reset)

Laxity measurement on the **distraction view** using the PennHIP formula. The menu item or the
**Distraction Index** toolbar button places two circles per hip: the femoral head circle
(R blue, L red, shared with the Norberg angle) and a yellow circle for the acetabulum.

- **Femoral head circle:** fit it to the femoral head; radius via the yellow grip outside or the
  mouse wheel.
- **Acetabular circle:** fit it to the acetabulum; grip on the inner side, mouse wheel over the
  circle. Where the two circles overlap, the one whose centre is nearer to the pointer responds.
- **DI** = distance between the two centres divided by the femoral head radius. A red line joins
  the centres; the value is shown below the femoral head ("DI 0.65") and stored in the name of
  the acetabular circle.
- **Show DI Risk Level** (checkmark in the Vet Tools menu) adds the level to the label:
  < 0.30 low · 0.30–0.70 moderate · > 0.70 high. These are practice cut-offs; the breed-related
  interpretation according to PennHIP remains a matter of judgement.
- **Delete Distraction Index** (menu or the "Delete DI" toolbar button) removes the acetabular
  circles.
- Norberg angle and distraction index share the femoral head circles. Both measurements can sit
  on the same image; resetting or deleting one keeps the circles as long as the other needs them.

An official PennHIP DI requires certification and submission; SekhVet measures with the same
formula for practice use.

### 5.8 Point tool "show this point in all other series"

Toolbar button **Point** (crosshair icon): a click into the image shows the same location in
all other open series of the study and jumps to the matching slice there (in Horos only
reachable via Alt-double-click). The markers disappear when you scroll on or change the tool.

### 5.9 Rename patient (Rename Patient (DICOM)…)

In the database context menu (below "Unify patient identity") and in **Vet Tools**. Writes
name (Owner^Animal), patient ID, birth date and sex into the DICOM files of one or more selected
studies; the previous values go into Other Patient Names/IDs, as with Horos' "Unify". The
**Take identity from** popup copies the data of an existing patient, so that a radiograph
registered as "emergency" ends up under the right animal. Open viewers are closed first; the
database is changed only after the files were written successfully. A PACS that already holds
the study keeps the old name.

### 5.10 Double MPR

Two MPR windows of the same study (e.g. native and contrast) stay in sync: crosshair point,
plane position, slab thickness, rotation/flip and the zoom per view (sagittal ↔ sagittal
etc.). Window/level stays independent per window. Requires the same study and the same Frame
of Reference.

- **MPR-Sync** switch in the MPR toolbar (on by default).
- New MPR windows open above their 2D series and are tiled inside the viewer area; they remain
  freely movable.
- A second MPR adopts the position of the first when it opens.
- **Double-click a view** to enlarge it to the whole window; a second double-click restores the
  three views. The other MPR window is not affected.

### 5.11 Further MPR improvements

- **Convolution filter (SekhVet):** popup in the MPR toolbar; Gaussian, Sharpen, Unsharp Mask,
  Highpass on all three planes.
- **Thick Slab** defaults to Mean (Horos: MIP).
- **Zoom** (checkbox in the MPR toolbar): couples the zoom of the three views of one window.
  Off by default; between windows the zoom always follows per view.
- **Crosshair hit zones** larger than in Horos (centre 18 px, lines 12 px), adjustable in
  Vet Tools › Display.
- **Quiet cursor:** Horos changes the pointer depending on position; SekhVet keeps the arrow
  (can be switched off in Display).
- CT with a very large value range is clipped to −1024…7168 HU without asking (the Horos
  "High Dynamic Values" dialog is gone).

### 5.12 DICOMweb (Vet Tools › DICOMweb Query (QIDO-RS / WADO-RS)…)

Horos only speaks DIMSE (C-FIND/C-MOVE) and WADO-URI. SekhVet has its own DICOMweb window
that works against Orthanc, dcm4chee and other servers.

1. **Add a node:** URL up to `/dicom-web` (e.g. `http://pacs.local:8042/dicom-web`) and user
   name. The password is requested on first retrieval and stored in the keychain (Basic Auth).
2. **Search** by name, ID, date, modality; date popup (default **Today**; Any date, Yesterday,
   Last 3 days, Last 4 days, Last week, Last month). Results show series, image count, time and
   institution. A ball in front of the name shows whether the study is already fully (green) or
   partially (orange) in the local database, as in the Horos Q/R window.
3. **Retrieve:** load selected studies via WADO-RS; images go into the database. Large
   studies are streamed, not held in memory in full.
4. **Send:** **Vet Tools › Send Selected Studies via STOW-RS…** or the button in the window
   sends the studies selected in the database to the node.

Toolbar button **DICOMweb** in the database next to "Query". The classic Horos Locations
(DIMSE) remain fully usable.

### 5.13 Image / PDF as DICOM (Vet Tools › Import Image / PDF as DICOM…)

Put photos, screenshots, lab reports and referral letters into the study.

- Formats: JPG, PNG, TIFF, GIF, BMP, HEIC, PDF.
- Fields: patient, ID, birth date, sex, study/series description, modality (OT, XC, ES, DX, US).
- **Attach to selected study:** takes patient data and Study UID from the study selected in the
  database.
- **PDF page by page as images** (150 dpi) or as Encapsulated PDF.
- Files of these types dropped into the database or chosen via **File › Import** are routed
  to this dialog automatically.

### 5.14 Display (Vet Tools › Display (Screen Area, Annotations, MPR)…)

- **Screen Area:** define per display which part the viewer windows occupy (fractions such as
  "right 2/3" or a pixel rectangle). The **Screen** popup in the viewer toolbar retiles
  immediately. Replaces Magnet and similar tools on wide monitors.
- **Annotations:** font, size (default Helvetica Bold 14), text colour (default white),
  outline/box (default: 70 % black box with outline) for measurement text, corner text and the
  values of the hip measurements. Changes take effect immediately.
- **Appearance:** System / Light / Dark, default Dark.
- **Modality colours:** study and series rows in the database tinted by modality (CT blue, MR
  violet, radiographs green, US orange …). Can be switched off.
- **Magnetic windows:** off by default; windows stay freely movable.
- **MPR:** hit zones, static cursor, MPR sync, tiling, zoom sync.

### 5.15 Feedback and contribution

- **Send Feedback…** opens an e-mail to the SekhVet mailbox with a filled-in template (build,
  macOS, what happened). Crop or anonymise images with patient data first.
- **Contribute to SekhVet…** shows two payment QR codes (Swiss QR bill in CHF, GiroCode in EUR)
  with the IBAN to copy. No payment provider in between, amount free, nothing in return.
- **Dictate with VoiceInk** leads to the partner link of the dictation software.
- **GitHub:** bug reports and feature requests can also be filed as issues at
  https://github.com/3v3nFloW/sekhvet/issues. The same rule applies: no screenshots with owner
  or animal names.

### 5.16 Ultrasound: calibration from a neighbouring image *(experimental)*

Some ultrasound devices write single frames without calibration data (no ultrasound region
and no pixel spacing), so length measurements on such an image only show pixels. SekhVet then
borrows the calibration from another image of the same series, provided both are the same size
and show the same depth scale on the right edge (checked by comparing the scale strips). The
measurement text carries the note "US calibration from image N" so the origin stays visible.
Cine loops are never used as a source. The fallback can be switched off in Terminal:
```
defaults write vet.kappa1.sekhvet.horos SekhmetUSCalibrationFallback -bool NO
```
Tested so far with one device (Mindray Vetus 9). If a borrowed calibration is wrong for your
device, switch it off and report the device model.

## 6. Behaviour that differs from Horos

| Topic | Horos | SekhVet |
|---|---|---|
| Orientation letters | A/P, S/I | Cr/Cd, D/V (switchable) |
| Hanging | rows/columns per modality | presets with orientation rules, keywords, DX rules, opening protocols |
| Making a window active | right-click/scroll wheel | left-click as well |
| Measurement text | Geneva 12 in ROI colour | Helvetica Bold 14, white on a box |
| Appearance | follows system | Dark by default, switchable |
| Propagate settings | re-enabled by protocols | stays off until you switch it on |
| Magnetic windows | on | off |
| Thick slab | MIP | Mean |
| Opening a series | slider with one tick per image (slow on large series) | no ticks, noticeably faster |
| Update check | hourly against the Horos server | none |
| Horos Cloud | plugin | removed |
| Data folder | Horos Data | SekhVet Data |
| DICOM port | 11112 | 11113 |

All SekhVet windows open inside the viewer area. All SekhVet toolbar buttons can be moved or
removed via **Customize Toolbar**; new buttons appear once automatically, and stay away if you
remove them.

## 7. Beta status, limitations and known restrictions (build 95)

**Experimental in this beta.** These functions work, but have been tested on few devices or
are still being adjusted. Use them with a critical eye and report what you see:

- **Spine Labeling** (5.5): the counting logic is still being adjusted.
- **Hanging protocol in the 3D MPR** (5.2, MPR part) and **opening protocols** (5.3) including
  the two-view radiograph hanging: rebuilt in September 2026, verified headless, device
  verification still running.
- **Ultrasound calibration from a neighbouring image** (5.16): one device tested.
- **MPR double-click zoom** (5.10): in rare cases a view came up black or white after the
  double-click; build 92 added safeguards, and if it happens again a diagnostic line is written
  to the system log (`log show --predicate 'process == "Horos"' --last 30m | grep "SekhVet MPR"`).
- **macOS 27:** one test installation so far; daily use is on macOS 26.

**In daily use** (stable in the sense of this beta): orientation letters, 2D hanging protocol,
window presets, Norberg angle, distraction index, point tool, double MPR, convolution filters,
DICOMweb query/retrieve/send, image and PDF import, rename patient, display settings, feedback
and contribution windows.

**General limitations:**

- **Not a certified medical device** (see above). No formal validation of measurements.
  Veterinary devices fall outside EU Regulation 2017/745 and the Swiss MepV, which apply to
  devices for human use. There is no certification scheme for veterinary imaging software in
  either jurisdiction.
- **Apple Silicon only**, macOS 12 or later; tested in practice on macOS 26 and 27.
- **Not notarised:** Gatekeeper workaround on first launch (section 3).
- **Old core:** SekhVet is a maintenance fork without modernisation (OpenGL, no Metal, no
  Swift). Known Horos quirks remain. In return it stays compatible with Horos plugins and
  Horos habits.
- **Reports:** SekhVet uses the Horos report path. The **Report** button opens Pages with the
  template from the database's `PAGES TEMPLATES` folder (the default); it can be switched to
  Word, TextEdit (RTF) or LibreOffice. There is no built-in report editor.
- **DICOMweb:** Basic Auth only (no OAuth/token), no instance-level QIDO, node list not
  imported from Horos Locations.
- **Hip measurements:** no Flückiger panel, no hip grade; the distraction index is a practice
  measurement, not an official PennHIP value.
- **Rename patient:** non-ASCII characters depend on the character set of the files; a PACS
  that already holds the study keeps the old name.
- **Spine labeling** is meant for CT and MR, not for radiographs.
- **Language:** English UI, no localisation.
- **No automatic updates**; new builds are announced on GitHub.

## 8. Licence, source code, contribution

SekhVet is free software under the GNU Lesser General Public License 3.0 and is based on
Horos (Horos Project) and OsiriX (Pixmeo SARL). The complete source code of this version,
including all changes to Horos, is at https://github.com/3v3nFloW/sekhvet (also behind
"Source code" in the About window).

If SekhVet is useful to you, a voluntary contribution helps keep development going:
**Vet Tools › Contribute to SekhVet…** The amount is free to choose; there is no service or
extra feature in return.

© 2026 Kappa1-VRS GmbH, Zurich. Horos and OsiriX are trademarks of their respective owners.
