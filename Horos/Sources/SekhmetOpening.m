/*=========================================================================
 SekhVet Paket AU — Oeffnungsprotokolle. Siehe Header.
 ============================================================================*/

#import "SekhmetOpening.h"
#import "SekhmetWindowing.h"
#import "SekhmetDisplayPanel.h"
#import "SekhmetTesthaken.h"
#import "BrowserController.h"
#import "AppController.h"
#import "ViewerController.h"
#import "DCMView.h"
#import "DicomStudy.h"
#import "DicomSeries.h"
#import "DicomImage.h"
#import "DCM.h"
#import "Notifications.h"
#import "DicomDatabase.h"

NSString* const SekhmetOpeningProtocolsKey  = @"SekhmetOpeningProtocols";
NSString* const SekhmetOpeningEnabledKey    = @"SekhmetOpeningEnabled";
NSString* const SekhmetOpeningSmallWidthKey = @"SekhmetOpeningSmallWidth";
NSString* const SekhmetOpeningSmallMaxKey   = @"SekhmetOpeningSmallMax";
NSString* const SekhmetTwoViewEnabledKey     = @"SekhmetTwoViewEnabled";
NSString* const SekhmetTwoViewLateralLeftKey = @"SekhmetTwoViewLateralLeft";

// Die offenen schwarzen Kacheln. Steht hier oben, weil der Testhaken sie mitprotokolliert.
static NSMutableArray *sekhmetBlackTiles = nil;

// viewerDICOMInt:…protocol: steht nicht im Horos-Header, nur in der .m — Horos-Idiom:
// die Signatur hier bekanntgeben, statt einen fremden Header anzufassen.
@interface BrowserController (SekhmetOpeningPrivate)
- (void) viewerDICOMInt:(BOOL) movieViewer dcmFile:(NSArray*) selectedLines viewer:(ViewerController*) viewer tileWindows:(BOOL) tileWindows protocol:(NSDictionary*) protocol;
@end

static NSDictionary* sekhmetPosition( NSString *keywords, NSString *without, NSString *window, NSInteger contrast)
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            keywords ? keywords : @"", @"keywords",
            without ? without : @"", @"without",
            window ? window : @"", @"window",
            [NSNumber numberWithInteger: contrast], @"contrast",
            [NSNumber numberWithFloat: 0], @"wl",
            [NSNumber numberWithFloat: 0], @"ww",
            nil];
}

static NSDictionary* sekhmetProtocol( NSString *name, NSString *modality, NSString *region, int rows, int columns, BOOL black, NSArray *positions)
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            name, @"name", modality, @"modality", region, @"region",
            [NSNumber numberWithInt: rows], @"rows",
            [NSNumber numberWithInt: columns], @"columns",
            [NSNumber numberWithBool: black], @"blackTiles",
            positions, @"positions", nil];
}

@implementation SekhmetOpening

+ (NSArray*) defaultProtocols
{
    // Reihenfolge = Prioritaet, das erste passende Protokoll gewinnt. Die MR-Protokolle
    // stehen vor dem CT, weil sie enger gefasst sind; treffen muessen sie ohnehin beide.
    // Stichworte belegt nach der Erhebung vom 15.09.2026 auf dem Praxis-PACS:
    // 679 CT-Serien (Siemens "nativ"/"KM" + Kernel, Canon "WT/KF", GE "N"/"C") und
    // 146 MR-Serien des Esaote (Region nur in ProtocolName/BodyPartExamined, nie in der Studie).
    return [NSArray arrayWithObjects:

        sekhmetProtocol( @"MR head", @"MR", @"NEUROCRANIUM|Brain|Kopf|Head", 2, 2, NO,
            [NSArray arrayWithObjects:
                sekhmetPosition( @"T2 sag", nil, nil, SekhmetContrastAny),
                sekhmetPosition( @"T2 tra", nil, nil, SekhmetContrastAny),
                sekhmetPosition( @"T1 tra", @"post KM|KM", nil, SekhmetContrastAny),
                sekhmetPosition( @"T1 tra", nil, nil, SekhmetContrastAgent),
                nil]),

        sekhmetProtocol( @"MR spine", @"MR", @"CERVICAL|THORACO_LUMBAR|LUMBO_SACRAL|HWS|BWS|LWS|Spine", 1, 2, NO,
            [NSArray arrayWithObjects:
                sekhmetPosition( @"T2 sag", nil, nil, SekhmetContrastAny),
                sekhmetPosition( @"T2 tra", nil, nil, SekhmetContrastAny),
                nil]),

        sekhmetProtocol( @"MR stifle", @"MR", @"STIFLE|Knee|Knie", 1, 4, NO,
            [NSArray arrayWithObjects:
                sekhmetPosition( @"STIR", nil, nil, SekhmetContrastAny),
                sekhmetPosition( @"GE T2|Gradient Echo T2", nil, nil, SekhmetContrastAny),   // sagittal zuerst, siehe "without" unten
                sekhmetPosition( @"GE T2|Gradient Echo T2", nil, nil, SekhmetContrastAny),
                sekhmetPosition( @"SST1|3D SST1", nil, nil, SekhmetContrastAgent),
                nil]),

        // CT: eine Belegung fuer alle Regionen — Weichteil nativ, Weichteil KM, Knochen nativ
        // (links nach rechts). Knochen/Weichteil kommt aus der WL/WW-Regel von Paket AE/AH,
        // damit Siemens-, Canon- und GE-Kernel ohne eigene Stichwortpflege stimmen.
        sekhmetProtocol( @"CT", @"CT", @"", 1, 3, NO,
            [NSArray arrayWithObjects:
                sekhmetPosition( nil, nil, @"Soft tissue", SekhmetContrastNative),
                sekhmetPosition( nil, nil, @"Soft tissue", SekhmetContrastAgent),
                sekhmetPosition( nil, nil, @"Bone (vet)", SekhmetContrastNative),
                nil]),
        nil];
}

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues
{
    [defaultValues setObject: [self defaultProtocols] forKey: SekhmetOpeningProtocolsKey];
    [defaultValues setObject: [NSNumber numberWithBool: YES] forKey: SekhmetOpeningEnabledKey];
    [defaultValues setObject: [NSNumber numberWithFloat: 1600] forKey: SekhmetOpeningSmallWidthKey];
    [defaultValues setObject: [NSNumber numberWithInt: 2] forKey: SekhmetOpeningSmallMaxKey];
    [defaultValues setObject: [NSNumber numberWithBool: YES] forKey: SekhmetTwoViewEnabledKey];
    [defaultValues setObject: [NSNumber numberWithBool: NO] forKey: SekhmetTwoViewLateralLeftKey];
}

#pragma mark - Erkennung

// Serienname + Faltungskern + ProtocolName + BodyPartExamined der ERSTEN Datei der Serie.
// Gleiches Muster wie SekhmetWindowing kernelForViewer: (Paket AH), nur auf der Datenbank
// statt auf einem offenen Viewer — beim Oeffnen gibt es noch keinen Viewer.
+ (NSString*) searchTextForSeries:(DicomSeries*) series
{
    static NSMutableDictionary *cache = nil;
    if( cache == nil) cache = [[NSMutableDictionary alloc] init];
    if( series == nil) return @"";

    NSString *uid = nil;
    @try { uid = [series valueForKey: @"seriesInstanceUID"]; } @catch (NSException *e) { }
    if( uid.length)
    {
        NSString *cached = [cache objectForKey: uid];
        if( cached) return cached;
    }

    NSMutableString *s = [NSMutableString string];
    @try
    {
        NSString *name = [self nameForSeries: series];
        if( name.length) [s appendString: name];
        NSString *desc = [series valueForKey: @"seriesDescription"];
        if( desc.length && ![desc isEqualToString: name]) [s appendFormat: @" %@", desc];

        NSArray *images = [series sortedImages];
        if( images.count)
        {
            NSString *path = [[images objectAtIndex: 0] valueForKey: @"completePath"];
            if( path.length)
            {
                DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
                NSString *k = [o attributeValueWithName: @"ConvolutionKernel"];
                NSString *p = [o attributeValueWithName: @"ProtocolName"];
                NSString *b = [o attributeValueWithName: @"BodyPartExamined"];
                if( k.length) [s appendFormat: @" [%@]", k];
                if( p.length) [s appendFormat: @" %@", p];
                if( b.length) [s appendFormat: @" %@", b];
            }
        }
    }
    @catch (NSException *e) { }

    if( cache.count > 500) [cache removeAllObjects];
    if( uid.length) [cache setObject: s forKey: uid];
    return s;
}

