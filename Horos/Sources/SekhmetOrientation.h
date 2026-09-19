/*=========================================================================
 Sekhmet — veterinaere Orientierung (ersetzt das vetHP-Plugin)
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Reine Anzeigetransformation (rotation / xFlipped / yFlipped) am DCMView,
 die Originaldaten werden nie angefasst. Vier Regeln je Preset, drei Presets
 (Kopf/Wirbelsaeule, Extremitaeten, frei) plus "Aus". Stichwort-Tabelle waehlt
 das Preset beim Oeffnen, ein Toolbar-Popup je Studie ueberstimmt sie.
 Nach jedem Setzen werden die Randbuchstaben zurueckgelesen; greift die
 Drehung nicht, wird zurueckgesetzt und sichtbar gemeldet (Lehre aus vetHP).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class ViewerController, DCMView, DCMPix, MPRController;

#ifdef __cplusplus
extern "C" {
#endif

extern NSString* const SekhmetVetPresetKey;                 // NSNumber 0..3, Vorgabe-Preset
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
    SekhmetPresetOff = 0,
    SekhmetPresetHeadSpine = 1,
    SekhmetPresetHindlimb = 2,   // bis Paket AF "Limbs": kranial/proximal oben
    SekhmetPresetForelimb = 3,   // SekhVet Paket AF: proximal = kaudal -> kaudal oben
    SekhmetPresetCustom = 4,
    SekhmetPresetCustom2 = 5,    // SekhVet Paket AF: zweites frei programmierbares Protokoll
    SekhmetPresetLast = 5
};
#define SekhmetPresetLimb SekhmetPresetHindlimb

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
+ (NSMenu*) presetMenuIncludingOff:(BOOL) off;                // Eintraege tragen die id als tag
+ (NSString*) rulesKeyForPreset:(NSInteger) preset;
+ (NSDictionary*) rulesForPreset:(NSInteger) preset;
+ (void) setRules:(NSDictionary*) rules forPreset:(NSInteger) preset;

+ (NSString*) descriptionForViewer:(ViewerController*) v;     // Study- + Serienbeschreibung fuer die Stichworte
+ (NSInteger) presetForStudyUID:(NSString*) uid description:(NSString*) description;
+ (void) setPresetOverride:(NSInteger) preset forStudyUID:(NSString*) uid;   // < 0 = Override entfernen

+ (NSString*) applyToViewer:(ViewerController*) v;            // liefert Statustext (Badge) oder nil
+ (NSString*) statusForViewer:(ViewerController*) v;
+ (NSString*) titleForViewer:(ViewerController*) v baseTitle:(NSString*) title;
+ (void) applyToAllViewersOfStudyUID:(NSString*) uid;         // nil = alle offenen 2D-Viewer und 3D-MPR-Fenster
+ (NSString*) applyToMPR:(MPRController*) c;                  // Regeln auf die drei MPR-Ansichten (Kamera um die Blickrichtung drehen + Anzeige spiegeln, Paket AX), liefert Statustext
+ (NSString*) applyToMPR:(MPRController*) c straighten:(BOOL) straighten;  // SekhVet Paket AN: straighten = Ebenen vorher auf die Volumenachsen stellen (Protokollwechsel)
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
+ (void) debugMPRFromEnvironment;
+ (void) debugMPRTake;                    // SekhVet Paket AX: SEKHVET_MPR_TAKE_TEST=1 — Anordnung des ersten MPR fuer sein Preset uebernehmen
+ (void) debugMPRTilt;                    // SekhVet Paket AN: SEKHVET_MPR_TILT_TEST="<Grad>,<mm>" — Ebenen schraeg stellen und verschieben
+ (void) debugDoubleMPRZoom;               // SekhVet Paket AT: SEKHVET_DOUBLE_MPR_ZOOM_TEST="<1..3>" - Doppelklick-Zoom bei zwei MPR-Fenstern
+ (void) debugPointLifetimeTest;          // SekhVet Paket AM: SEKHVET_POINT_LIFETIME_TEST="tra:256,256" — Marker nach Scroll/Pfeiltaste/Werkzeugwechsel
+ (void) debugPointTest;                  // SEKHVET_POINT_TEST="tra:256,170;256,400": Quelle = Viewer, dessen Serienname den Text enthaelt; je Pixel Punkt senden, 1,5 s spaeter Lage aller Viewer loggen        // SEKHVET_MPR_TEST=1: MPR des vordersten Viewers oeffnen, 15 s spaeter Buchstaben je Ebene loggen
#endif // SEKHVET_TESTHAKEN

@end
