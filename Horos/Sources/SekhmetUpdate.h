/*=========================================================================
 SekhVet Paket CB — Update-Pruefung gegen die GitHub-Releases.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Horos fragte einen eigenen Feed ab, der seit dem Fork immer "neuer" gemeldet
 haette; SekhVet hatte darum bisher gar keine Pruefung (Paket T/BN). Jetzt:
 das neueste STABILE Release von github.com/3v3nFloW/sekhvet (Pre-releases =
 Betas werden nicht angeboten, ausser mit dem versteckten Schalter
 SekhmetUpdateBetas). Verglichen wird die Build-Nummer: aus dem DMG-Namen
 ("SekhVet-1.0-build130-macOS.dmg" -> 130), sonst aus dem Tag ("v1.0-beta.117").
 "Download" oeffnet den DMG-Link im Browser — SekhVet ersetzt sich nicht selbst.
 SekhVet Paket CS: the browser is only ever sent to
 https://github.com/3v3nFloW/sekhvet/… (anything else -> releases page), and
 every field of the GitHub answer is type-checked.

 Beim Start still, hoechstens einmal in 24 Stunden und nur mit dem Haekchen
 Preferences > General (CheckHorosUpdates). Der Menuepunkt "Check for Updates"
 prueft sofort und meldet auch "aktuell" und "keine Verbindung".
 Gesendet wird nur die Anfrage selbst (User-Agent "SekhVet/<Build>").
 Test: bash SekhVet/test/update-test.sh
 ============================================================================*/

#import <Cocoa/Cocoa.h>

@interface SekhmetUpdate : NSObject

+ (void) pruefenNachStart;                  // still, 15 s nach dem Start, hoechstens alle 24 h
+ (void) pruefen:(BOOL) ausdruecklich;      // YES = Menue: meldet auch "aktuell"/Fehler, ignoriert "Skip"

// Reine Logik (fuer den Test): Angebot aus der GitHub-Antwort ({…} von /releases/latest
// oder […] von /releases). Liefert {build, dmg, name, seite, notizen} oder nil.
+ (NSDictionary*) angebotAus:(id) json betas:(BOOL) betas;
+ (NSInteger) buildAusName:(NSString*) dmgName tag:(NSString*) tag;
// SekhVet Paket CS
+ (NSString*) sichereAdresse:(id) adresse;                           // adresse, wenn https://github.com/3v3nFloW/sekhvet/…, sonst die Releases-Seite
+ (NSDictionary*) unklaresReleaseAus:(id) json betas:(BOOL) betas;   // neuestes Release mit DMG, aber ohne Build-Nummer: {name, seite} oder nil

@end
