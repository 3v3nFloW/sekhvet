/*=========================================================================
 Sekhmet — eingeschraenktes Auspacken alter NSArchiver-Archive (Paket DE).
 Typedstream-Pruefung nach ThalesMMS/horos e948e313 (RestrictedUnarchiver.swift,
 LGPL-3.0, (c) 2026 Thales Matheus M Santos), nach Objective-C uebertragen.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Foundation/Foundation.h>

// NSUnarchiver (das alte "typedstream"-Format, in dem Horos ROIs, CLUTs, Pfade usw. speichert) ruft fuer JEDE im
// Archiv genannte Klasse deren -initWithCoder: auf - bei fremden Daten (ROI-SR von einer Ueberweiser-CD, per C-STORE,
// .roi-Datei, Zwischenablage) also Code, den der Absender aussucht. Ein kaputtes Archiv stuerzt die App ab (nicht
// fangbar). Diese Klasse geht das Archiv vorher Byte fuer Byte durch, ohne etwas zu erzeugen, sammelt die Klassennamen
// und packt nur aus, wenn das Archiv wohlgeformt ist und ausschliesslich erlaubte Klassen nennt.
@interface SekhmetRestrictedUnarchiver : NSObject

+ (NSSet*) roiClassNames;            // ROI, MyPoint + Foundation-Werte
+ (NSSet*) clutClassNames;           // Kurven/Farben einer CLUT
+ (NSSet*) propertyListClassNames;   // nur Foundation-Werte (Zahlen, Text, Daten, Felder, Woerterbuecher, Datum)

// Klassennamen im Archiv, oder nil (mit Grund), wenn es kein Typedstream ist, den diese Pruefung annimmt
+ (NSArray*) classNamesInData:(NSData*) data reason:(NSString**) reason;

// Ausgepacktes Objekt oder nil (Grund im Log), wenn das Archiv nicht wohlgeformt ist oder eine andere Klasse nennt
+ (id) unarchiveObjectWithData:(NSData*) data allowedClassNames:(NSSet*) allowed;

+ (NSArray*) unarchiveROIsWithData:(NSData*) data;   // nil, wenn kein Feld
+ (NSArray*) unarchiveROIsWithFile:(NSString*) path;
+ (id) unarchiveCLUTWithData:(NSData*) data;
+ (id) unarchiveCLUTWithFile:(NSString*) path;
+ (NSSet*) colorClassNames;
+ (NSSet*) curvedPathClassNames;     // CPRCurvedPath (NSKeyedArchiver)

// Dasselbe fuer NSKeyedArchiver-Archive (binaere Property-Liste): alle "$classname" muessen erlaubt sein
+ (id) unarchiveKeyedObjectWithData:(NSData*) data allowedClassNames:(NSSet*) allowed;

@end