// Kontrastphase. Nur der SERIENNAME wird zerlegt, nicht der ganze Suchtext: "CERVICAL"
// aus BodyPartExamined darf nicht als GE-Kontrastkuerzel "C" gelesen werden.
// Marker als ganzes Wort: KM / post KM / CE / C = Kontrast, nativ / N = nativ.
// Horos fuehrt den Serientext in "name"; "seriesDescription" traegt bei manchen Geraeten
// die STUDIENbeschreibung (Siemens der Praxis: alle sechs Serien hiessen dort gleich).
// Darum "name" zuerst — SekhmetWindowing descriptionForViewer: macht es genauso.
+ (NSString*) nameForSeries:(DicomSeries*) series
{
    NSString *n = nil;
    @try
    {
        n = [series valueForKey: @"name"];
        if( n.length == 0) n = [series valueForKey: @"seriesDescription"];
    }
    @catch (NSException *e) { }
    return n ? n : @"";
}

+ (NSInteger) contrastForName:(NSString*) name
{
    if( name.length == 0) return SekhmetContrastAny;
    NSCharacterSet *sep = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSArray *tokens = [name componentsSeparatedByCharactersInSet: sep];
    for( NSString *raw in tokens)
    {
        NSString *t = [raw uppercaseString];
        if( [t isEqualToString: @"KM"] || [t isEqualToString: @"CE"] || [t isEqualToString: @"C"])
            return SekhmetContrastAgent;
    }
    for( NSString *raw in tokens)
    {
        NSString *t = [raw uppercaseString];
        if( [t isEqualToString: @"NATIV"] || [t isEqualToString: @"NATIVE"] || [t isEqualToString: @"N"])
            return SekhmetContrastNative;
    }
    return SekhmetContrastAny;
}

+ (NSInteger) contrastForSeries:(DicomSeries*) series
{
    return [self contrastForName: [self nameForSeries: series]];
}

