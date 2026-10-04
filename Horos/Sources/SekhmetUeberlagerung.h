/*=========================================================================
 SekhVet Paket CJ — Ueberlagern: mehrere Serien derselben Untersuchung in
 EINEM Fenster, eine Taste schaltet, Schicht und Zoom bleiben.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Nachbau von ImagoPilot (core-viewer/src/dicom/ueberlagerung.ts, 17.09.2026),
 Praemissen aus der Klaerungsrunde vom 29.09.2026 (Entscheid des Eigentuemers):
 - Stapel per Knopf "Overlay" (Vorschlag: gleiche Untersuchung + Modalitaet,
   >= 10 Bilder, kein Topogramm, gleiche Region, MRT gleiche Ebene; Rang
   Nativ, KM, Nativ Kn, KM Kn; hoechstens 4) oder von Hand (Serie aus der
   Leiste aufs Fenster ziehen). Paket CK: ohne Rueckfrage — ist der Knopf
   an (gestapelt, oder ohne Vorschlag gedrueckt = "bereit"), wird die
   gezogene Serie ueberlagert; ist er aus, zeigt Horos sie wie immer.
 - Unterbau ist Horos' 4D: jede weitere Serie wird auf das Gitter der
   Bezugsserie (die beim Stapeln im Fenster lag) neu abgetastet und als
   Movie-Eintrag angehaengt. Anderer FrameOfReference = kein Stapel.
 - Die Messungen sind geteilt (roiList[m] ist DIESELBE Liste wie roiList[0])
   und werden nur an der Bezugsserie gespeichert — die neu abgetasteten
   Bilder sind "generated", Horos' saveROI: ueberspringt sie von selbst.
 - Flaechen-ROIs bekommen eine Zeile "Native 42 · Contrast 168 · Δ +126 HU"
   (MRT: prozentuales Enhancement), nur Serien desselben Kerns.
 - Tasten "<" (naechste) und "y" (vorige; bis Build 140 ">"), umstellbar in
   Vet Tools > Display; das Fenster wird je Serie gemerkt (auch im MPR).
 - Paket CN: Segment "▾" waehlt, welche Serien mitlaufen; abgewaehlte
   CT-Raenge merkt sich SekhVet (SekhmetOverlayDeselected).
 - Paket CS (review before 1.0): while stacked the viewer is "postprocessed"
   (Horos' Revert would replace the overlaid pixels by the reference's) and
   Horos' 4D slider/Play are off; switches by Horos' own 4D paths (arrow
   up/down, Option + wheel, series list) get the per-series window and ROI
   values too. The reference must be one regular greyscale CT/MR block
   (same size, spacing, direction in every slice). Minimised 3D windows
   block ending the overlay. Chips show "(N hidden)" for measurements saved
   with an overlaid series (they are not shown while overlaid).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"
#import "ViewerController.h"

@class ROI, DCMView, DCMPix, DicomSeries;

extern NSString* const SekhmetOverlayToolbarItemIdentifier;  // "SekhmetOverlay"
extern NSString* const SekhmetOverlayKeyNextKey;             // Taste "naechste Serie" (Vorgabe "<")
extern NSString* const SekhmetOverlayKeyPrevKey;             // Taste "vorige Serie" (Vorgabe "y")

@interface SekhmetUeberlagerung : NSObject

// Regeln (aus ImagoPilot; SekhVet Paket CS: die Phasenregel steht in SekhmetSequenz +ctPhaseFuer: und kennt
// jetzt auch "pre KM", "vor KM", "without contrast" ... als nativ)
+ (int) phaseFuer:(NSString*) beschreibung;                                   // 0 unbekannt, 1 nativ, 2 KM
+ (BOOL) istKnochenkern:(NSString*) kernel beschreibung:(NSString*) beschreibung;
+ (NSArray*) vorschlagAus:(NSArray*) alle aktuell:(NSDictionary*) aktuell;   // Eintraege als Dictionary (uid, desc, kernel, modality, study, count, number, normal)

// Viewer
+ (NSArray*) vorschlagFuerViewer:(ViewerController*) v;                       // DicomSeries in Rangfolge, die angezeigte immer dabei
+ (BOOL) istGestapelt:(ViewerController*) v;
+ (BOOL) staple:(NSArray*) serien inViewer:(ViewerController*) v meldung:(NSString**) meldung;
+ (void) beende:(ViewerController*) v;
+ (void) zeige:(NSInteger) movieIndex inViewer:(ViewerController*) v;
+ (void) schalte:(ViewerController*) v schritt:(int) schritt;
+ (BOOL) handleKeyEvent:(NSEvent*) e inView:(DCMView*) view;                 // DCMView und MPRDCMView
+ (BOOL) handwegFuerSerie:(DicomSeries*) s viewer:(ViewerController*) v;     // YES = SekhVet uebernimmt den Drop
+ (int) handwegEntscheidFuerSerie:(DicomSeries*) s viewer:(ViewerController*) v; // 0 Horos zeigt, 1 ueberlagern, 2 Stapelserie anzeigen
+ (BOOL) istBereit:(ViewerController*) v;                                     // Knopf an, noch nichts gestapelt

// ROI-Beschriftung (Haken in -[ROI prepareTextualData:])
+ (void) ergaenzeTextboxVonROI:(ROI*) r;
+ (NSString*) enhancementZeileFuerROI:(ROI*) r;

// Werkzeugleiste
+ (void) konfiguriereToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) v;
+ (void) aktualisiereToolbar:(ViewerController*) v;
// SekhVet Paket CX: Subtraktion/Multiplikation aus Horos' Fusion-Blatt Schicht fuer Schicht nach Ort (nicht ueber die Sync-Nachricht)
+ (NSInteger) partnerVon:(DCMPix*) a in:(NSArray*) maske;   // Index der Maskenschicht am selben Ort, -1 = keine
+ (BOOL) verrechne:(ViewerController*) ziel mit:(ViewerController*) maske art:(int) art absolut:(BOOL) absolut nachIndex:(BOOL) nachIndex; // art 2 Subtraktion, 3 Multiplikation

#if SEKHVET_TESTHAKEN
// Tests (nur ueber Testhaken aufgerufen; SekhVet Paket CS: nur im Testbau vorhanden)
+ (NSString*) debugSelfTest;
+ (void) debugE2E;
+ (void) debugSubtraktionE2E;   // SekhVet Paket CX
+ (void) debugMPROverlayE2E;   // SekhVet Paket DA
#endif // SEKHVET_TESTHAKEN

@end

// Zugriff auf die 4D-Instanzvariablen, die nur eine Kategorie von ViewerController sieht.
@interface ViewerController (SekhVetUeberlagerung)
- (void) sekhmetUeberlagerungTeileROIs:(int) m;      // roiList[m] = roiList[0] (dieselbe Liste)
- (void) sekhmetUeberlagerungEntferneAb:(int) m;     // Movie-Eintraege ab m freigeben, zurueck auf 2D
- (void) sekhmetUeberlagerungSperre4DBedienung;      // SekhVet Paket CS: Horos' 4D slider / Play / rate off while stacked
@end
