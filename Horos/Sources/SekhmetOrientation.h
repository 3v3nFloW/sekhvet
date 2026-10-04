/*=========================================================================
 Sekhmet — veterinaere Orientierung (ersetzt das vetHP-Plugin)
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Reine Anzeigetransformation (rotation / xFlipped / yFlipped) am DCMView,
 die Originaldaten werden nie angefasst. Fuenf Regeln je Protokoll; die
 Protokolle sind eine Liste (eingebaut: Head / Spine, Hindlimbs, Forelimbs,
 dazu beliebig viele eigene) plus "Off". Die Stichwort-Tabelle waehlt das
 Protokoll beim Oeffnen (laengstes passendes Stichwort), ein Toolbar-Popup je
 Studie ueberstimmt sie; "Automatic (by keywords)" nimmt das zurueck.
 Nach jedem Setzen werden die Randbuchstaben zurueckgelesen; greift die
 Drehung nicht, wird zurueckgesetzt und sichtbar gemeldet (Lehre aus vetHP).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class ViewerController, DCMView, DCMPix, MPRController, CPRController, OrthogonalMPRViewer;

#ifdef __cplusplus
extern "C" {
#endif

extern NSString* const SekhmetVetPresetKey;                 // NSNumber, id des Vorgabe-Protokolls (0 = Off)
extern NSString* const SekhmetVetKeywordsKey;               // Array von {keyword, preset}
extern NSString* const SekhmetDXRulesKey;                   // Array von {match, rotation, xFlipped, yFlipped}
extern NSString* const SekhmetVetPresetDidChangeNotification;
extern NSString* const SekhmetVetProtocolListKey;           // SekhVet Paket BP: Array von {id, name} in Anzeige-Reihenfolge (ohne "Off")

extern NSString* const SekhmetRuleTransversalDorsalUp;      // BOOL: transversal dorsal oben (sonst ventral oben)
extern NSString* const SekhmetRuleSagittalCranialLeft;      // BOOL: sagittal kranial links (sonst kranial/proximal oben)
extern NSString* const SekhmetRuleDorsalCranialUp;          // BOOL: Dorsalebene kranial oben (sonst kranial links)
extern NSString* const SekhmetRuleLeftOnRight;              // BOOL: Patienten-links auf der rechten Bildseite
extern NSString* const SekhmetMPRLayoutsKey;                // SekhVet Paket AX: Preset -> MPR-Anordnung aus "Take from screen"
extern NSString* const SekhmetRuleProximalCaudal;           // BOOL: Gliedmasse, proximal = kaudal (Vorderbein nach vorn gestreckt) -> kaudal oben (SekhVet Paket AF)

enum {
    SekhmetPresetAutomatic = -1, // SekhVet Paket CS: popup entry "Automatic (by keywords)" - never stored, removes the override of a study
    SekhmetPresetOff = 0,
    SekhmetPresetHeadSpine = 1,
    SekhmetPresetHindlimb = 2,   // bis Paket AF "Limbs": kranial/proximal oben
    SekhmetPresetForelimb = 3,   // SekhVet Paket AF: proximal = kaudal -> kaudal oben
    SekhmetPresetLast = 5        // 4 and 5 were the two fixed custom presets up to Paket BP; ids of new protocols start at 6
};

#ifdef __cplusplus
}
#endif

/** Veterinaere Randbuchstaben (Schalter VetOrientationLetters): A->V, P->D, S->Cr, I->Cd;
 *  R/L bleiben. Stand bis Stufe 6c als `extern "C"`-Block in DCMView.h. */
#ifdef __cplusplus
extern "C" {
#endif
NSString* SekhmetVetLetter( NSString* letter);
#ifdef __cplusplus
}
#endif

@interface SekhmetOrientation : NSObject

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues;
// SekhVet Paket BP: die Protokolle sind eine Liste {id, name}; die id ist stabil (1-5 = die frueheren festen Presets, neue ab 6),
// Stichworte, Regeln, MPR-Anordnung und die Wahl je Studie haengen an der id -- Umbenennen und Umsortieren beruehrt sie nicht.
+ (NSArray*) protocolList;                                    // {id, name}, Anzeige-Reihenfolge, ohne "Off"
+ (void) setProtocolList:(NSArray*) list;                     // speichert und meldet SekhmetVetPresetDidChangeNotification
+ (NSString*) nameForPreset:(NSInteger) preset;
+ (BOOL) presetExists:(NSInteger) preset;                     // 0 (Off) gilt als vorhanden
+ (NSInteger) addProtocolNamed:(NSString*) name;              // neue id; Regeln wie Head / Spine
+ (BOOL) canRemovePreset:(NSInteger) preset;                  // die drei eingebauten (1-3) bleiben
+ (void) removeProtocol:(NSInteger) preset;
+ (NSMenu*) presetMenuIncludingOff:(BOOL) off;                // toolbar popups: entries carry the id as tag, first entry "Automatic (by keywords)" (tag SekhmetPresetAutomatic)
+ (NSMenu*) presetMenuIncludingOff:(BOOL) off automatic:(BOOL) automatic;   // SekhVet Paket CS: settings panel passes NO
+ (NSString*) rulesKeyForPreset:(NSInteger) preset;
+ (NSDictionary*) rulesForPreset:(NSInteger) preset;
+ (void) setRules:(NSDictionary*) rules forPreset:(NSInteger) preset;