+ (BOOL) text:(NSString*) text containsAnyOf:(NSString*) list
{
    if( list.length == 0) return NO;
    for( NSString *raw in [list componentsSeparatedByString: @"|"])
    {
        NSString *t = [raw stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
        if( t.length && [text rangeOfString: t options: NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

+ (NSString*) regionTextForStudy:(DicomStudy*) study
{
    NSMutableString *s = [NSMutableString string];
    @try
    {
        NSString *n = [study valueForKey: @"studyName"];
        if( n.length) [s appendString: n];
    }
    @catch (NSException *e) { }
    for( DicomSeries *series in [study imageSeries])
        [s appendFormat: @" %@", [self searchTextForSeries: series]];
    return s;
}

+ (NSDictionary*) protocolForStudy:(DicomStudy*) study
{
    if( study == nil) return nil;
    NSString *modality = nil;
    @try { modality = [[study valueForKey: @"modality"] uppercaseString]; } @catch (NSException *e) { }
    NSString *regionText = [self regionTextForStudy: study];

    for( NSDictionary *p in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetOpeningProtocolsKey])
    {
        NSString *pm = [[p objectForKey: @"modality"] uppercaseString];
        if( pm.length && (modality.length == 0 || [modality rangeOfString: pm].location == NSNotFound)) continue;
        NSString *region = [p objectForKey: @"region"];
        if( region.length && ![self text: regionText containsAnyOf: region]) continue;
        if( [[p objectForKey: @"positions"] count] == 0) continue;
        return p;
    }
    return nil;
}

+ (BOOL) series:(DicomSeries*) series matchesPosition:(NSDictionary*) pos
{
    NSString *text = [self searchTextForSeries: series];
    NSString *keywords = [pos objectForKey: @"keywords"];
    if( keywords.length && ![self text: text containsAnyOf: keywords]) return NO;
    NSString *without = [pos objectForKey: @"without"];
    if( without.length && [self text: text containsAnyOf: without]) return NO;
    NSString *window = [pos objectForKey: @"window"];
    if( window.length)
    {
        NSString *modality = nil;
        @try { modality = [[series valueForKey: @"modality"] uppercaseString]; } @catch (NSException *e) { }
        NSDictionary *rule = [SekhmetWindowing ruleForModality: modality description: text];
        if( ![[rule objectForKey: @"name"] isEqualToString: window]) return NO;
    }
    NSInteger contrast = [[pos objectForKey: @"contrast"] integerValue];
    if( contrast != SekhmetContrastAny && [self contrastForSeries: series] != contrast) return NO;
    return YES;
}

+ (NSArray*) seriesForProtocol:(NSDictionary*) protocol study:(DicomStudy*) study
{
    NSMutableArray *pool = [NSMutableArray arrayWithArray: [study imageSeriesContainingPixels: YES]];
    if( pool.count == 0) pool = [NSMutableArray arrayWithArray: [study imageSeries]];

    NSMutableArray *result = [NSMutableArray array];
    for( NSDictionary *pos in [protocol objectForKey: @"positions"])
    {
        DicomSeries *hit = nil;
        for( DicomSeries *s in pool)
        {
            if( [self series: s matchesPosition: pos]) { hit = s; break; }
        }
        if( hit) { [result addObject: hit]; [pool removeObject: hit]; }   // jede Serie nur einmal
        else [result addObject: [NSNull null]];
    }
    return result;
}

#pragma mark - SekhVet Paket AY: Roentgen-Zweiebenen

// Gemessen fuer ImagoPilot am 05.09.2026 (400 Untersuchungen / 971 Serien der Praxis): 163 Paare,
// jedes mit GENAU EINER seitlichen Aufnahme — darum ist "seitlich nach rechts" ueberhaupt entscheidbar.
// Die Woerter sind die gemessenen (LL 138, ML 25) plus die Schreibweisen anderer Geraete fuer dieselbe
// Ebene. Kommt ein unbekanntes Wort, ordnet die Regel nicht falsch, sondern haelt die Serienreihenfolge.
+ (BOOL) isLateralProjection:(NSString*) p
{
    static NSSet *lateral = nil;
    if( lateral == nil) lateral = [[NSSet alloc] initWithObjects: @"LL", @"RL", @"ML", @"LM", @"LAT", @"LATERAL", nil];
    return [lateral containsObject: p];
}

+ (NSString*) projectionForViewPosition:(NSString*) viewPosition name:(NSString*) name
{
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *vp = [[viewPosition stringByTrimmingCharactersInSet: ws] uppercaseString];
    if( vp.length) return vp;   // Canon CXDI und manche Varian-Aufnahmen fuellen es ("VD"/"LL"/"LAT")
    NSMutableArray *words = [NSMutableArray array];
    for( NSString *w in [name componentsSeparatedByCharactersInSet: ws]) if( w.length) [words addObject: w];
    // Ein einzelnes Wort ist keine Projektion, sondern ein Name ("IIP_MWL_SCU" bei zwei Geraeten der Praxis)
    return words.count >= 2 ? [[words lastObject] uppercaseString] : @"";
}

+ (NSInteger) twoViewOrderForProjection:(NSString*) a projection:(NSString*) b lateralLeft:(BOOL) lateralLeft
{
    if( a.length == 0 || b.length == 0 || [a isEqualToString: b]) return 0;
    BOOL la = [self isLateralProjection: a], lb = [self isLateralProjection: b];
    if( la == lb) return 1;   // beide oder keine seitlich: nebeneinander in Serienreihenfolge
    BOOL aLeft = lateralLeft ? la : lb;   // die seitliche gehoert auf ihre Seite, die andere gegenueber
    return aLeft ? 1 : 2;
}

+ (NSArray*) twoViewPairForStudy:(DicomStudy*) study
{
    if( study == nil || ![[NSUserDefaults standardUserDefaults] boolForKey: SekhmetTwoViewEnabledKey]) return nil;
    NSArray *pool = [study imageSeriesContainingPixels: YES];
    if( pool.count == 0) pool = [study imageSeries];
    if( pool.count != 2) return nil;
    // Serienreihenfolge (SeriesNumber), damit "nicht entscheidbar" stabil bleibt
    NSArray *two = [pool sortedArrayUsingDescriptors: [NSArray arrayWithObjects:
                    [NSSortDescriptor sortDescriptorWithKey: @"id" ascending: YES],
                    [NSSortDescriptor sortDescriptorWithKey: @"date" ascending: YES], nil]];

    static NSSet *projectionModalities = nil;
    if( projectionModalities == nil) projectionModalities = [[NSSet alloc] initWithObjects: @"CR", @"DX", @"IO", @"PX", @"MG", nil];
    NSMutableArray *regions = [NSMutableArray array], *projections = [NSMutableArray array];
    for( DicomSeries *s in two)
    {
        NSString *modality = nil;
        int images = 0;
        @try
        {
            modality = [[s valueForKey: @"modality"] uppercaseString];
            images = [[s valueForKey: @"numberOfImages"] intValue];   // roh: negativ = Multiframe, siehe Paket AQ
        }
        @catch (NSException *e) { return nil; }
        if( ![projectionModalities containsObject: modality] || images != 1) return nil;
        NSString *region = [[[self tag: @"BodyPartExamined" forSeries: s] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] uppercaseString];
        if( region.length == 0) return nil;
        [regions addObject: region];
        [projections addObject: [self projectionForViewPosition: [self tag: @"ViewPosition" forSeries: s] name: [self nameForSeries: s]]];
    }
    if( ![[regions objectAtIndex: 0] isEqualToString: [regions objectAtIndex: 1]]) return nil;

    NSInteger order = [self twoViewOrderForProjection: [projections objectAtIndex: 0] projection: [projections objectAtIndex: 1]
                                          lateralLeft: [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetTwoViewLateralLeftKey]];
    if( order == 0) return nil;
    NSArray *result = order == 1 ? two : [NSArray arrayWithObjects: [two objectAtIndex: 1], [two objectAtIndex: 0], nil];
    NSLog( @"SekhVet two-view: %@ %@ / %@ -> left \"%@\", right \"%@\"", [regions objectAtIndex: 0],
          [projections objectAtIndex: 0], [projections objectAtIndex: 1],
          [self nameForSeries: [result objectAtIndex: 0]], [self nameForSeries: [result objectAtIndex: 1]]);
    return result;
}

#pragma mark - Oeffnen

// Horos kachelt nur mit AUTOTILING; fuer die Dauer des Oeffnens einschalten und danach
// den Stand des Benutzers zurueckstellen.
+ (void) openSeries:(NSArray*) open rows:(int) rows columns:(int) columns
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL restoreNoAutotiling = NO;
    int windowSizeCopy = 0;
    if( [d boolForKey: @"AUTOTILING"] != YES)
    {
        restoreNoAutotiling = YES;
        windowSizeCopy = (int) [d integerForKey: @"WINDOWSIZEVIEWER"];
        [d setBool: YES forKey: @"AUTOTILING"];
    }

    [SekhmetBlackTile closeAll];

    NSDictionary *tile = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNumber numberWithInt: rows], @"rows",
                          [NSNumber numberWithInt: columns], @"columns", nil];
    [[BrowserController currentBrowser] viewerDICOMInt: NO dcmFile: open viewer: nil tileWindows: YES protocol: tile];

    if( restoreNoAutotiling)
    {
        [d setBool: NO forKey: @"AUTOTILING"];
        [d setInteger: windowSizeCopy forKey: @"WINDOWSIZEVIEWER"];
    }
}

+ (BOOL) applyToStudy:(DicomStudy*) study
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( study == nil || ![d boolForKey: SekhmetOpeningEnabledKey]) return NO;

    // Liegt schon eine Serie dieser Studie offen, macht Horos weiter wie bisher
    // (dort holt es die Fenster nur nach vorn).
    for( DicomSeries *shown in [ViewerController getDisplayedSeries])
    {
        for( DicomSeries *s in [study imageSeries])
        {
            if( [[shown valueForKey: @"seriesInstanceUID"] isEqualToString: [s valueForKey: @"seriesInstanceUID"]])
                return NO;
        }
    }

    // SekhVet Paket AY: Roentgen-Zweiebenen vor den Protokollen — die Regel ist enger gefasst,
    // und ein Protokoll ohne Modalitaet wuerde sonst jede Roentgenstudie schlucken.
    NSArray *pair = [self twoViewPairForStudy: study];
    if( pair)
    {
        [self openSeries: pair rows: 1 columns: 2];
        NSArray *screens = [[AppController sharedAppController] viewerScreens];
        if( screens.count == 1)   // auf einem Schirm selbst in die Zellen setzen, dann entscheidet nicht die Fensterreihenfolge
            [self placeViewersOfStudy: study cells: [NSArray arrayWithObjects: @0, @1, nil] series: pair rows: 1 columns: 2 screen: [screens objectAtIndex: 0]];
        return YES;
    }

    NSDictionary *p = [self protocolForStudy: study];
    if( p == nil) return NO;

    NSArray *chosen = [self seriesForProtocol: p study: study];
    NSArray *positions = [p objectForKey: @"positions"];
    int rows = MAX( 1, [[p objectForKey: @"rows"] intValue]);
    int columns = MAX( 1, [[p objectForKey: @"columns"] intValue]);
    BOOL black = [[p objectForKey: @"blackTiles"] boolValue];

    // Kleiner Schirm: Deckel auf die Zahl der Viewer.
    NSArray *screens = [[AppController sharedAppController] viewerScreens];
    int cap = 0;
    if( screens.count == 1)
    {
        float small = [d floatForKey: SekhmetOpeningSmallWidthKey];
        int smallMax = (int) [d integerForKey: SekhmetOpeningSmallMaxKey];
        NSRect r = [AppController usefullRectForScreen: [screens objectAtIndex: 0]];
        if( small > 0 && smallMax > 0 && r.size.width < small) cap = smallMax;
    }

    // Belegung in Zellen umrechnen. Ohne schwarze Kacheln ruecken die uebrigen auf,
    // mit schwarzen Kacheln behaelt jede Position ihre Zelle.
    NSMutableArray *open = [NSMutableArray array];        // DicomSeries, in Oeffnungsreihenfolge
    NSMutableArray *cells = [NSMutableArray array];       // Zellindex je geoeffneter Serie
    NSMutableArray *slots = [NSMutableArray array];       // zugehoerige Position (fuer WL/WW)
    int cell = 0;
    for( NSUInteger i = 0; i < chosen.count; i++)
    {
        id s = [chosen objectAtIndex: i];
        if( s == [NSNull null]) { if( black) cell++; continue; }
        if( cap && open.count >= (NSUInteger) cap) break;
        [open addObject: s];
        [cells addObject: [NSNumber numberWithInt: cell]];
        [slots addObject: [positions objectAtIndex: i]];
        cell++;
    }
    if( open.count == 0) return NO;

    // Ohne schwarze Kacheln das Raster auf die tatsaechliche Zahl eindampfen,
    // sonst bliebe genau das Loch stehen, das wir vermeiden wollen.
    int useRows = rows, useColumns = columns;
    if( !black || cap)
    {
        useRows = MIN( rows, (int) open.count);
        if( useRows < 1) useRows = 1;
        useColumns = (int) ceil( (float) open.count / (float) useRows);
    }

    [self openSeries: open rows: useRows columns: useColumns];

    // Auf einem Schirm setzen wir die Fenster selbst in ihre Zellen — nur so bleibt eine
    // Luecke dort stehen, wo sie hingehoert. Bei mehreren Schirmen bleibt Horos' Kachelung
    // zustaendig, die schwarzen Kacheln fallen dann ans Ende.
    if( black && screens.count == 1)
        [self placeViewersOfStudy: study cells: cells series: open rows: rows columns: columns screen: [screens objectAtIndex: 0]];

    // Schwarze Kacheln gibt es nur auf einem Schirm: nur dort setzen wir die Fenster
    // selbst in ihre Zellen und wissen deshalb, welche Zelle wirklich frei ist.
    if( black && screens.count == 1 && !cap)
        [SekhmetBlackTile showOnFreeCellsForRows: rows columns: columns taken: cells screen: [screens objectAtIndex: 0]];

    // Erzwungene Fensterung je Position — nach der Regel aus Paket AE, die beim Laden lief.
    for( NSUInteger i = 0; i < open.count; i++)
    {
        NSDictionary *pos = [slots objectAtIndex: i];
        float wl = [[pos objectForKey: @"wl"] floatValue], ww = [[pos objectForKey: @"ww"] floatValue];
        if( ww <= 0) continue;
        NSString *uid = [[open objectAtIndex: i] valueForKey: @"seriesInstanceUID"];
        for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        {
            if( [[[v currentSeries] valueForKey: @"seriesInstanceUID"] isEqualToString: uid])
                [[v imageView] setWLWW: wl :ww];
        }
    }

    NSLog( @"SekhVet opening protocol \"%@\": %lu of %lu positions filled, grid %dx%d%@",
          [p objectForKey: @"name"], (unsigned long) open.count, (unsigned long) positions.count,
          useRows, useColumns, black ? @", Luecken schwarz" : @"");
    return YES;
}

// SekhVet Paket BS: nur wenn noch das Datenbankfenster Schluesselfenster ist und die Studie wirklich Viewer hat
+ (void) bringViewersToFrontForStudyUID:(NSString*) uid
{
    NSWindow *db = [[BrowserController currentBrowser] window];
    if( uid.length == 0 || [NSApp keyWindow] != db) return;
    ViewerController *first = nil;
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        if( [v windowWillClose] || [uid isEqualToString: [v studyInstanceUID]] == NO) continue;
        [[v window] orderFront: nil];
        if( first == nil) first = v;
    }
    if( first)
    {
        [[first window] makeKeyAndOrderFront: nil];
        NSLog( @"SekhVet opening: database window was still in front, viewers brought forward");
    }
}

