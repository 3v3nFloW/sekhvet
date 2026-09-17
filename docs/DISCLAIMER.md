# SekhVet — regulatory status

This is the canonical wording. The same text appears in the first-launch dialog, in the About
window, in the README and on the download page. If it changes here, it changes everywhere, and
the constant `SEKHMET_DISCLAIMER_VERSION` in `Horos/Sources/SekhmetDisplayPanel.m` is raised by
one so the dialog is shown again.

## English

**SekhVet is a veterinary DICOM viewer and is not a certified medical device.**
It is not cleared by the FDA, not CE-marked and has not undergone any formal validation.
It is intended for use in veterinary medicine, research and education only and must not be used
for the diagnosis or treatment of humans.
Measurements and orientation aids are tools; the interpretation of images and the diagnosis
remain the responsibility of the veterinarian. SekhVet is provided "as is", without warranty of
any kind (GNU LGPL v3).

Why there is no certificate, in one sentence for the README and the website:

> Veterinary devices fall outside EU Regulation 2017/745 and the Swiss MepV, which apply to
> devices for human use. There is no certification scheme for veterinary imaging software in
> either jurisdiction.

Short form, one sentence, for a download page:

> SekhVet is free veterinary software, not a certified medical device, and not for human use.
> Diagnosis remains the responsibility of the veterinarian.

## Deutsch

**SekhVet ist ein veterinärmedizinischer DICOM-Viewer und kein zertifiziertes Medizinprodukt.**
Es ist weder FDA-cleared noch CE-gekennzeichnet und hat keine formale Validierung durchlaufen.
Es ist ausschliesslich für Veterinärmedizin, Forschung und Lehre bestimmt und darf nicht für die
Diagnose oder Behandlung von Menschen eingesetzt werden.
Messwerkzeuge und Orientierungshilfen sind Hilfsmittel; Bildinterpretation und Diagnose bleiben
in der Verantwortung der Tierärztin oder des Tierarztes. SekhVet wird ohne Gewährleistung
bereitgestellt (GNU LGPL v3).

## Why this wording, and not a claim of validation

- **Horos** is not FDA-cleared and not CE-certified. Horos describes itself as intended for
  research, education and personal review, not for primary diagnosis. The certified product line
  is OsiriX MD. A fork does not inherit an approval, and SekhVet has never been validated.
- **United States.** Devices used exclusively on animals require neither a 510(k) nor a PMA;
  the FDA operates no approval pathway for veterinary devices. Manufacturers are themselves
  responsible for safety, effectiveness and correct labelling. Claiming an approval that does
  not exist would be misbranding.
- **European Union and Switzerland.** MDR 2017/745 applies to devices for human use. The Swiss
  Federal Council has expressly restricted the scope of the MepV to products for humans; devices
  used only on animals fall under other law instead, notably the Product Safety Act. Neither
  jurisdiction operates a certification scheme for veterinary imaging software, so there is no
  certificate to obtain. The Swiss reading should be confirmed by the company's lawyer before
  wide distribution.
- **Product liability, the point worth watching.** EU Directive 2024/2853 treats software as a
  product but exempts free and open-source software supplied outside a commercial activity. It
  applies from December 2026. A contribution link and a GmbH as publisher can put that exemption
  in question; wording on the label does not change it.
- **What remains** is unfair-competition law against misleading claims, product liability, and
  the warranty disclaimer of the LGPL-3.0. The honest notice is therefore also the best
  protection.

Never use: "validated", "certified", "diagnostic quality", "FDA", "CE".
Always state instead: what it is, what it is for, and who stays responsible.

## Where it appears

| Place | Implementation |
|---|---|
| First launch | `+[SekhmetAbout showDisclaimerIfNeeded]`, called from `AppController applicationDidFinishLaunching`. Buttons "I understand" and "Quit". The default `SekhmetDisclaimerAccepted` stores the accepted text version. |
| About window | First paragraph of the text block in `SekhmetDisplayPanel.m`. |
| Repository | The quoted block at the top of `README.md`. |
| Manuals | Opening block of `docs/Manual-EN.md` and `docs/Anleitung-DE.md`. |
| Download page | Short form above, on kappa1.vet. |

In a test build (`SEKHVET_TESTHAKEN=1`, see `README.md`) the dialog is skipped when the environment
holds `SEKHVET_SKIP_DISCLAIMER` or any variable named `SEKHVET_*_TEST`, so headless test runs never
block on it. A shipped build has no environment switch; the dialog is shown until it has been
accepted once (the accepted text version is stored in the preferences as `SekhmetDisclaimerAccepted`).