+ (NSString*) descriptionForViewer:(ViewerController*) v;     // Study- + Serienbeschreibung fuer die Stichworte
+ (NSInteger) presetForStudyUID:(NSString*) uid description:(NSString*) description;
+ (void) setPresetOverride:(NSInteger) preset forStudyUID:(NSString*) uid;   // < 0 (SekhmetPresetAutomatic) = Override entfernen; hoechstens die 500 neuesten bleiben gespeichert

+ (NSString*) applyToViewer:(ViewerController*) v;            // liefert Statustext (Badge) oder nil
+ (NSString*) statusForViewer:(ViewerController*) v;
+ (NSString*) titleForViewer:(ViewerController*) v baseTitle:(NSString*) title;
+ (void) applyToAllViewersOfStudyUID:(NSString*) uid;         // nil = alle offenen 2D-Viewer und 3D-MPR-Fenster
+ (NSString*) applyToMPR:(MPRController*) c;                  // Regeln auf die drei MPR-Ansichten (Kamera um die Blickrichtung drehen + Anzeige spiegeln, Paket AX), liefert Statustext
+ (void) setBadge:(NSString*) status inTitleOfWindow:(NSWindow*) w;   // SekhVet Paket CS: badge of a 3D window (MPR / Curved / Orthogonal); the apply methods below call it themselves
+ (NSString*) stateSignatureForPreset:(NSInteger) preset;     // SekhVet Paket CS: rules + MPR layout of a protocol as text; a remembered MPR state is only valid for the same signature
+ (NSString*) applyToMPR:(MPRController*) c straighten:(BOOL) straighten;  // SekhVet Paket AN: straighten = Ebenen vorher auf die Volumenachsen stellen (Protokollwechsel)
+ (NSString*) applyToCPR:(CPRController*) c;                  // SekhVet Paket CH: dieselben Regeln im Curved MPR (nur Drehen/Spiegeln)
+ (NSString*) applyToOrthogonalMPR:(OrthogonalMPRViewer*) o;  // SekhVet Paket CH: 2D-Regeln auf die drei Ansichten des Orthogonal MPR (Drehen/Spiegeln der Anzeige)
+ (void) configurePresetToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) v target:(id) target;   // SekhVet Paket CH: Popup "Hanging Protocol", Aktion sekhmetPresetChanged:
+ (void) updatePresetToolbarItemInWindow:(NSWindow*) w viewer:(ViewerController*) v;
+ (void) presetPopupChanged:(NSPopUpButton*) sender viewer:(ViewerController*) v;
+ (void) lettersForView:(DCMView*) view left:(NSString**) left top:(NSString**) top;   // Randbuchstaben wie gezeichnet

// SekhVet Paket AX: MPR-Anordnung je Preset. Ohne eigene Anordnung gilt Horos' Grundbelegung
// (Fenster 1 sagittal, 2 transversal, 3 dorsal); ein Protokollwechsel stellt sie wieder her,
// auch wenn das Fadenkreuz vorher gedreht wurde. Eine Anordnung ist ein Array aus drei
// Dictionaries {axis 0|1|2 (x sagittal, y dorsal, z transversal), top, left (DICOM-Buchstaben)}.
+ (NSArray*) mprLayoutForPreset:(NSInteger) preset;           // nil = Grundbelegung
+ (void) setMPRLayout:(NSArray*) layout forPreset:(NSInteger) preset;   // nil = zuruecksetzen
+ (NSArray*) layoutFromMPR:(MPRController*) c error:(NSString**) error; // aktuelle Anordnung, nil + Fehlertext bei schraegen Ebenen
+ (MPRController*) frontMPR;                                  // vorderstes offenes MPR-Fenster
+ (NSInteger) presetForMPR:(MPRController*) c;
+ (NSString*) describeMPRLayout:(NSArray*) layout;            // lesbar fuer Dialog und Panel
#if SEKHVET_TESTHAKEN
+ (NSString*) debugLettersForView:(DCMView*) view;
+ (void) debugResliceFromEnvironment;    // SEKHVET_RESLICE_TEST=<0 axial|1 coronal|2 sagittal>: vorderster Viewer reslicen, Buchstaben loggen
+ (void) debugMPRFromEnvironment;         // SEKHVET_MPR_TEST=1: MPR des vordersten Viewers oeffnen (all = aller Viewer), 1/3/6/15 s spaeter Buchstaben je Ebene loggen
+ (void) debugMPRTake;                    // SekhVet Paket AX: SEKHVET_MPR_TAKE_TEST=1 — Anordnung des ersten MPR fuer sein Preset uebernehmen
+ (void) debugMPRTilt;                    // SekhVet Paket AN: SEKHVET_MPR_TILT_TEST="<Grad>,<mm>" — Ebenen schraeg stellen und verschieben
+ (void) debugDoubleMPRZoom;               // SekhVet Paket AT: SEKHVET_DOUBLE_MPR_ZOOM_TEST="<1..3>" - Doppelklick-Zoom bei zwei MPR-Fenstern
+ (void) debugPointLifetimeTest;          // SekhVet Paket AM: SEKHVET_POINT_LIFETIME_TEST="tra:256,256" — Marker nach Scroll/Pfeiltaste/Werkzeugwechsel
+ (void) debugPointTest;                  // SEKHVET_POINT_TEST="tra:256,170;256,400": Quelle = Viewer, dessen Serienname den Text enthaelt; je Pixel Punkt senden, 1,5 s spaeter Lage aller Viewer loggen
#endif // SEKHVET_TESTHAKEN

@end