+ (NSRect) cellRect:(int) index rows:(int) rows columns:(int) columns screen:(NSScreen*) screen
{
    NSRect base = [AppController usefullRectForScreen: screen];
    float w = base.size.width / (float) columns;
    float h = base.size.height / (float) rows;
    int col = index % columns;
    int row = index / columns;
    return NSMakeRect( base.origin.x + col * w,
                       base.origin.y + base.size.height - (row + 1) * h,
                       w, h);
}

+ (void) placeViewersOfStudy:(DicomStudy*) study cells:(NSArray*) cells series:(NSArray*) series rows:(int) rows columns:(int) columns screen:(NSScreen*) screen
{
    for( NSUInteger i = 0; i < series.count; i++)
    {
        NSString *uid = [[series objectAtIndex: i] valueForKey: @"seriesInstanceUID"];
        for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        {
            if( [[[v currentSeries] valueForKey: @"seriesInstanceUID"] isEqualToString: uid])
                [v setWindowFrame: [self cellRect: [[cells objectAtIndex: i] intValue] rows: rows columns: columns screen: screen] showWindow: YES animate: NO];
        }
    }
}

#pragma mark - Aufraeumen und "aus dem Bildschirm uebernehmen"


// Die Kacheln duerfen den letzten Viewer nicht ueberleben, sonst steht schwarze Flaeche
// auf einem sonst leeren Schreibtisch. Horos schliesst beim Bildschirmwechsel ohnehin alle
// Viewer (AppController applicationDidChangeScreenParameters:), darum haengt derselbe
// Aufraeumer auch daran.
+ (void) installObservers
{
    static BOOL done = NO;
    if( done) return;
    done = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver: self selector: @selector(viewerClosed:) name: OsirixCloseViewerNotification object: nil];
    [nc addObserver: self selector: @selector(screensChanged:) name: NSApplicationDidChangeScreenParametersNotification object: nil];
}

+ (void) viewerClosed:(NSNotification*) n
{
    // Nach dem Schliessen zaehlen, nicht davor: der Viewer haengt zum Zeitpunkt der
    // Nachricht noch in der Liste.
    [self performSelector: @selector(closeTilesIfNoViewers) withObject: nil afterDelay: 0.3];
}

+ (void) screensChanged:(NSNotification*) n { [SekhmetBlackTile closeAll]; }

+ (void) closeTilesIfNoViewers
{
    if( [[ViewerController getDisplayed2DViewers] count] == 0) [SekhmetBlackTile closeAll];
}

// "Take from screen": die offenen Viewer von links nach rechts (bei Gleichstand von oben
// nach unten) als Positionen uebernehmen. Stichwort ist der Serienname, damit man sieht,
// was gemeint war, und ihn danach von Hand kuerzen kann.
// Einen einzelnen Tag der ersten Datei einer Serie lesen (fuer "Take from screen").
+ (NSString*) tag:(NSString*) tagName forSeries:(DicomSeries*) series
{
    @try
    {
        NSArray *images = [series sortedImages];
        if( images.count == 0) return @"";
        NSString *path = [[images objectAtIndex: 0] valueForKey: @"completePath"];
        if( path.length == 0) return @"";
        DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
        NSString *v = [o attributeValueWithName: tagName];
        return v ? v : @"";
    }
    @catch (NSException *e) { }
    return @"";
}

