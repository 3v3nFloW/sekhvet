/*=========================================================================
 SekhVet — Ultraschall-Kalibrierung von einem Nachbarbild uebernehmen (Paket BH).
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Anlass (16.09.2026): Ein Mindray Vetus 9 (SW 2.0.0 Rev35909) schickt einzelne
 Standbilder ohne SequenceOfUltrasoundRegions (Instance Number 0), die anderen
 Bilder derselben Serie tragen sie. Laengen kamen dort nur in Pixeln.

 Regel: Ein US-Bild ohne Region und ohne Pixelabstand uebernimmt die Regionen
 eines Bildes derselben Serie, wenn
   - beide gleich gross sind,
   - der Spender eine 2D-Region in cm hat, die nicht selbst uebernommen ist,
   - die eingebrannte Tiefenskala pixelgleich ist: im rechten Randstreifen
     (8 % der Breite, mind. 40 px, Hoehe der 2D-Region) die Maske der hellen
     Pixel (ueber halber Spanne) mit IoU >= 0.9 und je >= 100 Pixeln.
 Eine andere Tiefe verschiebt die Skalenstriche; gemessen an den Mindray-Bildern
 faellt die IoU schon bei 2 % Tiefenaenderung auf 0.2. Messungen auf einem
 solchen Bild tragen im Textfeld den Hinweis, woher die Kalibrierung stammt.
 Abschalten: defaults SekhmetUSCalibrationFallback = NO.
 ============================================================================*/

#import <Foundation/Foundation.h>
#include "SekhmetTesthaken.h"
#import "DCMUSRegion.h"

@class DCMPix;

// Region, die von einem anderen Bild stammt; die Kennung zeigt das ROI-Textfeld an.
@interface SekhmetBorrowedUSRegion : DCMUSRegion
{
    NSString *sourceLabel;
}
@property (nonatomic, copy) NSString *sourceLabel;
+ (SekhmetBorrowedUSRegion*) borrowedRegionFrom:(DCMUSRegion*) r label:(NSString*) label;
@end

@interface SekhmetUSKalibrierung : NSObject

// pixList: DCMPix einer Serie (geladen); labels: gleich lang, Anzeigename je Bild ("image 1").
// Liefert die Zahl der Bilder, die eine Kalibrierung erhalten haben.
+ (NSUInteger) borrowCalibrationInPixList:(NSArray*) pixList labels:(NSArray*) labels;

// Herkunft, falls die Kalibrierung dieses Bildes uebernommen ist, sonst nil.
+ (NSString*) borrowedSourceForPix:(DCMPix*) pix;

// IoU der Skalenmasken (0..1), -1 wenn nicht vergleichbar. offsetB verschiebt b senkrecht (Selbsttest).
+ (double) rulerIoUBetween:(DCMPix*) a and:(DCMPix*) b region:(DCMUSRegion*) r offsetB:(int) offsetB;

#if SEKHVET_TESTHAKEN
// Selbsttest ueber einen Ordner mit DICOM-Dateien (nur Testbuild).
+ (NSString*) debugSelfTestWithDirectory:(NSString*) dir;
#endif // SEKHVET_TESTHAKEN

@end
