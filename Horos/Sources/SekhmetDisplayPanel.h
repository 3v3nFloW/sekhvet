/*=========================================================================
 Sekhmet — Anzeige-Einstellungen (programmatisch, ohne Nib):
 Viewer-Flaeche je Bildschirm (Brueche oder Pixel-Rechteck), Hintergrund
 der Beschriftungen, MPR-Gleichlauf und -Kachelung.
 Menue "Sekhmet > Anzeige…".
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>

extern NSString* const SekhmetScreenAreasKey;        // Dict: "<Bildschirmindex>" -> NSNumber Modus
extern NSString* const SekhmetScreenAreaRectsKey;    // Dict: "<Bildschirmindex>" -> "x y w h" (relativ zur sichtbaren Flaeche)
extern NSString* const SekhmetAnnotationBackgroundKey; // 0 Horos, 1 Kontur, 2 Kasten, 3 beide
extern NSString* const SekhmetMPRSyncKey;
extern NSString* const SekhmetTile3DWindowsKey;
extern NSString* const SekhmetAppearanceKey;        // SekhVet Paket N: 0 System, 1 Hell, 2 Dunkel
extern NSString* const SekhmetModalityColorsKey;    // SekhVet Paket N: BOOL
extern NSString* const SekhmetROITextColorModeKey;  // SekhVet Paket N: 0 ROI-Farbe, 1 Weiss, 2 Gelb, 3 eigene
extern NSString* const SekhmetROITextColorKey;      // "r g b"
extern NSString* const SekhmetAnnotationBoxColorKey; // "r g b a"

enum {
    SekhmetAreaFull = 0,
    SekhmetAreaLeftHalf = 1,
    SekhmetAreaRightHalf = 2,
    SekhmetAreaLeftTwoThirds = 3,
    SekhmetAreaRightTwoThirds = 4,
    SekhmetAreaCenterHalf = 5,
    SekhmetAreaPixelRect = 9
};

@interface SekhmetDisplayPanel : NSWindowController
{
    NSMutableArray *areaPopups;     // je Bildschirm
    NSMutableArray *rectFields;
    NSPopUpButton *annotationPopup;
    NSButton *syncButton, *tileButton, *staticCursorButton, *zoomSyncButton, *magneticButton; // magneticButton: SekhVet Paket AH // zoomSyncButton: SekhVet Paket P
    NSTextField *centerZoneField, *lineZoneField;
    NSPopUpButton *appearancePopup, *fontPopup, *textColorPopup; // SekhVet Paket N
    NSButton *modalityColorsButton;
    NSTextField *fontSizeField;
    NSColorWell *textColorWell, *boxColorWell;
}

+ (NSImage*) crosshairIcon; // SekhVet Paket AH: Fadenkreuz (Template) fuer das Point-Werkzeug
+ (SekhmetDisplayPanel*) shared;
+ (NSRect) areaForScreen:(NSScreen*) screen frame:(NSRect) visibleFrame;   // die Sekhmet-Flaeche
+ (NSArray*) areaModeNames;
+ (NSInteger) modeForIndex:(NSInteger) i;
+ (NSInteger) indexForMode:(NSInteger) m;
+ (void) setMode:(NSInteger) mode forScreen:(NSScreen*) screen;
+ (NSInteger) modeForScreen:(NSScreen*) screen;
+ (void) placeWindow:(NSWindow*) w nearWindow:(NSWindow*) ref centered:(BOOL) centered;
+ (void) applyAppearance;                                        // SekhVet Paket N: NSApp.appearance aus SekhmetAppearance
+ (NSColor*) modalityColorForModality:(NSString*) modality;     // SekhVet Paket N: Zeilentoenung (alpha 0.22) oder nil   // in die Viewer-Flaeche des Bildschirms von ref (oben links oder mittig), nur wenn w noch nicht sichtbar

@end

// SekhVet Paket F: About-Fenster mit Lizenzhinweis (LGPL 3.0, Horos/OsiriX) und Links (Spenden, VoiceInk, Quelltext)
// SekhVet Paket BB: Skalenstriche eines Reglers nach Bildzahl setzen; ab SEKHMET_SLIDER_MAX_TICKS
// Bildern gibt es keine. Grund: AppKit (macOS 26) legt je Strich ein Rechteck an und baut den
// Regler dabei zweimal neu - bei 1700 Bildern rund eine halbe Sekunde auf dem Hauptthread,
// sichtbar als Wartecursor beim Oeffnen jeder Serie. Ab ein paar Dutzend Strichen ist die
// Skala ohnehin nur noch ein Balken, und alle Aufrufer lesen intValue, brauchen also kein
// Einrasten auf Striche.
#define SEKHMET_SLIDER_MAX_TICKS 100
void SekhmetSliderSetTickMarks(NSSlider* slider, NSInteger count);

@interface SekhmetAbout : NSWindowController
+ (SekhmetAbout*) shared;
+ (void) openURLKey:(NSString*) key;   // oeffnet die URL aus den Defaults; leer -> Hinweis, wie man sie setzt
+ (void) showDisclaimerIfNeeded;      // SekhVet Paket AA: Hinweis beim ersten Start, kein zertifiziertes Medizinprodukt
- (IBAction) donate:(id) sender;
- (IBAction) voiceInk:(id) sender;
- (IBAction) feedback:(id) sender;     // SekhVet Paket AZ: vorbefuellte Mail an SekhmetFeedbackAddress
+ (NSString*) feedbackBody;           // SekhVet Paket AZ: Vorlage samt Version/macOS/Mac-Modell (auch fuer den Testhaken)
- (IBAction) source:(id) sender;
- (IBAction) license:(id) sender;
- (NSTextField*) aboutLabel:(NSString*) text frame:(NSRect) r size:(float) size bold:(BOOL) bold;  // SekhVet Paket AR: von SekhmetContribute mitbenutzt
- (NSButton*) aboutButton:(NSString*) title frame:(NSRect) r action:(SEL) sel;                     // SekhVet Paket AR
@end

// SekhVet Paket AR: Beitrags-Fenster mit Zahlungs-QR (CHF Swiss QR, EUR GiroCode).
// Kein Zahlungsdienstleister dazwischen: die Zahlung geht als Ueberweisung direkt auf das GmbH-Konto.
@interface SekhmetContribute : NSWindowController
+ (SekhmetContribute*) shared;
+ (void) showReminderIfNeeded;   // hoechstens zweimal je Installation, nie beim ersten Start, abschaltbar
- (IBAction) copyCHF:(id) sender;
- (IBAction) copyEUR:(id) sender;
@end