// "Take from screen": die offenen Viewer von links nach rechts (bei Gleichstand von oben
// nach unten) als Positionen uebernehmen.
//
// WAS uebernommen wird, entscheidet die Modalitaet — und das ist der Punkt: der blosse
// Serienname taugt bei CT NICHT als Regel. "Schulter Ellbogen nativ 0,60 Br40 S2" trifft
// genau diese eine Untersuchung und nie wieder eine. Bei CT schreiben wir darum das,
// was sich wiederholt: die FENSTERREGEL (die aus dem Faltungskern kommt, Paket AE/AH) und
// die KONTRASTPHASE. Genau so sind die mitgelieferten CT-Vorgaben gebaut.
// Bei MR ist der Sequenzname dagegen stabil ("FSE T2 sag" steht so an jeder Studie des
// Geraets) — dort bleibt er das Stichwort.
+ (void) takeFromScreenIntoProtocol:(NSMutableDictionary*) protocol
{
    if( protocol == nil) return;
    NSArray *viewers = [[ViewerController getDisplayed2DViewers] sortedArrayUsingComparator: ^NSComparisonResult( id a, id b) {
        NSRect ra = [[a window] frame], rb = [[b window] frame];
        if( fabs( ra.origin.x - rb.origin.x) > 20) return ra.origin.x < rb.origin.x ? NSOrderedAscending : NSOrderedDescending;
        if( fabs( ra.origin.y - rb.origin.y) > 20) return ra.origin.y > rb.origin.y ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    if( viewers.count == 0)
    {
        NSLog( @"SekhVet opening protocol: \"Take from screen\" without open viewers — nothing to take");
        NSRunAlertPanel( NSLocalizedString( @"Take from screen", nil),
                        NSLocalizedString( @"No viewer is open. Open the study the way you want it first, then press Take from screen.", nil),
                        NSLocalizedString( @"OK", nil), nil, nil);
        return;
    }

    NSMutableArray *positions = [NSMutableArray array];
    NSMutableSet *columnsX = [NSMutableSet set], *rowsY = [NSMutableSet set];
    NSMutableString *bericht = [NSMutableString string];
    for( ViewerController *v in viewers)
    {
        DicomSeries *s = [v currentSeries];
        NSString *name = [self nameForSeries: s];
        NSString *modality = [[s valueForKey: @"modality"] uppercaseString];
        NSInteger contrast = [self contrastForSeries: s];

        NSString *keywords = @"", *window = @"";
        if( [modality isEqualToString: @"CT"])
        {
            NSDictionary *rule = [SekhmetWindowing ruleForModality: modality description: [self searchTextForSeries: s]];
            window = [rule objectForKey: @"name"];
            if( window == nil) window = @"";
        }
        else keywords = name ? name : @"";

        NSMutableDictionary *pos = [NSMutableDictionary dictionary];
        [pos setObject: keywords forKey: @"keywords"];
        [pos setObject: @"" forKey: @"without"];
        [pos setObject: window forKey: @"window"];
        [pos setObject: [NSNumber numberWithInteger: contrast] forKey: @"contrast"];
        [pos setObject: [NSNumber numberWithFloat: 0] forKey: @"wl"];
        [pos setObject: [NSNumber numberWithFloat: 0] forKey: @"ww"];
        [positions addObject: pos];
        [bericht appendFormat: @"\n    \"%@\" -> Fenster \"%@\" Stichwort \"%@\" Kontrast %ld", name, window, keywords, (long) contrast];

        [columnsX addObject: [NSNumber numberWithInt: (int) round( [[v window] frame].origin.x / 50.0)]];
        [rowsY addObject: [NSNumber numberWithInt: (int) round( [[v window] frame].origin.y / 50.0)]];
    }
    [protocol setObject: positions forKey: @"positions"];
    [protocol setObject: [NSNumber numberWithInt: MAX( 1, (int) rowsY.count)] forKey: @"rows"];
    [protocol setObject: [NSNumber numberWithInt: MAX( 1, (int) columnsX.count)] forKey: @"columns"];

    DicomSeries *first = [[viewers objectAtIndex: 0] currentSeries];
    NSString *modality = [[first valueForKey: @"modality"] uppercaseString];
    if( modality.length) [protocol setObject: modality forKey: @"modality"];

    // Region nur ergaenzen, nicht ueberschreiben: eine getippte Stichwortliste ist mehr wert
    // als ein einzelner Tag. Bei CT bleibt sie leer — ein CT-Protokoll gilt in der Praxis fuer
    // alle Regionen, die Fensterregel trennt.
    NSString *region = [protocol objectForKey: @"region"];
    if( region.length == 0 && ![modality isEqualToString: @"CT"])
    {
        NSString *body = [self tag: @"BodyPartExamined" forSeries: first];
        if( body.length) [protocol setObject: body forKey: @"region"];
    }

    NSLog( @"SekhVet opening protocol \"%@\" taken from screen: %lu positions, %@x%@, modality %@, region \"%@\"%@",
          [protocol objectForKey: @"name"], (unsigned long) positions.count,
          [protocol objectForKey: @"rows"], [protocol objectForKey: @"columns"], modality,
          [protocol objectForKey: @"region"], bericht);
}

#pragma mark - Testhaken

#if SEKHVET_TESTHAKEN
// Selbsttest ohne Datenbank: die Kontrasterkennung gegen echte Seriennamen aus dem Praxis-
// Bestand (Erhebung 15.09.2026). Positivkontrolle UND Knockout in einem — "Topogramm" und
// "CSPINE stitch" muessen UNENTSCHIEDEN bleiben, sonst zieht ein CT-Slot ein Topogramm.
+ (NSString*) debugSelfTest
{
    NSArray *cases = [NSArray arrayWithObjects:
        @"Wirbelsäule nativ 0,80 Br40 S2", @"1",
        @"Wirbelsäule KM 0,80 Br64",       @"2",
        @"WT nativ Vol 0.5  FC26",         @"1",
        @"KF KM Vol 0.5  BONE",            @"2",
        @"CCT nativ 0,80 Hr40 S2",         @"1",
        @"Head N",                         @"1",
        @"Head C",                         @"2",
        @"Thorax Bone N",                  @"1",
        @"Head Bone Plus N",               @"1",
        @"Body 1.0 CE FC08",               @"2",
        @"HKCL SE T1 tra HawkAI",          @"0",
        @"HKCL SE T1 tra post KM HawkAI",  @"2",
        @"HKCL FSE T2 sag HawkAI",         @"0",
        @"Topogramm 0,70 Tr20 sag",        @"0",
        @"CSPINE stitch",                  @"0",
        @"C1-Th3 N",                       @"1",
        nil];
    int ok = 0, bad = 0;
    NSMutableString *fails = [NSMutableString string];
    for( NSUInteger i = 0; i + 1 < cases.count; i += 2)
    {
        NSString *name = [cases objectAtIndex: i];
        NSInteger want = [[cases objectAtIndex: i+1] integerValue];
        NSInteger got = [self contrastForName: name];
        if( got == want) ok++;
        else { bad++; [fails appendFormat: @"  \"%@\": erwartet %ld, bekommen %ld\n", name, (long) want, (long) got]; }
    }
    NSString *contrast = [NSString stringWithFormat: @"Kontrasterkennung %d/%d richtig%@", ok, ok + bad,
                          bad ? [NSString stringWithFormat: @"\n%@", fails] : @""];

    // SekhVet Paket AY: Projektion und Seitenwahl am Roentgenbestand der Praxis (16.09.2026).
    // Knockout: ein Einzelwort ist keine Projektion, gleiche Projektionen ordnen nicht.
    NSArray *proj = [NSArray arrayWithObjects:
        @"",   @"Thorax > vd",        @"VD",
        @"LL", @"Thorax > links lat", @"LL",
        @"",   @"Katzogramm LL",      @"LL",
        @"",   @"Abdomen vd",         @"VD",
        @" lat ", @"",                @"LAT",
        @"",   @"IIP_MWL_SCU",        @"",
        @"",   @"",                   @"",
        nil];
    int pok = 0, pbad = 0;
    NSMutableString *pfails = [NSMutableString string];
    for( NSUInteger i = 0; i + 2 < proj.count; i += 3)
    {
        NSString *got = [self projectionForViewPosition: [proj objectAtIndex: i] name: [proj objectAtIndex: i+1]];
        if( [got isEqualToString: [proj objectAtIndex: i+2]]) pok++;
        else { pbad++; [pfails appendFormat: @"  Projektion \"%@\"/\"%@\": erwartet \"%@\", bekommen \"%@\"\n", [proj objectAtIndex: i], [proj objectAtIndex: i+1], [proj objectAtIndex: i+2], got]; }
    }
    NSArray *order = [NSArray arrayWithObjects:
        @"VD",  @"LL",  @"0", @"1",   // VD links, LL rechts (Vorgabe)
        @"LL",  @"VD",  @"0", @"2",
        @"VD",  @"LL",  @"1", @"2",   // Einstellung: seitliche links
        @"LAT", @"VD",  @"0", @"2",
        @"DV",  @"ML",  @"0", @"1",
        @"VD",  @"DV",  @"0", @"1",   // keine seitlich: Serienreihenfolge
        @"LL",  @"ML",  @"0", @"1",   // beide seitlich: Serienreihenfolge
        @"DV",  @"DV",  @"0", @"0",   // gleiche Projektion: keine Regel
        @"",    @"LL",  @"0", @"0",   // unbekannt: keine Regel
        nil];
    for( NSUInteger i = 0; i + 3 < order.count; i += 4)
    {
        NSInteger got = [self twoViewOrderForProjection: [order objectAtIndex: i] projection: [order objectAtIndex: i+1] lateralLeft: [[order objectAtIndex: i+2] boolValue]];
        if( got == [[order objectAtIndex: i+3] integerValue]) pok++;
        else { pbad++; [pfails appendFormat: @"  Reihenfolge %@/%@ (links=%@): erwartet %@, bekommen %ld\n", [order objectAtIndex: i], [order objectAtIndex: i+1], [order objectAtIndex: i+2], [order objectAtIndex: i+3], (long) got]; }
    }
    return [NSString stringWithFormat: @"%@; Zwei-Ebenen %d/%d richtig%@", contrast, pok, pok + pbad,
            pbad ? [NSString stringWithFormat: @"\n%@", pfails] : @""];
}

// SEKHVET_OPENING_TEST="<Teil der PatientID oder des Namens>": Studie in der lokalen
// Datenbank suchen, Protokollwahl und Belegung protokollieren und die Studie oeffnen.
+ (void) debugOpeningFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_OPENING_TEST");
    if( env == NULL) return;
    NSString *needle = [NSString stringWithUTF8String: env];

    NSLog( @"SekhVet Oeffnungstest: Selbsttest %@", [self debugSelfTest]);

    DicomDatabase *db = [DicomDatabase activeLocalDatabase];
    NSArray *studies = nil;
    @try { studies = [db objectsForEntity: [db studyEntity] predicate: [NSPredicate predicateWithValue: YES]]; }
    @catch (NSException *e) { NSLog( @"SekhVet Oeffnungstest: keine Datenbank (%@)", e); return; }

    for( DicomStudy *s in studies)
    {
        NSString *pid = [s valueForKey: @"patientID"], *name = [s valueForKey: @"name"];
        if( [pid rangeOfString: needle options: NSCaseInsensitiveSearch].location == NSNotFound &&
            [name rangeOfString: needle options: NSCaseInsensitiveSearch].location == NSNotFound) continue;

        NSArray *pair = [self twoViewPairForStudy: s];   // SekhVet Paket AY
        if( pair)
        {
            NSLog( @"SekhVet Oeffnungstest: Studie \"%@\" (%@, %@) -> Zwei-Ebenen, links \"%@\", rechts \"%@\"", name, pid,
                  [s valueForKey: @"modality"], [self nameForSeries: [pair objectAtIndex: 0]], [self nameForSeries: [pair objectAtIndex: 1]]);
            [self applyToStudy: s];
            [self performSelector: @selector(debugOpeningLog) withObject: nil afterDelay: 8 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
            return;
        }
        NSDictionary *p = [self protocolForStudy: s];
        NSLog( @"SekhVet Oeffnungstest: Studie \"%@\" (%@, %@) -> Protokoll %@", name, pid,
              [s valueForKey: @"modality"], p ? [p objectForKey: @"name"] : @"KEINES");
        if( p == nil) continue;

        // Erst die Kandidaten zeigen, dann die Zuordnung: sonst sieht man nur "leer"
        // und weiss nicht, ob der Suchtext, die Fensterregel oder der Kontrast schuld ist.
        NSArray *pool = [s imageSeriesContainingPixels: YES];
        if( pool.count == 0) pool = [s imageSeries];
        NSLog( @"SekhVet Oeffnungstest:   %lu Kandidatenserie(n)", (unsigned long) pool.count);
        for( DicomSeries *cand in pool)
        {
            NSString *text = [self searchTextForSeries: cand];
            NSDictionary *rule = [SekhmetWindowing ruleForModality: [[cand valueForKey: @"modality"] uppercaseString] description: text];
            NSLog( @"SekhVet Oeffnungstest:     \"%@\" | Suchtext \"%@\" | Fenster \"%@\" | Kontrast %ld",
                  [self nameForSeries: cand], text,
                  [rule objectForKey: @"name"], (long) [self contrastForSeries: cand]);
        }

        NSArray *chosen = [self seriesForProtocol: p study: s];
        for( NSUInteger i = 0; i < chosen.count; i++)
        {
            id hit = [chosen objectAtIndex: i];
            NSDictionary *pos = [[p objectForKey: @"positions"] objectAtIndex: i];
            NSLog( @"SekhVet Oeffnungstest:   Position %lu [kw=\"%@\" ohne=\"%@\" fenster=\"%@\" kontrast=%@] -> %@",
                  (unsigned long) i + 1, [pos objectForKey: @"keywords"], [pos objectForKey: @"without"],
                  [pos objectForKey: @"window"], [pos objectForKey: @"contrast"],
                  hit == [NSNull null] ? @"— leer —" : [self nameForSeries: hit]);
        }
        NSLog( @"SekhVet Oeffnungstest: oeffne jetzt …");
        [self applyToStudy: s];
        [self performSelector: @selector(debugOpeningLog) withObject: nil afterDelay: 8 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
        [self performSelector: @selector(debugTakeFromScreen) withObject: nil afterDelay: 12 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
        return;
    }
    NSLog( @"SekhVet Oeffnungstest: keine Studie zu \"%@\" gefunden", needle);
}

// SEKHVET_OPENING_TAKE_TEST=1: nach dem Oeffnen "Take from screen" auf ein Wegwerf-Protokoll
// anwenden und protokollieren, was es uebernehmen wuerde — genau der Knopf, den der Anwender drueckt.
+ (void) debugTakeFromScreen
{
    if( sekhvetTesthaken( "SEKHVET_OPENING_TAKE_TEST") == NULL) return;
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject: @"Testprotokoll" forKey: @"name"];
    [p setObject: @"" forKey: @"modality"];
    [p setObject: @"" forKey: @"region"];
    [self takeFromScreenIntoProtocol: p];
}

+ (void) debugOpeningLog
{
    NSArray *viewers = [ViewerController getDisplayed2DViewers];
    NSLog( @"SekhVet Oeffnungstest: %lu Viewer offen", (unsigned long) viewers.count);
    for( ViewerController *v in viewers)
    {
        NSRect f = [[v window] frame];
        NSLog( @"SekhVet Oeffnungstest:   \"%@\" bei x=%.0f y=%.0f %.0fx%.0f  WL/WW %.0f/%.0f",
              [self nameForSeries: [v currentSeries]], f.origin.x, f.origin.y, f.size.width, f.size.height,
              [[v imageView] curWL], [[v imageView] curWW]);
    }
    for( NSWindow *w in sekhmetBlackTiles)
    {
        NSRect f = [w frame];
        NSLog( @"SekhVet Oeffnungstest:   schwarze Kachel bei x=%.0f y=%.0f %.0fx%.0f", f.origin.x, f.origin.y, f.size.width, f.size.height);
    }
}
#endif // SEKHVET_TESTHAKEN

@end


#pragma mark - Schwarze Kacheln

// Randloses schwarzes Fenster ueber einer leeren Rasterzelle. Kein Viewer, kein DICOM:
// es verhindert nur, dass in der Luecke der Schreibtisch durchscheint. Es schluckt Klicks
// (kein Durchklicken — sonst holte ein Fehlklick den Finder nach vorn, also genau das,
// was die Kachel verdecken soll).

@implementation SekhmetBlackTile

- (BOOL) canBecomeKeyWindow { return NO; }
- (BOOL) canBecomeMainWindow { return NO; }

+ (SekhmetBlackTile*) tileWithFrame:(NSRect) frame
{
    SekhmetBlackTile *w = [[SekhmetBlackTile alloc] initWithContentRect: frame
                                                             styleMask: NSWindowStyleMaskBorderless
                                                               backing: NSBackingStoreBuffered
                                                                 defer: NO];
    [w setBackgroundColor: [NSColor blackColor]];
    [w setOpaque: YES];
    [w setHasShadow: NO];
    [w setReleasedWhenClosed: NO];
    [w setExcludedFromWindowsMenu: YES];
    [w setLevel: NSNormalWindowLevel];
    [w setCollectionBehavior: NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];
    return [w autorelease];
}

+ (void) showOnFreeCellsForRows:(int) rows columns:(int) columns taken:(NSArray*) taken screen:(NSScreen*) screen
{
    [self closeAll];
    if( rows < 1 || columns < 1 || screen == nil) return;
    if( sekhmetBlackTiles == nil) sekhmetBlackTiles = [[NSMutableArray alloc] init];

    NSMutableSet *used = [NSMutableSet set];
    for( NSNumber *n in taken) [used addObject: n];

    for( int i = 0; i < rows * columns; i++)
    {
        if( [used containsObject: [NSNumber numberWithInt: i]]) continue;
        SekhmetBlackTile *w = [self tileWithFrame: [SekhmetOpening cellRect: i rows: rows columns: columns screen: screen]];
        [w orderBack: nil];
        [sekhmetBlackTiles addObject: w];
    }
    if( sekhmetBlackTiles.count)
        NSLog( @"SekhVet opening protocol: %lu black tile(s) on empty cells", (unsigned long) sekhmetBlackTiles.count);
}

+ (void) closeAll
{
    for( NSWindow *w in sekhmetBlackTiles) [w close];
    [sekhmetBlackTiles removeAllObjects];
}

@end

#pragma mark -

static SekhmetOpeningPanel *sekhmetOpeningPanel = nil;

@implementation SekhmetOpeningPanel

+ (SekhmetOpeningPanel*) shared
{
    if( sekhmetOpeningPanel == nil) sekhmetOpeningPanel = [[SekhmetOpeningPanel alloc] init];
    return sekhmetOpeningPanel;
}

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 900, 560)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Opening Protocols", nil)];
    [w setReleasedWhenClosed: NO];
    self = [super initWithWindow: w];
    if( self)
    {
        protocols = [[NSMutableArray alloc] init];
        [self buildUI];
        [self loadFromDefaults];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [protocols release];
    [super dealloc];
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: YES];
    [super showWindow: sender];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text];
    [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: 13] : [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSButton*) button:(NSString*) title frame:(NSRect) r action:(SEL) sel
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setTitle: title];
    [b setBezelStyle: NSBezelStyleRounded];
    [b setTarget: self]; [b setAction: sel];
    [b setFont: [NSFont systemFontOfSize: 12]];
    return b;
}

