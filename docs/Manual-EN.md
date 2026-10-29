# SekhVet — User Guide (English)

Version 1.1.2, build 197 · 29 October 2026

> **SekhVet is a veterinary DICOM viewer and is not a certified medical device.**
> It is not cleared by the FDA, not CE-marked and has not undergone any formal validation.
> It is intended for use in veterinary medicine, research and education only and must not be
> used for the diagnosis or treatment of humans. Measurements and orientation aids are tools;
> the interpretation of images and the diagnosis remain the responsibility of the
> veterinarian. SekhVet is provided "as is", without warranty of any kind (GNU LGPL v3).

> **Version 1.1.** New since 1.0 (build 174): separate **study databases** on external disks,
> including ejecting them from within SekhVet (5.25), **overlay with several contrast phases**
> and a simpler selection (5.20), and **opening protocols** that recognise arterial, venous and
> delayed phases (5.3), and **backing up, exporting and sharing the vet settings** (5.26). SekhVet 1.0 was the first regular release after the public beta (builds
> 45–149). The Horos core and the veterinary tools are in daily use in one practice; section 7
> lists what has been tested on few devices so far. Please report what you find (section 5.15).

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
| macOS | 12 Monterey or later. Tested on macOS 26 Tahoe (daily use) and macOS 27 (test installation, double MPR with a large CT). |
| Display | Any display; the "Screen Area" feature is designed for wide monitors. |
| Network | For DICOMweb, a server with QIDO-RS/WADO-RS (e.g. Orthanc with the DICOMweb plugin). |

## 3. Installation

1. Download `SekhVet-1.1-build190-macOS.dmg` from the releases page,
   https://github.com/3v3nFloW/sekhvet/releases, and open it. The zip file on the same page
   contains the same app, for those who prefer it.
2. In the window that opens, drag SekhVet onto the Applications folder, then eject the disk
   image. If an older SekhVet copy is already there, **quit it first**, then replace it. If two copies with the DICOM
   listener enabled run at the same time, the second one reports "DICOM Listener Error" because the receive port is already taken.
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
   its wording changes. Right after it, SekhVet asks once whether it may check GitHub for
   updates once a day ("SekhVet can check GitHub once a day …"): **Check for Updates** or
   **Don't Check**; you can change this later in Preferences › General.
6. Checksum (optional): `shasum -a 256 SekhVet-1.1-build190-macOS.dmg` (or the zip) must
   match the value shown on the releases page.

**SekhVet next to Horos or OsiriX:** SekhVet has its own database (`~/Documents/SekhVet Data`),
its own preferences and its own plugin folder (`~/Library/Application Support/SekhVet/Plugins`);
web portal users and templates also live under `~/Library/Application Support/SekhVet/` and
start empty. Horos and OsiriX remain untouched and can stay installed side by side. URLs of the
form `sekhvet://` open in SekhVet; `horos://` stays with Horos.
Such a link only runs its command when **Activate the URL support and HTTP XML-RPC Server** is
on (Preferences › Listener, off by default); otherwise SekhVet shows a notice and does nothing
*(since build 189; before, the command ran anyway)*.

**Network: the DICOM listener is off by default.** A fresh installation receives nothing, does
not announce itself via Bonjour and answers neither C-FIND nor C-GET; its identity on the
network is a random UUID. Sending to other nodes works right away, as does DICOMweb (5.12). To
receive: **Preferences › Listener**, enable the listener, set the port (suggested 11113; Horos
uses 11112, so both can run at the same time) and the AE title, then restart SekhVet. Without a
listener there is no classic query/retrieve (the query says so). "Reset preferences" switches
the listener off again. SekhVet does not check for plugin updates; the web tab of the plugin
manager is empty.

**Updates:** SekhVet can check GitHub once a day for a new release (asked at first start,
switchable in Preferences › General). It checks at most every 24 hours, about 15 seconds after
launch, and only against regular releases. If a newer version exists, a dialog shows the release
notes and offers **Download** (opens the DMG address in your browser), **Release Notes**,
**Later** and the checkbox **Skip this version**. SekhVet never installs anything itself: you
download the DMG and install it by hand; copy the new build over the old one (quit it first),
database and settings are kept. **SekhVet › Check for Updates** checks immediately and reports
"up-to-date (build N)" or "No Internet connection"; if a release carries no build number,
SekhVet says it cannot tell whether it is newer and offers **Open Releases Page**.

**Database index:** if the index cannot be opened at launch, the dialog offers **Try Again**,
**Reveal in Finder**, **Reset SQL Index…** and **Quit SekhVet**; the old index is always backed
up before a rebuild.

## 4. First steps

1. Bring in studies as in Horos: drag files into the window, **File › Import**, DICOM receive
   (after enabling the listener, section 3), via DICOMweb (section 5.12) or from a Horos/OsiriX
   database (5.18). While data is arriving, the Dock shows the SekhVet emblem with an arrow.
2. Double-click a study to open it. Which series open and how they hang is decided by the
   opening protocols (5.3) and the hanging protocol (5.2). Radiograph studies with exactly two
   views hang VD on the left, lateral on the right (5.3).
3. In the viewer's series bar and in the database preview the thumbnails carry **badges**: for
   MR the sequence (T1, T2, FLAIR, STIR …), for CT and MR **KM** for a contrast series and SUB
   for subtractions. The series name is shown in up to three lines below the thumbnail, the full
   name as a tooltip.
4. SekhVet's own windows open inside the viewer area and live in the **Vet Tools** menu. The
   Help menu only contains **Report a bug** (opens the SekhVet issues page).

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

A hanging protocol decides **how a series is turned on screen**: which anatomical direction
points up and which points left, in 2D windows and in the three planes of the 3D MPR. It is
purely a display transformation (rotation and flip); pixel data is never modified. Which
series open, and in which grid, is a different matter — see opening protocols (5.3).

**The protocols.** SekhVet ships with *Head / Spine*, *Hindlimbs*, *Forelimbs*, *Custom 1* and
*Custom 2*, plus **Off**. With Off, SekhVet behaves like Horos and restores the last saved
orientation. The list on the left of the panel is yours to edit:

| You want to … | Do this |
|---|---|
| add a protocol | **+** below the list; type a name. It starts with the rules of Head / Spine. |
| rename a protocol | double-click its name. |
| change the order | drag the row. The popups in the viewer and MPR toolbars follow this order. |
| delete a protocol | select it, **−**. Its rules, MPR layout and keywords go with it; studies that used it fall back to the keyword or default protocol. The three built-in ones (Head / Spine, Hindlimbs, Forelimbs) can be renamed and moved but not deleted. |

Renaming and reordering never breaks anything: keywords, rules, MPR layouts and the choice
remembered per study are tied to the protocol itself, not to its name or position. The panel
can be resized; it remembers its size.

**Rules of the selected protocol** (right side of the panel; select a protocol first). The four
rule switches apply to protocols **without an MPR layout of their own** ("Standard layout"); if
a protocol has a layout ("Take from screen", see below), the layout decides the orientation per
plane and the switches have no effect.

| Rule | On | Off |
|---|---|---|
| Transverse: dorsal up | dorsal at the top | ventral at the top |
| Sagittal: cranial left | cranial on the left, dorsal up | cranial/proximal at the top (limbs) |
| Dorsal plane: cranial up | cranial at the top | cranial on the left |
| Patient left on the right side of the image | radiological convention | left is left |
| Limb: proximal = caudal (forelimb) | for a forelimb stretched forward: caudal (= proximal) at the top | — |

**Which protocol a study gets**, in this order:

1. what you chose for this study in the **Hanging Protocol popup** of the viewer or MPR toolbar
   (remembered per study, also after a restart). The first entry of the popup, **Automatic (by
   keywords)**, cancels that choice again;
2. the **keyword** found in the study or series description (table "Keywords": text →
   protocol; e.g. "elbow", "shoulder", "carpus" → Forelimbs). If several match, the longest wins;
   short keywords only count as whole words ("head" does not match "headrest");
3. the **default protocol** at the top of the panel.

**3D MPR.** The three planes are turned so the letters are right (for Head / Spine: sagittal Cr
left, transverse D up, dorsal Cr up), even if the planes were oblique before. To decide *which
plane sits in which of the three views*: arrange one MPR window the way you want it, select the
protocol in the list and press **Take from screen**. Every MPR window opened with or switched
to this protocol is then arranged like that. **Standard layout** removes the arrangement again.
The last straightened position of a series is remembered per protocol; it is only used as long
as the protocol's rules are unchanged. The MPR window title shows the state, e.g. "HP: Head /
Spine" or "HP: Head / Spine (not applied: oblique)"; **Off** restores the plain title. SekhVet
asks before "Reset".

**An MPR layout also applies in 2D and in the orthogonal MPR.** If a protocol has a layout, it
decides the orientation per plane not only in the 3D MPR but also in the 2D windows and in the
2D Orthogonal MPR. Example, stifle MR: the sagittal series sits in the 2D window the way it does
in the MPR (caudal up, dorsal left), even when freshly dragged into a window. The "Hanging
Protocol" popup is also available in the **Curved MPR** and the **2D Orthogonal MPR**; there the
planes are oriented as in the 3D MPR (in the curved MPR the axis arrangement is left as it is).

**Radiographs (DX/CR)** have no planes; they get a rule per source instead: text found in
StationName or modality → rotation and flips. Images from a device that "always comes in
wrong" then hang correctly from the first opening.

**Apply to open viewers** (button, and Vet Tools › Apply Hanging Protocol to Open Viewers)
applies the current settings to all open windows. Localizers and oblique series are flagged,
not rotated. Window/level is not touched here (see 5.4).

**Two MPR windows side by side.** With "Tile 3D windows automatically when opened" (Vet Tools ›
Display) the MPR windows are arranged in the order of their 2D source series: the MPR of the
series on the left sits on the left, even if you had dragged a window elsewhere. Switch the
option off to place MPR windows yourself; an MPR then opens over its own 2D window.

### 5.3 Opening protocols (Vet Tools › Opening Protocols (which series open)…)

Defines per modality and body region **which series** open on double-click, in which layout
and with which window/level. If a protocol matches, it does everything; if none matches, Horos
opens the study as usual.

- **Detection** from the first file of each series: region from series name, protocol name
  and body part; for CT the window rule (e.g. Soft tissue, Bone) from the convolution kernel
  and the contrast phase (native / contrast as a whole word; *since 1.1* also "arterial",
  "venous", "portal venous", "delayed" and their German forms). If the series name names no
  phase, the DICOM field *Contrast/Bolus Agent* decides: if it is filled, the series counts as
  contrast — this also covers scanners that name native and contrast series alike. For MR the
  sequence name.
- **Templates** for MR head (2×2: T2 sag · T2 tra · T1 tra · T1 tra post contrast), spine (1×2)
  and stifle (1×4). For CT *since 1.1* one protocol each for **spine, head, pelvis/hip, fore- and
  hindlimb, limbs/joints, abdomen and thorax** plus one for all other CT, each 1×3: **bone native ·
  soft tissue contrast · soft tissue native**, for the thorax **lung** instead of bone. SekhVet
  recognises the region from English and German words in the study, series and protocol name and
  the body part (e.g. "Spine", "Cervical", "Wirbelsäule", "Head", "Brain", "Nasal", "Bulla",
  "Dental", "Pelvis", "Hip joint", "Shoulder", "Elbow", "Stifle", "Tarsus", "Abdomen", "Liver",
  "Kidney", "Shunt", "Thorax", "Lung", "Metastasis" …). Everything is editable. Empty tiles can be
  filled black.
- **Order matters:** the first matching protocol from the top wins. A protocol without a region
  applies to every study of its modality — so it belongs at the end of the list, otherwise the
  protocols below it never get their turn. For examinations covering several regions (e.g.
  thorax and abdomen) also write the region as a keyword into the positions, so that each
  position only takes series of that region.
- **Take from screen:** open the study the way it should look, then press the button; the
  positions of the selected protocol are filled from the open windows.
- **Two-view radiographs:** if a study contains exactly two radiographs of the same body part,
  the VD/DV view hangs on the left and the lateral view on the right. Switch and side choice
  ("lateral on the left") in the same panel.

### 5.4 Window presets (Vet Tools › Window Presets (WL/WW)…)

The panel has two parts.