- (void) buildUI
{
    // Festes Raster statt fortlaufender y-Rechnung: links die Protokolle, rechts das
    // gewaehlte Protokoll, unten die globalen Schalter.
    NSView *cv = [[self window] contentView];

    NSTextField *hint = [self label: NSLocalizedString( @"Double-clicking a study in the database opens it by the first protocol whose modality and region keywords match. Positions are left to right, then next row; each position takes the first series that fits and no series is used twice. Empty field = any. Window = name of a rule from Vet Tools > Window Presets. WL/WW = 0 means the window preset decides.", nil)
                              frame: NSMakeRect( 20, 512, 860, 36) bold: NO];
    [hint setFont: [NSFont systemFontOfSize: 11]];
    [[hint cell] setWraps: YES];
    [cv addSubview: hint];

    // Links: Protokolle
    [cv addSubview: [self label: NSLocalizedString( @"Protocols", nil) frame: NSMakeRect( 20, 488, 200, 18) bold: YES]];
    NSScrollView *sv1 = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, 190, 250, 290)] autorelease];
    protocolTable = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 250, 290)] autorelease];
    NSArray *cols1 = [NSArray arrayWithObjects: @"Name", @"Mod", nil];
    NSArray *widths1 = [NSArray arrayWithObjects: @"175", @"45", nil];
    for( NSUInteger i = 0; i < cols1.count; i++)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [cols1 objectAtIndex: i]] autorelease];
        [[c headerCell] setStringValue: [cols1 objectAtIndex: i]];
        [c setWidth: [[widths1 objectAtIndex: i] floatValue]];
        [c setEditable: YES];
        [protocolTable addTableColumn: c];
    }
    [protocolTable setDataSource: self]; [protocolTable setDelegate: self];
    [protocolTable setUsesAlternatingRowBackgroundColors: YES];
    [sv1 setDocumentView: protocolTable];
    [sv1 setHasVerticalScroller: YES];
    [sv1 setBorderType: NSBezelBorder];
    [cv addSubview: sv1];
    [cv addSubview: [self button: @"+" frame: NSMakeRect(  20, 158, 40, 26) action: @selector(addProtocol:)]];
    [cv addSubview: [self button: @"\u2212" frame: NSMakeRect(  65, 158, 40, 26) action: @selector(removeProtocol:)]];
    [cv addSubview: [self button: @"\u2191" frame: NSMakeRect( 110, 158, 40, 26) action: @selector(moveProtocolUp:)]];
    [cv addSubview: [self button: @"\u2193" frame: NSMakeRect( 155, 158, 40, 26) action: @selector(moveProtocolDown:)]];

    // Rechts: das gewaehlte Protokoll
    [cv addSubview: [self label: NSLocalizedString( @"Region keywords (series name, protocol name, body part) — empty = any", nil) frame: NSMakeRect( 300, 488, 560, 18) bold: NO]];
    regionField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 300, 464, 560, 22)] autorelease];
    [regionField setTarget: self]; [regionField setAction: @selector(regionChanged:)];
    [cv addSubview: regionField];

    [cv addSubview: [self label: NSLocalizedString( @"Rows", nil) frame: NSMakeRect( 300, 438, 50, 18) bold: NO]];
    rowsField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 300, 414, 50, 22)] autorelease];
    [rowsField setTarget: self]; [rowsField setAction: @selector(rowsChanged:)];
    [cv addSubview: rowsField];

    [cv addSubview: [self label: NSLocalizedString( @"Columns", nil) frame: NSMakeRect( 365, 438, 70, 18) bold: NO]];
    columnsField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 365, 414, 50, 22)] autorelease];
    [columnsField setTarget: self]; [columnsField setAction: @selector(columnsChanged:)];
    [cv addSubview: columnsField];

    blackTilesButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 440, 417, 420, 18)] autorelease];
    [blackTilesButton setButtonType: NSButtonTypeSwitch];
    [blackTilesButton setTitle: NSLocalizedString( @"Leave gaps as a black tile (one screen only)", nil)];
    [blackTilesButton setFont: [NSFont systemFontOfSize: 12]];
    [blackTilesButton setTarget: self]; [blackTilesButton setAction: @selector(blackTilesChanged:)];
    [cv addSubview: blackTilesButton];

    [cv addSubview: [self label: NSLocalizedString( @"Positions — left to right, then next row", nil) frame: NSMakeRect( 300, 388, 400, 18) bold: YES]];
    NSScrollView *sv2 = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 300, 190, 560, 192)] autorelease];
    positionTable = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 560, 192)] autorelease];
    NSArray *cols2 = [NSArray arrayWithObjects: @"Keywords", @"without", @"Window", @"Contrast", @"WL", @"WW", nil];
    NSArray *widths2 = [NSArray arrayWithObjects: @"120", @"85", @"85", @"70", @"45", @"45", nil];
    for( NSUInteger i = 0; i < cols2.count; i++)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [cols2 objectAtIndex: i]] autorelease];
        [[c headerCell] setStringValue: [cols2 objectAtIndex: i]];
        [c setWidth: [[widths2 objectAtIndex: i] floatValue]];
        [c setEditable: YES];
        if( [[cols2 objectAtIndex: i] isEqualToString: @"Contrast"])
        {
            NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
            [cell setBordered: NO];
            [cell addItemsWithTitles: [NSArray arrayWithObjects: @"any", @"native", @"contrast", nil]];
            [cell setFont: [NSFont systemFontOfSize: 11]];
            [c setDataCell: cell];
        }
        [positionTable addTableColumn: c];
    }
    [positionTable setDataSource: self]; [positionTable setDelegate: self];
    [positionTable setUsesAlternatingRowBackgroundColors: YES];
    // Ohne das dehnt die Tabelle die Spalten selbst und schiebt die letzte (WW) aus dem Bild.
    [positionTable setColumnAutoresizingStyle: NSTableViewNoColumnAutoresizing];
    [sv2 setDocumentView: positionTable];
    [sv2 setHasVerticalScroller: YES];
    [sv2 setHasHorizontalScroller: YES];
    [sv2 setBorderType: NSBezelBorder];
    [cv addSubview: sv2];
    [cv addSubview: [self button: @"+" frame: NSMakeRect( 300, 158, 40, 26) action: @selector(addPosition:)]];
    [cv addSubview: [self button: @"\u2212" frame: NSMakeRect( 345, 158, 40, 26) action: @selector(removePosition:)]];
    [cv addSubview: [self button: @"\u2191" frame: NSMakeRect( 390, 158, 40, 26) action: @selector(movePositionUp:)]];
    [cv addSubview: [self button: @"\u2193" frame: NSMakeRect( 435, 158, 40, 26) action: @selector(movePositionDown:)]];

    // Unten: global
    enabledButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, 122, 400, 18)] autorelease];
    [enabledButton setButtonType: NSButtonTypeSwitch];
    [enabledButton setTitle: NSLocalizedString( @"Use opening protocols when a study is opened from the database", nil)];
    [enabledButton setFont: [NSFont systemFontOfSize: 12]];
    [enabledButton setTarget: self]; [enabledButton setAction: @selector(enabledChanged:)];
    [cv addSubview: enabledButton];

    [cv addSubview: [self label: NSLocalizedString( @"On screens narrower than", nil) frame: NSMakeRect( 20, 90, 170, 18) bold: NO]];
    smallWidthField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 195, 86, 55, 22)] autorelease];
    [smallWidthField setTarget: self]; [smallWidthField setAction: @selector(smallWidthChanged:)];
    [cv addSubview: smallWidthField];
    [cv addSubview: [self label: NSLocalizedString( @"px, open at most", nil) frame: NSMakeRect( 258, 90, 110, 18) bold: NO]];
    smallMaxField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 372, 86, 55, 22)] autorelease];
    [smallMaxField setTarget: self]; [smallMaxField setAction: @selector(smallMaxChanged:)];
    [cv addSubview: smallMaxField];
    [cv addSubview: [self label: NSLocalizedString( @"viewers", nil) frame: NSMakeRect( 435, 90, 100, 18) bold: NO]];

    // SekhVet Paket AY: Roentgen-Zweiebenen
    twoViewButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 440, 122, 330, 18)] autorelease];
    [twoViewButton setButtonType: NSButtonTypeSwitch];
    [twoViewButton setTitle: NSLocalizedString( @"X-ray: two views of one region side by side, lateral on the", nil)];
    [twoViewButton setFont: [NSFont systemFontOfSize: 12]];
    [twoViewButton setTarget: self]; [twoViewButton setAction: @selector(twoViewChanged:)];
    [cv addSubview: twoViewButton];
    lateralSidePopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 775, 117, 90, 26) pullsDown: NO] autorelease];
    [lateralSidePopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"right", nil), NSLocalizedString( @"left", nil), nil]];
    [lateralSidePopup setTarget: self]; [lateralSidePopup setAction: @selector(lateralSideChanged:)];
    [cv addSubview: lateralSidePopup];

    [cv addSubview: [self button: NSLocalizedString( @"Take from screen", nil) frame: NSMakeRect( 20, 30, 180, 30) action: @selector(takeFromScreen:)]];
    [cv addSubview: [self button: NSLocalizedString( @"Reset to defaults", nil) frame: NSMakeRect( 210, 30, 180, 30) action: @selector(resetToDefaults:)]];
}

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [enabledButton setState: [d boolForKey: SekhmetOpeningEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff];

    float smallWidth = [d floatForKey: SekhmetOpeningSmallWidthKey];
    [smallWidthField setStringValue: [NSString stringWithFormat: @"%.0f", smallWidth]];

    int smallMax = [d integerForKey: SekhmetOpeningSmallMaxKey];
    [smallMaxField setStringValue: [NSString stringWithFormat: @"%d", smallMax]];

    [twoViewButton setState: [d boolForKey: SekhmetTwoViewEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [lateralSidePopup selectItemAtIndex: [d boolForKey: SekhmetTwoViewLateralLeftKey] ? 1 : 0];

    [protocols removeAllObjects];
    for( NSDictionary *p in [d arrayForKey: SekhmetOpeningProtocolsKey])
    {
        NSMutableDictionary *mp = [[p mutableCopy] autorelease];
        NSMutableArray *positions = [NSMutableArray array];
        for( NSDictionary *pos in [mp objectForKey: @"positions"])
        {
            [positions addObject: [[pos mutableCopy] autorelease]];
        }
        [mp setObject: positions forKey: @"positions"];
        [protocols addObject: mp];
    }
    NSInteger vorher = [protocolTable selectedRow];   // SekhVet Paket AV: Auswahl ueberlebt das Neuladen
    [protocolTable reloadData];
    // Ohne Auswahl bliebe die rechte Haelfte beim Oeffnen leer und man haelt das Panel
    // fuer kaputt: erstes Protokoll waehlen und die Felder fuellen. Nach "Take from screen"
    // sprang die Auswahl dadurch aber auf das ERSTE Protokoll zurueck — es sah aus, als waere
    // nichts uebernommen worden, obwohl geschrieben war (Rueckmeldung 15.09.).
    if( protocols.count)
    {
        NSInteger ziel = (vorher >= 0 && vorher < (NSInteger) protocols.count) ? vorher : 0;
        [protocolTable selectRowIndexes: [NSIndexSet indexSetWithIndex: ziel] byExtendingSelection: NO];
        [self tableViewSelectionDidChange: [NSNotification notificationWithName: NSTableViewSelectionDidChangeNotification object: protocolTable]];
    }
    [positionTable reloadData];
}

- (void) save
{
    [[NSUserDefaults standardUserDefaults] setObject: protocols forKey: SekhmetOpeningProtocolsKey];
}

- (NSMutableDictionary*) selectedProtocol
{
    NSInteger r = [protocolTable selectedRow];
    if( r < 0 || r >= (NSInteger) protocols.count) return nil;
    return [protocols objectAtIndex: r];
}

- (IBAction) addProtocol:(id) sender
{
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject: @"New Protocol" forKey: @"name"];
    [p setObject: @"" forKey: @"modality"];
    [p setObject: @"" forKey: @"region"];
    [p setObject: @1 forKey: @"rows"];
    [p setObject: @1 forKey: @"columns"];
    [p setObject: @NO forKey: @"blackTiles"];
    [p setObject: [NSMutableArray array] forKey: @"positions"];
    [protocols addObject: p];
    [self save]; [protocolTable reloadData];
    [protocolTable selectRowIndexes: [NSIndexSet indexSetWithIndex: protocols.count - 1] byExtendingSelection: NO];
}

- (IBAction) removeProtocol:(id) sender
{
    NSInteger r = [protocolTable selectedRow];
    if( r >= 0 && r < (NSInteger) protocols.count)
    {
        [protocols removeObjectAtIndex: r];
        [self save]; [protocolTable reloadData];
        [positionTable reloadData];
    }
}

- (void) moveProtocol:(NSInteger) delta
{
    NSInteger r = [protocolTable selectedRow], n = r + delta;
    if( r < 0 || n < 0 || n >= (NSInteger) protocols.count) return;
    [protocols exchangeObjectAtIndex: r withObjectAtIndex: n];
    [self save]; [protocolTable reloadData];
    [protocolTable selectRowIndexes: [NSIndexSet indexSetWithIndex: n] byExtendingSelection: NO];
}

- (IBAction) moveProtocolUp:(id) sender { [self moveProtocol: -1]; }
- (IBAction) moveProtocolDown:(id) sender { [self moveProtocol: 1]; }

- (IBAction) regionChanged:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    [p setObject: [regionField stringValue] forKey: @"region"];
    [self save];
}