**Rules on opening.** Rules "modality + description contains … → window values" (e.g.
Bone (vet), Soft tissue) that apply when a series opens. The first matching rule from the top
wins. For a CT with a convolution kernel in the header **only the kernel** decides (bone kernel →
bone window), not the series name. *Since 1.1* the Canon kernel `BODY_SHARP` counts as a soft
tissue kernel (in the practice's Canon studies the soft tissue series "WT …" use it). If you have
saved the rules before, your list is kept; then remove `BODY_SHARP` from the rule "Bone (vet)" by
hand. A window you adjusted yourself and saved with the series is
kept when the series is reopened; the rules only apply on the first opening. The opening
protocols (5.3) use the same rule names.

**Global WL/WW presets.** The table below lists the presets of the WL/WW menu in every viewer,
for example "CT - Bone" or "CT - Abdomen". Name, WL and WW can be edited directly; **+** adds a
preset, **−** deletes the selected one, **Reset presets to defaults** restores the SekhVet
values. Open viewers pick up changes immediately. The keys 1–9 apply the presets in the
alphabetical order shown in the table.

### 5.5 Spine Labeling (Vet Tools › Spine Labeling…)

Count vertebrae by clicking, in CT (2D or MPR) and MR. Not meant for radiographs.

**Where to click — this matters.** Place every point **in the centre of the vertebral body**,
on a sagittal image close to the midline. SekhVet derives the level of every other slice from
these points: along the line from one vertebral centre to the next, the first 40 % belong to
the first vertebra, the last 40 % to the next one, and the **middle 20 % are shown as the disc
space** ("L3-L4"). Centres placed consistently give disc labels that sit on the disc; a point
on an end plate shifts the disc zone by that amount. Beyond the first and last labelled
vertebra the level is shown for half a vertebra's distance, then nothing. Special cases: C1 —
click the centre of the atlas ring at the level of the dens; sacrum — one point per segment, or
only S1; a block vertebra or transitional vertebra — see "Formula" below.

**Step by step**

1. Press **Spine Labeling** in the toolbar of the 2D or MPR window (or the menu). The panel
   opens and labeling starts; the point tool is selected.
2. **Species** sets the vertebral formula (**Dog / Cat 7-13-7-3**, **Rabbit 7-12-7-4**,
   **Horse 7-18-6-5** = C-T-L-S). **Formula:** change a number if this animal differs — e.g. L = 6
   or 8, T = 12 or 14 for a transitional vertebra. The changed formula is stored with the study;
   counting and renumbering follow it (with L = 6, S1 follows L6).
3. **Start at:** the vertebra you will click first, e.g. L1 — choose one you can identify with
   certainty (last rib → T13, sacrum → L7, C2).
4. Click the first vertebra, then the neighbouring one. With **Direction: Automatic** SekhVet
   takes the counting direction from these first two clicks (towards the tail = counting up,
   towards the head = counting down). Set the direction by hand if the animal lies unusually.
   The next label is shown in the panel and at the top of the active image ("Spine ▸ next: L3").
5. Keep clicking; transitions C7→T1, T13→L1, L7→S1, S3→Cd1 are automatic.
6. **Disc labels:** click **between** two labelled neighbours and the point becomes "L3-L4"
   without advancing the counter; between two vertebrae that are not neighbours (L2 and L5)
   there is no disc label. **Alt-click** forces a disc label between the last and the next
   vertebra while you are still counting.
7. **⌫** removes the last label; if a measurement is selected in the list, ⌫ deletes that one,
   also while labeling. **Esc**, **Stop** or closing the panel ends labeling; the toolbar tool
   you had before comes back in every window. Counting towards the head ends at C1.

**Label colour** (colour well in the row of "Delete label") sets the colour of the level display,
the projected markers and the names of the label points. Default: the green used so far.

**What you see afterwards**

- **Transverse images** — any series of the study with the same frame of reference, and the
  transverse MPR view — show the level in large green type at the top: "L3", between two
  vertebrae "L3-L4". This works while scrolling and needs no points in that series. The level
  continues across series: with a thorax and an abdomen series, the abdomen series shows L1,
  L2 … rather than "T13" all the way to the pelvis.
- The **dorsal MPR view** shows the level at the position of the crosshair in the same way.
- The **sagittal view** shows the points with their names; in other sagittal series of the
  study they appear as small circles with a leader line.
- **Show the label points** (checkbox in the panel) hides and shows all points at once; the
  level display stays. Starting to label switches the points on again.
- **… also in the transverse and dorsal views** is off by default, so the points do not clutter
  those views. Switch it on when you want to see or **drag** a point there, e.g. to centre it
  left–right.

**Correcting**

- **Drag** a point to move it; the level display follows.
- **Rename with recount:** double-click a label in the panel's list (or the point itself) and
  type the right name, e.g. L1 → T13. All labels caudal to it are renumbered, disc labels
  included, using this study's formula. This is the way to fix a miscount at the start.
- The **list** in the panel shows all labels of the study. Click one to jump all 2D windows of
  the study to that slice. **Delete label** removes one, **Delete all** removes every label of
  the study. Renaming and deleting need the series in which the label was set to be open.

Labels are ordinary point ROIs, stored with the series by the database as in Horos. In
addition SekhVet keeps the 3D positions per study in the folder `SPINE` of the data folder;
this is what lets other series show the level.

### 5.6 Norberg angle (Vet Tools › Norberg Angle (Hip Dysplasia) — Place / Reset)

Hip dysplasia assessment on the VD pelvis (extended view). The **Norberg Angle** toolbar button
is a **toggle**: pressed means the measurement is on the image. One click places two femoral
head circles (R blue, L red) and two points for the cranial acetabular rim in the frontmost 2D
window; a second click removes the measurement again (**⌘Z** brings it back). The button follows
the image: scroll to a view that has a measurement and it is pressed.

- **Move a circle:** grab it at the centre and drag (large hit zone).
- **Change the radius:** drag the yellow grip outside the circle, or use the **mouse wheel**
  over the circle (locked circles ignore the wheel).
- **Acetabular rim:** drag the point onto the cranial acetabular edge.
- The angle is drawn live (arm, arc, value at 10 o'clock for R, 2 o'clock for L) and stored in
  the point's name ("Norberg R: 104.3°"). It stays in the database and returns the next time
  the study is opened.
- **Reset:** **Vet Tools › Norberg Angle (Hip Dysplasia) — Place / Reset** places the
  measurement afresh in the centre of the window. **Delete Norberg Measurement** in the same
  menu removes it. Placing, reset and delete can be undone with ⌘Z. Deleting a femoral head
  circle by hand removes the rest of the measurement with it.
- Screen left = patient right (VD convention). Flipping the image does not change the
  assignment. If the device shows the pelvis mirrored, **Vet Tools › Hip Measurement: Exchange
  Sides R ↔ L** swaps the labels; geometry and values stay.

The angle measured is the inner angle between the line connecting the two centres and the
line centre → acetabular rim, in millimetres via the image's pixel spacing, rounded to 0.1°.
A rim point placed caudally instead of cranially yields the same inner angle; the point belongs
on the cranial rim. **Not included:** Flückiger score and automatic hip grade. Grading
according to FCI or another scheme is done by the veterinarian.

### 5.7 Distraction index (Vet Tools › Distraction Index (PennHIP) — Place / Reset)

Laxity measurement on the **distraction view** using the PennHIP formula. Like the Norberg
button, the **Distraction Index** toolbar button is a toggle (pressed = measurement on the
image, second click removes it, ⌘Z brings it back). It places two circles per hip: the femoral
head circle (R blue, L red, shared with the Norberg angle) and a yellow circle for the
acetabulum.

- **Femoral head circle:** fit it to the femoral head; radius via the yellow grip outside or the
  mouse wheel.
- **Acetabular circle:** fit it to the acetabulum; grip on the inner side, mouse wheel over the
  circle. Where the two circles overlap, the one whose centre is nearer to the pointer responds.
- **DI** = distance between the two centres divided by the femoral head radius. A red line joins
  the centres; the value is shown below the femoral head ("DI 0.65") and stored in the name of
  the acetabular circle.
- **Show DI Risk Level** (checkmark in the Vet Tools menu) adds the level to the label, based
  on the displayed, rounded number: < 0.30 low · 0.30–0.70 moderate · > 0.70 high. These are
  practice cut-offs; the breed-related interpretation according to PennHIP remains a matter of
  judgement.
- **Vet Tools › Distraction Index (PennHIP) — Place / Reset** places the measurement afresh,
  **Delete Distraction Index** removes the acetabular circles; both can be undone.
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
registered as "emergency" ends up under the right animal. Open viewers are closed first. Per
study it is **all or nothing**: SekhVet makes a backup copy of the files before writing, and the
database is changed only after every file has been written; if one fails, the backup is
restored. Refused are linked studies, studies from remote databases, names with characters the
files' character set cannot hold, missing files and insufficient free space (the message says
why). A PACS that already holds the study keeps the old name.

### 5.10 Double MPR

Two MPR windows of the same study (e.g. native and contrast) stay in sync: crosshair point,
plane position, slab thickness, rotation/flip and the zoom per view (sagittal ↔ sagittal
etc.). Requires the same study and the same Frame of Reference.

- **MPR-Sync** switch in the MPR toolbar (on by default).
- **WL/WW** switch in the MPR toolbar (after Zoom, off by default): on = window level/width
  follows between all MPR windows of the same modality — by mouse, key or the WL/WW menu; also
  between two examinations (prior and follow-up). When switched on, the window you click in
  gives the window level; a newly opened MPR adopts it. Off = every window keeps its own window
  level (e.g. bone kernel next to soft-tissue kernel). The same switch is in **Vet Tools ›
  Display** (5.14).
- **View sizes** (Vet Tools › Display, off by default): on = dragging a divider between the views of
  one MPR window gives the other MPR windows the same split – as a proportion, so it also fits
  windows of different size. When switched on, the front MPR window gives the split; a newly opened
  one adopts it. The double-click zoom of a single view stays in its own window.