- (IBAction) rowsChanged:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    [p setObject: [NSNumber numberWithInt: [[rowsField stringValue] intValue]] forKey: @"rows"];
    [self save];
}

- (IBAction) columnsChanged:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    [p setObject: [NSNumber numberWithInt: [[columnsField stringValue] intValue]] forKey: @"columns"];
    [self save];
}

- (IBAction) blackTilesChanged:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    [p setObject: [NSNumber numberWithBool: ([blackTilesButton state] == NSControlStateValueOn)] forKey: @"blackTiles"];
    [self save];
}

- (IBAction) addPosition:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    NSMutableArray *positions = [p objectForKey: @"positions"];
    [positions addObject: [NSMutableDictionary dictionary]];
    [self save]; [positionTable reloadData];
    [positionTable editColumn: 0 row: positions.count - 1 withEvent: nil select: YES];
}

- (IBAction) removePosition:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    NSMutableArray *positions = [p objectForKey: @"positions"];
    NSInteger r = [positionTable selectedRow];
    if( r >= 0 && r < (NSInteger) positions.count)
    {
        [positions removeObjectAtIndex: r];
        [self save]; [positionTable reloadData];
    }
}

- (void) movePosition:(NSInteger) delta
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    NSMutableArray *positions = [p objectForKey: @"positions"];
    NSInteger r = [positionTable selectedRow], n = r + delta;
    if( r < 0 || n < 0 || n >= (NSInteger) positions.count) return;
    [positions exchangeObjectAtIndex: r withObjectAtIndex: n];
    [self save]; [positionTable reloadData];
    [positionTable selectRowIndexes: [NSIndexSet indexSetWithIndex: n] byExtendingSelection: NO];
}