- New MPR windows open above their 2D series and are tiled inside the viewer area; they remain
  freely movable.
- A second MPR adopts the position of the first when it opens.
- **Double-click a view** to enlarge it to the whole window; a second double-click restores the
  three views. The other MPR window is not affected.
- **One click** into a 2D series makes it the active series: the MPR button then builds the MPR
  from this series (no second click or scroll needed).
- **Swap sides:** **⌘H** or the **Swap** toolbar button lets the two MPR windows change sides,
  together with their 2D series underneath; each MPR ends up over its own series again (5.17).

### 5.11 Further MPR improvements

- **Convolution filter (SekhVet):** popup in the MPR toolbar; Gaussian, Sharpen, Unsharp Mask,
  Highpass on all three planes.
- **Thick Slab** defaults to Mean (Horos: MIP). The mode (MIP/Mean) applies per MPR window, not
  to all open MPRs.
- **No stripes on oblique planes:** Horos samples a thin MPR slab with only one or two samples per
  pixel; with the plane almost, but not exactly, axis-aligned (after rotating in one view only) the
  image breaks up into black rows. SekhVet takes at least four samples per slab thickness. Geometry
  and measurements are unchanged.
- **Movie export shows the whole view:** in Horos a QuickTime movie of an MPR view (3D rotation or
  batch) is often only a strip in the middle, because the co-rotated neighbouring view imposes its
  size; with export size 512 or 768 a square is cut out as well. SekhVet exports crop, zoom and
  rotation exactly as set in the view; 512/768 scale down the whole view (long side) and keep the
  aspect ratio (since build 196). The same applies to DICOM screen-capture export (MPR, CPR) at
  512/768: whole view instead of a square, pixel spacing converted accordingly (since build 197).
- **Zoom** (checkbox in the MPR toolbar): couples the zoom of the three views of one window.
  Off by default; between windows the zoom always follows per view. The button can be removed
  via Customize Toolbar.
- **Right-click without dragging** opens the tool menu in every MPR view, as in the 2D viewer
  (with **3D Rotate** since build 175); dragging with the right button zooms as in Horos. A left
  click next to the menu closes it and at once grabs the crosshair or starts the chosen tool —
  before build 175 the window level jumped there (very dark/very grey).
- **Icons:** the orientation buttons (Axial, Coronal, Sagittal and their opposite) show a
  vertebral CT in a bone window, "3D MPR" a dorsal MR slice with a crosshair, "2D Orthogonal MPR"
  three strips of a stifle CT; the functions are those of Horos.
- **Crosshair hit zones** larger than in Horos (centre 18 px, lines 12 px), adjustable in
  Vet Tools › Display.
- **Quiet cursor:** Horos changes the pointer depending on position; SekhVet keeps the arrow
  (can be switched off in Display).
- CT with a very large value range is clipped to −1024…7168 HU without asking (the Horos
  "High Dynamic Values" dialog is gone).

### 5.12 DICOMweb (Vet Tools › DICOMweb Query (QIDO-RS / WADO-RS)…)

Horos only speaks DIMSE (C-FIND/C-MOVE) and WADO-URI. SekhVet has its own DICOMweb window
that works against Orthanc, dcm4chee and other servers.

1. **Add a node:** **+** creates "New node"; URL up to `/dicom-web` (e.g.
   `http://pacs.local:8042/dicom-web`) and user name. The password is requested on first
   retrieval and stored in the keychain (Basic Auth); if you change the URL or the user, SekhVet
   asks for it again. A node with `http://` (unencrypted), a password and a target outside the
   local network is confirmed once with a warning. Switching the node clears the result list.
2. **Search** by name, ID, date, modality; date popup (default **Today**; Any date, Yesterday,
   **Last 2 days** (yesterday and today), Last 3 days, Last 4 days, Last week, Last month) or
   your own range in the fields "from YYYYMMDD" / "to YYYYMMDD". Results show series, image
   count, time and institution. A ball in front of the name shows whether the study is already
   fully (green) or partially (orange) in the local database, as in the Horos Q/R window.
   Images (instances) are counted as the server counts them: a US cine loop counts as one image,
   not as its frames *(fixed in build 187 — before, a single loop could turn an incomplete US
   study green)*.
3. **Retrieve:** load selected studies or single series via WADO-RS; images go into the
   database. Large studies are streamed, not held in memory in full. If part of the selection
   is already here (green or orange ball), SekhVet asks: **Only missing parts** (skips
   everything green and retrieves only incomplete series), **Download everything again**, or
   Cancel. Alt-click on Retrieve downloads everything without asking.
   **Retrieve stays available while a download is running:** further studies are added to a
   queue (no duplicates; the status line shows "Added to the queue: N — M waiting"). A failed
   retrieve no longer stops the queue; failures are listed at the end. The queue does not
   remember the node: switching the node during a download retrieves the rest from the new one.
   **Stop** next to Retrieve cancels the running retrieve together with the queue.
   **Sorting:** click a column header to sort the studies (date/time newest first on the first
   click, click again to reverse); the choice is remembered.
   Structured reports (dose report, examination report) are imported as their own series and
   open as a rendered page. Report types the database cannot take (e.g. key object selections)
   are marked "report — not in the database" and do not keep a study from turning green.
4. **Send from the database (STOW-RS):** select studies or series in the database window, then
   either press the **Send DICOMweb** toolbar button or right-click and choose **Send via
   DICOMweb ›**; both show the list of your nodes (and "DICOMweb Nodes…" to add one). Sending
   runs in the background, progress is shown in the Activity window where it can be cancelled;
   a notification appears at the end. If the server does not explicitly confirm receipt, the
   result reads "NOT confirmed" — check in the PACS. **Vet Tools › Send Selected Studies via
   STOW-RS…** and the **Send** button in the DICOMweb window do the same.

5. **Filter by institution** *(new in build 167)*: field **Institution (partial; a; b)** in the
   search row — shows only studies whose institution contains the text (upper/lower case and
   accents do not matter; separate several names with ";"). In addition, **each node has its list
   of referring institutions:** **Choose…** reads all institutions of the server (with their number
   of studies; "(none)" = studies without an institution), you tick the ones to show (**All** /
   **None**) and **Save**. The checkbox **Only the N chosen institutions** switches the filter on
   and off (on by default). The list can also be edited by hand in the column **Institutions
   filter (a; b; …)** of the node list below. The filter works in SekhVet,
   not on the server; the status line says how many studies it hid ("… hidden by the institution
   filter"). The server returns at most 300 studies per search, so search with a period.
6. **Automatic refresh (auto Q/R)** *(new in build 167)*: popup **Auto-refresh** (Off, Every
   1 / 3 / 5 / 10 / 15 / 30 min.) repeats the search with the current fields — also while the
   window is closed and after a restart (then with period Today, node and institution as last
   time, name/ID/modality empty). Expanded studies and the selection stay; the status line shows
   the time and new results ("Auto-refresh 14:05, 2 new: …"). Checkbox **Retrieve new studies
   automatically** then retrieves every listed study that is not (completely) here via WADO-RS —
   only with a period set. *From build 187:* SekhVet waits until the image count on the server
   has stood still for about 45 seconds (status line "N still arriving"), then retrieves; if the
   study is still not complete afterwards — broken download, network error, images sent later —
   SekhVet tries again after 3 and after 10 minutes (only the missing series), at most three
   times per image count. New images on the server start the count afresh. The tooltip of the
   ball shows what is pending ("Auto-retrieve failed (try 1 of 3) — next try at 09:06", "… gave
   up after 3 tries — use Retrieve"). **Stop** takes the stopped studies out of the automatic
   retrieve until the server has more images of them; switching auto-retrieve off and on again
   resets all tries.
7. **Compressed transfer** *(new in build 184)*: checkbox **Compressed transfer (JPEG-LS,
   lossless)** right above **Retrieve** (on by default, remembered). SekhVet asks the server to
   pack the images as lossless JPEG-LS before sending: a CT needs about a third of the data
   (measured against Orthanc 1.13: 72 → 27 MB per series), noticeably faster on slow or mobile
   networks. Pixel values stay bit-identical. Applies only to studies or series made of CT, MR,
   DX, CR, MG, PX, IO (plus SR/KO/PR); **ultrasound**, angiography or an unknown modality always
   come uncompressed — the server would have to unpack cine loops completely in its memory, which
   can crash it. If the server cannot compress (error answer or broken stream), SekhVet retrieves
   the same job once uncompressed; the status line says so. Automatic retrieve (6) follows the
   checkbox as well.

Toolbar buttons **DICOMweb** (query) and **Send DICOMweb** in the database next to "Query".
The classic Horos Locations (DIMSE) remain fully usable.

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
- **Workplaces — several monitors** *(new in build 188)*: the viewer area belongs to the
  **combination of connected monitors**. Example 2 × 27": monitor 1 whole, on monitor 2 only the
  left half, the right half stays free for the report (ReportPilot, Pages). On the laptop alone
  or at the 49-inch monitor the areas chosen there apply again. SekhVet recognises monitors by
  vendor, model and serial number, not by the order macOS lists them in; two identical monitors
  without a serial number are told apart by their place (left/right). Per workplace SekhVet
  also remembers **Screens used for viewers** (Preferences › Viewers) and where the database
  window stands. When monitors are connected or disconnected, SekhVet switches by itself and
  retiles open viewers.
  - New combination of monitors: at first every monitor uses its whole area. SekhVet asks once
    whether to set it up (**Set Up Screens…** opens this window).
  - The window lists the monitors by name and place ("2 · DELL U2723QE (right)"), with the
    recognised workplace above them.
  - **Identify Screens** shows number, name and viewer area on every monitor for a few seconds;
    the area is tinted blue.
  - **Use Front Viewer's Place** (also in the **Screen** popup as **Use This Window's Place**):
    drag and size a viewer window to where viewers should go, then click. Close to a half or a
    third, SekhVet snaps to it; otherwise the exact rectangle applies.
  - After the update the first workplace takes over the areas chosen before.
- **Annotations:** font, size (default Helvetica Bold 14; "Classic (1 px shadow)" and
  "classic: Geneva 12" restore the Horos look), text colour (default white, "ROI color
  (classic)" = each measurement in its own colour), outline/box for measurement text, corner
  text and the values of the hip measurements: a popup with the Horos original, **Outline**
  (outline only, the **default**), "Semi-transparent box" and "Outline and box"; box colour and
  opacity stay adjustable. Changes take effect immediately. Text in the image is drawn in full
  colour and opacity on every display.
- **Measurements:** checkbox **Measurement navigator: thumbnails of the images with measurements**
  (measurement navigator, 5.24), checkbox **Magnified view in a corner while measuring** (measuring magnifier,
  5.21), popup **Magnifier size (of the shorter side)** 25–75 % (default 55 %) and **Line width
  (px)** separately for lines, areas and arrows (1–10) with an **Apply to open** button.
- **Overlay:** the keys for the next and the previous series in an overlay (5.20); default `<`
  and `y`.
- **Corner information (Preferences › Annotations):** the default layout shows top
  left image size, WL/WW and mouse position; top centre orientation and patient orientation;
  top right patient ID, study and series description; bottom right MR data, acquisition date
  and acquisition duration. **CT** has its own entry that shows kVp, mA and mAs at the bottom left;
  CBCT studies are stored as modality CT and get the same. A layout you saved yourself is kept.
- **Appearance:** System / Light / Dark, default Dark.
- **Modality colours:** study and series rows in the database tinted by modality (CT blue, MR
  violet, radiographs green, US orange …). Can be switched off.
- **Magnetic windows:** off by default; windows stay freely movable.
- **MPR:** hit zones, static cursor, MPR sync, tiling, zoom sync, WL/WW sync, view sizes.
- The display rows (Screen Area) follow newly connected displays automatically; the values
  belong to the current workplace (see above).

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
and show the same scale-like depth scale on the right edge (checked by comparing the scale
strips). The measurement text carries the note "US calibration from image N" (for multi-frame
files "image N, frame M") so the origin stays visible. Cine loops are never used as a source.
**Enabled by default for Mindray devices only**, the one manufacturer tested so far (Vetus 9).
For other manufacturers the fallback can be enabled in Terminal, e.g. for Esaote:
```
defaults write vet.kappa1.sekhvet.horos SekhmetUSCalibrationFallbackVendors -array Mindray Esaote
```
and switched off completely with
```
defaults write vet.kappa1.sekhvet.horos SekhmetUSCalibrationFallback -bool NO
```
If a borrowed calibration is wrong for your device, switch it off and report the device model.

### 5.17 Swap / rotate windows (⌘H)

**⌘H**, the **Swap** toolbar button (in the 2D viewer next to Point and in the MPR window next
to Zoom sync and WL/WW) or **Vet Tools › Swap / Rotate Windows** rearranges the open windows:

| Open | Result |
|---|---|
| two MPR windows | they change sides together with their 2D series; each MPR sits over its own series again |
| three or more MPR windows | every MPR moves one place on, together with its series |
| no or one MPR, two 2D series | the two 2D windows change places |
| no or one MPR, three or more 2D series | every window moves one place to the right, the last one comes to the front: `[A][B][C]` → `[C][A][B]` |

Places are counted per display from left to right, then row by row from the top. The active
window stays active; window/level, crosshair and spine labels are not affected. Series spread
over several displays can move to another display. **⌘H no longer hides SekhVet;** "Hide
SekhVet" stays in the SekhVet menu without a shortcut, ⌥⌘H (Hide Others) is unchanged. To use a
different key: System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts, menu title
"Swap / Rotate Windows (MPR with their 2D series, else 2D series)".

### 5.18 Import from other databases (Preferences › Database › Import from Other Databases… or Vet Tools)

For switching from Horos, OsiriX, HorliX or Miele-LXIV: the studies of another database are
copied into the SekhVet database. In the database toolbar the button is called **Import
Databases** (Horos: "Migration Assistant").

- **Found automatically:** every folder in `~/Documents` that contains a `DATABASE.noindex`
  (e.g. "OsiriX Data", "Horos Data") and the custom database locations from the OsiriX and
  Horos settings. For a database elsewhere (external disk) use **Choose Folder…**.
- **Import** copies all images of the selected database; progress is shown in the Activity
  window and you can keep working. The **source is only read**, never changed.
- Images already in SekhVet are recognised (SOPInstanceUID) and **not duplicated** — importing
  the same database again only adds what is new.
- ROIs stored as DICOM (SR) in the database come along. Albums and reports are **not**
  imported; settings have their own dialog (5.27).
- On the first start after a foreign database is found, SekhVet points this out once.
- Why "SekhVet Data" and not "Horos Data": SekhVet is an independent fork; its own data folder
  leaves the Horos database untouched (and keeps the "Horos" trademark out of SekhVet).

*The idea comes from Hiroaki Inomata (PHORLIX) — many thanks for kindly agreeing to this
independent implementation.*

### 5.19 Searching by description

In the database window the search type **Description** (formerly "Study Description") looks in
the study **and** the series description — "lat", "VD" or "thorax" find the study even when the
projection is only stored in the series. The **all fields** search (three characters or more)
includes the series as well. PACS queries still search at study level only.

### 5.20 Overlay: stacking series ("Overlay" button in the 2D viewer)

View native, contrast and bone kernel **of the same examination in the same window**: slice,
zoom and pan stay put while you switch, as if flipping between transparencies. CT and MR in
greyscale only, 2D viewer only; the series need the same frame of reference (otherwise a
message, no overlay). At most four series; every added series is resampled onto the grid of the
series in the window (trilinear, about 0.4 GB of memory per CT series).

- **"Overlay" button** in the viewer toolbar (next to "Swap") finds the matching series by
  itself: same modality, at least ten images, no localizer, same region, for MR the same plane.
  Only series covering at least half of the slices of the series in the window are suggested.
  Order per kernel (soft tissue, bone, lung): Native · Arterial · Venous · Contrast · Delayed,
  e.g. "Native · Arterial · Venous" or "Native · Contrast · Native bone · Contrast bone". Series
  named "KM", "contrast", "post", "T1+C" … and *since 1.1* "arterial", "venous", "portal",
  "delayed" (also the German words) count as contrast; without such a word the DICOM field
  *Contrast/Bolus Agent* decides. "pre KM", "vor KM", "ohne KM", "without / non contrast",
  "plain" count as native. Afterwards the toolbar shows **chips**, one per series, **▾** (selection) and
  **✕** (end).
- **If the button finds nothing**, it stays pressed and waits: the next series you drag from the
  series bar onto the image is overlaid (a message says so; a second click switches the button
  off again).
- **Dragging a series onto the image** no longer asks: overlay off → the series is shown as in
  Horos; overlay on → the series is added; if it is already in the overlay → it is just shown.
  Clicking a thumbnail always shows the series normally and ends the overlay.
- **▾ selection** *(redesigned in 1.1)*: at the top there is a **one-click line** per kernel,
  e.g. "Soft tissue: Native · Arterial · Venous" — it shows exactly these series. Below are all
  series of the examination, grouped as **Soft tissue / Bone / Lung**, with a checkmark each. The
  series you started from carries "(base series)" and cannot be deselected. A series that covers
  only part of it shows "· covers 37 %". Deselected series get no chip and are skipped (they stay
  loaded). If four series are already loaded, ticking another one rebuilds the overlay without
  the deselected ones. For CT SekhVet remembers the deselected **kind** (e.g. "Contrast bone")
  and does not load it at all for the next overlay; it can be ticked again in the menu.
  Deselecting a series that covers only part is not remembered.
- **Series without images at this position** *(new in 1.1)*: if the visible series does not
  reach the current slice (e.g. a contrast thorax next to a native whole-body CT), the image shows
  "Contrast: no images at this level" at the top instead of an empty grey area.
- **Keys:** `<` next series, `y` previous (adjustable in Vet Tools › Display, row "Overlay").
  They only work while an overlay is running and the image has the focus. In Horos `y` is the
  crosshair tool of the orthogonal MPR; during an overlay it switches the series.
- **Window/level per series** is remembered: the bone series stays in the bone window, the soft
  tissue series in the soft tissue window, also in the MPR.
- **Measurements are shared:** a length or an oval sits in all series of the overlay at the same
  place; it is stored with the series you started the overlay from only. Earlier measurements of
  the other series are hidden meanwhile (chip "(n hidden)") and stay stored.
- **Area ROIs (oval, rectangle, polygon, pencil):** mean and SD apply to the series currently
  shown. In addition there is the line **"Native 42 · Contrast 168 · Δ +126 HU"** (only between
  series of the same kernel; for MR the enhancement in percent). With several phases each phase
  gets its own Δ against native: **"Native 42 · Arterial 180 (+138) · Venous 150 (+108) HU"**. In the MPR the oval also
  recalculates per series; the Δ line is not available there.
- **Overlay in the MPR:** the MPR toolbar has the same **Overlay** button with chips, **▾** and
  **✕**. An MPR opened from the overlay window contains all series; `<`, `y` and the chips switch
  MPR and 2D together. If you start the overlay in the MPR, add a series via **▾** or end it with
  **✕**, SekhVet briefly closes the MPR, changes the overlay in the 2D window and reopens the MPR
  in the same place: same planes, same zoom, same window position, same visible series. Depending
  on the series this takes a few seconds. **It is quicker to start the overlay in the 2D window
  and open the MPR afterwards.** A minimised MPR or an open volume rendering of the same series
  still blocks it (message).
- During an overlay Revert, LUT, SUV and DICOM overlays are not available ("post processed"), the
  4D slider and Play are greyed out. A reference series with mixed image sizes or non-parallel
  slices is refused.
- Limits: at most four series at a time; the phase comes from the series name or the field
  *Contrast/Bolus Agent* only, not from bolus tracking or time stamps.

### 5.21 Magnifier (measuring magnifier and free magnifier)

- **Measuring magnifier:** while dragging a **length measurement** (also when dragging an end
  point afterwards) a magnified view appears in the corner farthest from the pointer; the corner
  stays fixed during the measurement. Length only, not oval & co. Can be switched off under
  Vet Tools › Display › Measurements, checkbox "Magnified view in a corner while measuring".
- **Free magnifier:** hold **Shift**; the view follows next to the pointer and the real pointer
  stays visible in the image. Also works with a measurement tool active, unless the pointer is
  on a measurement.
- **Zoom** with `+`/`−`, `→`/`←` or the scroll wheel (1.5× to 12×, default 3×); **size** with
  `↑`/`↓` or the popup "Magnifier size (of the shorter side)", 25–75 %, default 55 %.
- Works in the 2D viewer and in the MPR views (there without the crosshair inside the magnifier).

### 5.22 Fusion and subtraction (Horos feature, repaired in SekhVet)

When you drag the image of one viewer onto another, Horos offers **Subtraction** and
**Multiply**. SekhVet combines each target slice with the mask slice **at the same location**
(same frame of reference or the same examination), no longer with the slice of the same number;
target slices outside the mask are blanked. No window sync is needed and the window order does
not matter. **Ctrl** while choosing combines image by image by number, **Option** gives the
absolute difference. If both series come from examinations without shared coordinates, slices
are matched by number if the counts are equal, otherwise proportionally.

### 5.23 Free rotation ("Rotate" tool)

With the **Rotate** tool (also ⌘⌥-drag) the image follows the mouse around the centre of the
view. Close to the centre the rotation is damped so that small mouse movements give small
angles; further out the image turns exactly with the mouse. Works in the 2D viewer, the 3D MPR
and the curved MPR; in the MPR every view turns around its own centre. A double-click with the
tool turns by 90° (with Shift) or 180° (with Option); the arrow keys turn in 3° steps.

### 5.24 Measurement navigator ("Measurements" button in the 2D viewer) *(new in build 167)*

As soon as a series has measurements (ROIs), a bar at the bottom of the image shows one
thumbnail per image with a measurement — window level, rotation and flip as in the viewer, the
measurements in their colour. Below each is the image number (as in the image corner) and, with
several measurements, their count; the tooltip lists their names. The image on screen has a
yellow frame.

- **Click** a thumbnail to go to that image; synchronised viewers follow as when scrolling.
- The **trash can** at the right of the bar (or the toolbar button **Delete All**) deletes all
  measurements of the series after asking (the toolbar button those of the viewer clicked last; the
  question names the series); locked ones stay, **⌘Z** brings everything back (same
  as Horos' ROI › Delete All ROIs).
- **x** at the left hides the navigator. To show it again: toolbar button **Measurements** or
  Vet Tools › Display, checkbox **Measurement navigator: thumbnails of the images with
  measurements** (on by default).

The bar lies over the image; the image does not move. Up to 400 images with measurements are
shown; when there are more than fit, the bar scrolls sideways.

### 5.25 Study databases (File › New Database Folder…) *(new in build 175)*

A study or case collection can have its own database, e.g. on an external SSD — the working
database stays free of it.

- **Create:** File › **New Database Folder…**, choose a folder (e.g. `/Volumes/SSD/Study-CT`).
  SekhVet creates `SekhVet Data` in it; the database appears on the left under **Sources**.
- **Switch:** click its entry under Sources; the window title names the database shown.
- **Fill:** with the study database shown, drag files/folders into the window or use File › Import.
  To keep the images on the SSD, leave copying into the database folder on (Preferences ›
  Database). Vet Tools › Import Image / PDF as DICOM also writes into the database shown.
- **Eject** *(new in build 179)*: study databases on an external disk have a ⏏ on the right under
  Sources. A click shows the main database again, closes its viewers, lets go of the study database
  and ejects the disk — no need to quit SekhVet. While an import into the disk is running, SekhVet
  says so and does not eject. If the disk is not connected, clicking the entry says exactly that.
- **Reopen:** File › **Open Database Folder…**; an SSD with `SekhVet Data` at its top level appears
  under Sources by itself when plugged in.
- **Incoming stays in the main database:** everything from a PACS (DICOM listener,
  query/retrieve, DICOMweb including auto-retrieve) always goes to the main database, also while a
  study database is shown. Switch: Preferences › Listener, **Incoming and shared files are always
  linked to the default database** (on by default since build 175).

- **Red entry under Sources:** the disk is not connected — not broken. After plugging it in the
  entry is normal again.
- **Remove an entry:** Preferences › Locations, box "Local – SekhVet Databases files / folder",
  select the row, **⌫**. This only removes the reference; the data stay on the disk and can be
  added again via "Add a local path".
- **Rename an entry:** in the same list double-click the **Description** column — **not "Local
  Path"**. If you overwrite the path, the database is no longer found; then set the path back to
  the real folder.
- **Where measurements go:** measurements (ROIs), reports and 3D states are stored in the
  database the study was opened from. Measuring studies on the external disk writes to that disk —
  so include it in your backup.
- **Which disk:** in a test with about 31,600 images the import took 3 minutes onto an external
  SSD (APFS), 16 minutes onto a USB stick (APFS) and about 2 hours onto a USB hard disk (exFAT). For
  working databases use an SSD with APFS; no network drive, no sync folder.

Do not put a database into a Dropbox/iCloud folder: syncing does not go together with a running
database.

**In one step from a folder** *(new in build 176)*: Vet Tools › **New Study Database from
Folder…** — first choose the folder with the studies (it is only read), then place and name of the
study database (e.g. on the external disk). SekhVet creates the database, shows it under Sources,
copies every image into it once (duplicate images in the source only once) and at the end checks
each image of the source by its SOPInstanceUID. The result ("COMPLETE" or the list of missing
images) appears in a message and in the report `Import report <date>.txt` next to the database.
Run again into the same folder, it only adds what is missing.
On external disks the database runs in WAL mode (build 177, much faster indexing). Images are copied
without extended attributes (e.g. from Dropbox) (build 178). Since build 178 the activity list shows
the time left, a notification comes at the end and the result appears on the database window
without halting SekhVet; the report sums up duplicate images per pair of folders.
Note: on exFAT macOS puts a hidden `._` file next to every new file — for study databases an
APFS-formatted disk is faster and, thanks to its journal, more robust.

**The Mac stays awake:** while SekhVet imports files or copies studies into another database, the
Mac does not go to sleep (the display may turn off). A closed Mac laptop only stays awake with an
external display and power.

### 5.26 Back up, export and share vet settings across a practice (Vet Tools › Vet Settings) *(new in 1.1)*

So that an update does not lose your setup and several computers of a practice are set up alike.
The settings come in groups you tick one by one: **Opening protocols**, **Hanging protocols &
orientation**, **Window rules & WL/WW presets**, **Display & annotations**, **Overlay & keys**,
**Measurement tools** and **Network targets** (DICOM and DICOMweb nodes). Network targets must be
ticked on purpose when settings are taken over.

**Never included:** passwords (they stay in the keychain), routing rules, the DICOM listener, Bonjour,
database sharing, the web portal, plugins, database locations, screen areas and window positions.
Unknown entries in a file are dropped.

- **Backup:** on the first start of every new SekhVet version and before every take-over SekhVet backs
  up all groups (`~/Library/Application Support/SekhVet/Settings Backups`, the newest 20 stay).
  **Restore Settings Backup…** brings an earlier state back.
- **Export / Import:** **Export Vet Settings…** writes the ticked groups to a file (`.sekhvet-settings`),
  e.g. for a new Mac. **Import Vet Settings…** shows per group what would change ("3 → 9 entries, new:
  CT spine …"). Every ticked group replaces your own one as a whole.
- **Practice settings folder:** under **Practice Settings Folder…** every computer chooses a shared
  folder once, e.g. on the practice's NAS. Whoever may change the practice settings needs write access
  there — the folder decides, not SekhVet. **Publish Practice Settings…** puts the ticked groups of this
  computer there (the previous version is kept next to it). The other computers look at start and
  whenever SekhVet comes to the front, show the changes and ask **Apply / Later / Reject**. By default
  they always ask; "apply without asking" can be switched on per computer (never for network targets).
  No network port is opened and no service is announced.
- **New defaults on updates:** if a new version brings new built-in settings for a group you have
  changed yourself, SekhVet asks once: **Replace / Not Now / View…**. Replacing makes a backup first.
- Some changes (hanging protocols, keys, toolbars) take full effect after SekhVet is restarted.

### 5.27 Import settings from Horos / OsiriX (File › Import or Vet Tools) *(new in 1.1.2)*

For switching on a Mac where Horos or OsiriX is already set up: the dialog
**Import Settings from Horos / OsiriX…** reads their settings and adds them to SekhVet. At the
first start it opens by itself when SekhVet has no DICOM node of its own yet and a source is
found; later it is always available via **File › Import** or **Vet Tools**.

- **Sources:** Horos (`org.horosproject.horos`, older builds `com.horosproject.horos`), OsiriX and
  OsiriX Lite. Several hits are listed under **Source**, the most recently changed one first.
- **Groups** (all checked by default): DICOM nodes · listener (AE title, port) · hotkeys ·
  window / CLUT / opacity presets · display (ROI colours, annotations, hanging protocols, default
  tool) · query/retrieve settings. The database location and "Horos Data" are never touched;
  studies are copied by 5.18.
- **Add, do not replace:** whatever you have already set in SekhVet stays. Only what is missing
  is filled in; lists are merged (nodes equal by AE + address + port, keys per function, presets
  per name). The checkbox **Overwrite existing SekhVet settings** (off by default) turns this
  around.
- **DICOM nodes:** every node of the source is contacted in the background (TCP, 3 s, then
  C-ECHO) and the result appears in the **Check** column: *echo OK*, *port open, echo rejected*
  or *no answer*. Dead nodes stay checked; you can uncheck them.
- **Listener — the question that decides whether both can run side by side:**
  - **New AE title and port:** SekhVet gets its own AE title (suggested: the Horos title plus
    "SV", at most 16 characters) and its own port (suggested: Horos port + 1). Horos or OsiriX can
    keep running. **Your PACS does not know the new AE title:** register this Mac with the new
    title and port there as a second destination, otherwise retrieve (C-MOVE) fails although the
    query works.
  - **Same as the source:** AE title and port are taken 1:1 from Horos/OsiriX, the PACS needs no
    change — but Horos/OsiriX and SekhVet must **never run at the same time**; the second one
    cannot open the port.
  - This answer takes precedence over the add-only rule. **The listener values take effect only
    after SekhVet is restarted:** the message after the import offers "Quit and reopen SekhVet"
    (SekhVet opens again by itself); with "Later" the old port stays open until you quit SekhVet.
    Check: Preferences › Listener. If Horos has no AE title of its own (it then uses the computer
    name), SekhVet takes the computer name as well with "Same as the source".
- **Backup:** before writing, SekhVet saves its previous settings as
  `~/Library/Application Support/SekhVet/prefs-vor-import-<date>.plist`; the path is shown in the
  message after the import. To go back, quit SekhVet and run
  `defaults import vet.kappa1.sekhvet.horos <file>` in Terminal. If the backup cannot be written,
  nothing is imported.
- Without a source the dialog says "Nothing to take over". The first-start dialog appears once;
  via the menu it is always available.

## 6. Behaviour that differs from Horos

| Topic | Horos | SekhVet |
|---|---|---|
| Orientation letters | A/P, S/I | Cr/Cd, D/V (switchable) |
| Hanging | rows/columns per modality | presets with orientation rules, keywords, DX rules, opening protocols |
| Making a window active | right-click/scroll wheel | left-click as well |
| Measurement text | Geneva 12 in ROI colour | Helvetica Bold 14, white with outline (adjustable, 5.14) |
| ROI values in the MPR | keep their value when the slice changes | recalculate with every new slice |
| Dragging a series onto the image | replaces the series | the same; during an overlay it is stacked (5.20) |
| Key `y` | crosshair in the orthogonal MPR | the same; during an overlay previous series |
| Holding Shift | — | free magnifier, also with a measurement tool (5.21) |
| Rotate tool | jumps near the image centre | damped, follows the mouse (5.23) |
| Subtraction | slice of the same number | slice at the same location (5.22) |
| DICOM listener | on, port 11112 | off by default; enable under Preferences › Listener (section 3) |
| Appearance | follows system | Dark by default, switchable |
| Propagate settings | re-enabled by protocols | stays off until you switch it on |
| Magnetic windows | on | off |
| Thick slab | MIP | Mean |
| Thin MPR slab, plane almost axis-aligned | black stripes possible | at least 4 samples per slab, no stripes |
| Exporting an MPR movie / DICOM screen capture | often only a strip or a centred square | whole view as set |
| Opening a series | slider with one tick per image (slow on large series) | no ticks, noticeably faster |
| Update check | hourly against the Horos server | optional, once a day against GitHub; notice only |
| Horos Cloud | plugin | removed |
| Data folder | Horos Data | SekhVet Data |
| Help menu | Horos help, forums | only "Report a bug" |
| ⌘H | hides the program | swaps / rotates windows (5.17) |

All SekhVet windows open inside the viewer area. All SekhVet toolbar buttons can be moved or
removed via **Customize Toolbar**; new buttons appear once automatically, and stay away if you
remove them.

## 7. Status of 1.1.2, limitations and known restrictions (build 197)

**New in 1.1.2, tested on few devices so far:**

- **Import settings from Horos / OsiriX** (5.27): tested on one clinic computer with Horos 4
  (three DICOM nodes, 41 hotkeys) and on a freshly installed SekhVet (October 2026). The database
  import (5.18) now also finds Horos installations that keep their settings under
  `org.horosproject.horos` (Horos 3 and 4).
- **Double MPR: view sizes in sync** (5.10, Vet Tools › Display, off by default): tested on one
  device (October 2026).
- **MPR improvements** (5.11): no stripes on oblique thin slabs, measurements in HU again, film and
  DICOM screen-capture export show the whole view — tested on CT studies of one device (October 2026).

**New in 1.1, tested on few devices so far:**

- **Study databases** (5.25) with WAL mode and eject: tested on one device with an external SSD,
  a USB stick and a USB hard disk (October 2026).
- **Overlay with several contrast phases** and the new selection (5.20) as well as the phase
  detection of the opening protocols (5.3): tested on CT studies from Siemens and Canon (October
  2026).
- **Backing up, exporting and sharing vet settings** (5.26): tested on one computer (October 2026).
- **Compressed transfer via DICOMweb** (5.12, item 7): tested against Orthanc 1.13 (October 2026);
  other servers may refuse to transcode — SekhVet then retrieves uncompressed.
- **Workplaces — several monitors** (5.14): checked with simulated monitor combinations, not yet
  at two real monitors (October 2026).

**New in 1.0, tested on few devices so far.** These functions run in one practice but are
young. Use them with a critical eye and report what you see:

- **Overlay** (5.20): in use on CT and MR of one device since late September 2026.
- **Subtraction by location** (5.22): checked on CT and MR (October 2026).
- **Measurement navigator** (5.24) and the **institution filter and automatic refresh** in
  DICOMweb (5.12): tested on one device since October 2026.
- **Ultrasound calibration from a neighbouring image** (5.16): one device tested, hence enabled
  for Mindray only by default.
- **Update check** (section 3): the check against GitHub can only be judged in daily use with
  the next release.
- **macOS 27:** tested in a test installation, including double MPR with a large CT and the
  double-click zoom; daily use is on macOS 26.

**In daily use:** orientation letters, hanging protocol in 2D and MPR (also curved and
orthogonal), opening protocols including two-view radiographs, window presets, spine labeling,
Norberg angle, distraction index, point tool, double MPR, convolution filters, magnifier, free
rotation, DICOMweb query, retrieve (with queue) and send, image and PDF import, rename patient,
import from other databases, display settings including CT corner information, feedback and
contribution windows.

**General limitations:**

- **Not a certified medical device** (see above). No formal validation of measurements.
  Veterinary devices fall outside EU Regulation 2017/745 and the Swiss MepV, which apply to
  devices for human use. There is no certification scheme for veterinary imaging software in
  either jurisdiction.
- **Apple Silicon only**, macOS 12 or later; tested in practice on macOS 26 and 27.
- **Receiving is off by default:** the DICOM listener has to be enabled once (section 3).
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
- **Language:** English UI under every system language. The outdated Japanese resources inherited from Horos were removed in build 107; they shadowed the maintained English files on Japanese systems (broken toolbars).
- **No automatic installation of updates**; SekhVet can check GitHub once a day and tell you about a new release, you download the DMG and install it yourself.

## 8. Licence, source code, contribution

SekhVet is free software under the GNU Lesser General Public License 3.0 and is based on
Horos (Horos Project) and OsiriX (Pixmeo SARL). The complete source code of this version,
including all changes to Horos, is at https://github.com/3v3nFloW/sekhvet (also behind
"Source code" in the About window).

If SekhVet is useful to you, a voluntary contribution helps keep development going:
**Vet Tools › Contribute to SekhVet…** The amount is free to choose; there is no service or
extra feature in return.

© 2026 Kappa1-VRS GmbH, Zurich. Horos and OsiriX are trademarks of their respective owners.