- (IBAction) movePositionUp:(id) sender { [self movePosition: -1]; }
- (IBAction) movePositionDown:(id) sender { [self movePosition: 1]; }

- (IBAction) enabledChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([enabledButton state] == NSControlStateValueOn) forKey: SekhmetOpeningEnabledKey];
}

- (IBAction) twoViewChanged:(id) sender   // SekhVet Paket AY
{
    [[NSUserDefaults standardUserDefaults] setBool: ([twoViewButton state] == NSControlStateValueOn) forKey: SekhmetTwoViewEnabledKey];
}

- (IBAction) lateralSideChanged:(id) sender   // SekhVet Paket AY
{
    [[NSUserDefaults standardUserDefaults] setBool: ([lateralSidePopup indexOfSelectedItem] == 1) forKey: SekhmetTwoViewLateralLeftKey];
}

- (IBAction) smallWidthChanged:(id) sender
{
    float f = [[smallWidthField stringValue] floatValue];
    [[NSUserDefaults standardUserDefaults] setFloat: f forKey: SekhmetOpeningSmallWidthKey];
}

- (IBAction) smallMaxChanged:(id) sender
{
    int i = [[smallMaxField stringValue] intValue];
    [[NSUserDefaults standardUserDefaults] setInteger: i forKey: SekhmetOpeningSmallMaxKey];
}

- (IBAction) takeFromScreen:(id) sender
{
    NSMutableDictionary *p = [self selectedProtocol];
    if( p == nil) return;
    [SekhmetOpening takeFromScreenIntoProtocol: p];
    [self save];              // erst sichern, dann neu laden — sonst holt loadFromDefaults die alte Fassung zurueck
    [self loadFromDefaults];
}

- (IBAction) resetToDefaults:(id) sender
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: SekhmetOpeningProtocolsKey];
    [self loadFromDefaults];
}

- (void) tableViewSelectionDidChange:(NSNotification*) notification
{
    if( notification.object == protocolTable)
    {
        NSMutableDictionary *p = [self selectedProtocol];
        if( p == nil)
        {
            [regionField setStringValue: @""];
            [rowsField setStringValue: @"1"];
            [columnsField setStringValue: @"1"];
            [blackTilesButton setState: NSControlStateValueOff];
        }
        else
        {
            [regionField setStringValue: [p objectForKey: @"region"]];
            [rowsField setStringValue: [NSString stringWithFormat: @"%d", [[p objectForKey: @"rows"] intValue]]];
            [columnsField setStringValue: [NSString stringWithFormat: @"%d", [[p objectForKey: @"columns"] intValue]]];
            [blackTilesButton setState: [[p objectForKey: @"blackTiles"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
        }
        [positionTable reloadData];
    }
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv
{
    if( tv == protocolTable)
        return protocols.count;
    else
    {
        NSMutableDictionary *p = [self selectedProtocol];
        if( p == nil) return 0;
        return [[p objectForKey: @"positions"] count];
    }
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( tv == protocolTable)
    {
        NSDictionary *p = [protocols objectAtIndex: row];
        NSString *ident = [col identifier];
        if( [ident isEqualToString: @"Name"]) return [p objectForKey: @"name"];
        if( [ident isEqualToString: @"Mod"]) return [p objectForKey: @"modality"];
        return nil;
    }
    else
    {
        NSMutableDictionary *p = [self selectedProtocol];
        if( p == nil) return nil;
        NSArray *positions = [p objectForKey: @"positions"];
        NSDictionary *pos = [positions objectAtIndex: row];
        NSString *ident = [col identifier];
        if( [ident isEqualToString: @"Keywords"]) return [pos objectForKey: @"keywords"];
        if( [ident isEqualToString: @"without"]) return [pos objectForKey: @"without"];
        if( [ident isEqualToString: @"Window"]) return [pos objectForKey: @"window"];
        if( [ident isEqualToString: @"Contrast"])
            return [NSNumber numberWithInteger: [[pos objectForKey: @"contrast"] integerValue]];
        if( [ident isEqualToString: @"WL"]) return [NSString stringWithFormat: @"%.0f", [[pos objectForKey: @"wl"] floatValue]];
        if( [ident isEqualToString: @"WW"]) return [NSString stringWithFormat: @"%.0f", [[pos objectForKey: @"ww"] floatValue]];
        return nil;
    }
}

- (void) tableView:(NSTableView*) tv setObjectValue:(id) value forTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( tv == protocolTable)
    {
        NSMutableDictionary *p = [protocols objectAtIndex: row];
        NSString *ident = [col identifier];
        if( value == nil) value = @"";
        if( [ident isEqualToString: @"Name"]) [p setObject: [value description] forKey: @"name"];
        else if( [ident isEqualToString: @"Mod"]) [p setObject: [[value description] uppercaseString] forKey: @"modality"];
        [self save];
    }
    else
    {
        NSMutableDictionary *p = [self selectedProtocol];
        if( p == nil) return;
        NSMutableArray *positions = [p objectForKey: @"positions"];
        NSMutableDictionary *pos = [positions objectAtIndex: row];
        NSString *ident = [col identifier];
        if( value == nil) value = @"";
        if( [ident isEqualToString: @"Keywords"]) [pos setObject: [value description] forKey: @"keywords"];
        else if( [ident isEqualToString: @"without"]) [pos setObject: [value description] forKey: @"without"];
        else if( [ident isEqualToString: @"Window"]) [pos setObject: [value description] forKey: @"window"];
        else if( [ident isEqualToString: @"Contrast"])
        {
            NSInteger contrast = [value integerValue];   // NSPopUpButtonCell liefert den Index
            if( contrast < SekhmetContrastAny || contrast > SekhmetContrastAgent) contrast = SekhmetContrastAny;
            [pos setObject: [NSNumber numberWithInteger: contrast] forKey: @"contrast"];
        }
        else if( [ident isEqualToString: @"WL"]) [pos setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"wl"];
        else if( [ident isEqualToString: @"WW"]) [pos setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"ww"];
        [self save];
    }
}

@end
