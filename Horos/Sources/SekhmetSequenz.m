/*=========================================================================
 SekhVet Paket CA — Sequenz-Plaketten in der Serienliste. Siehe Header.
 ============================================================================*/

#import "SekhmetSequenz.h"

// Grenze = kein Buchstabe/keine Ziffer davor bzw. danach — "T1" in "SE T1 tra",
// aber nicht in "T10" oder "ST1R". Klassen ausdruecklich mit A-Z: ob ICU bei
// CASE_INSENSITIVE eine verneinte Klasse vor oder nach der Faltung bildet, soll
// hier keine Rolle spielen.
static NSRegularExpression* wort( NSString *kern)
{
    NSString *muster = [NSString stringWithFormat: @"(?:^|[^A-Za-z0-9])(?:%@)(?![A-Za-z0-9])", kern];
    return [[NSRegularExpression alloc] initWithPattern: muster options: NSRegularExpressionCaseInsensitive error: nil]; // bleibt fuer die Laufzeit
}

static BOOL trifft( NSRegularExpression *re, NSString *s)
{
    return [re firstMatchInString: s options: 0 range: NSMakeRange( 0, s.length)] != nil;
}

static NSArray *regeln = nil;               // Paare { Ausdruck, Name }, erste passende Regel gewinnt
static NSRegularExpression *reKM = nil, *reSUB = nil, *reGradientenecho = nil;
// SekhVet Paket CS: "T1+C" / "T1 C+" (the plus needs no word boundary in front) and negated contrast
// ("ohne KM", "vor KM", "pre contrast", "non contrast", "w/o contrast" ...), see kontrastFuer:km:sub:.
static NSRegularExpression *reKMPlus = nil, *reOhneKM = nil;

static void regelnAnlegen( void)
{
    static dispatch_once_t einmal;
    dispatch_once( &einmal, ^{
        regeln = [@[
            @[ wort( @"flair"), @"FLAIR"],
            @[ wort( @"stir"), @"STIR"],
            @[ wort( @"adc"), @"ADC"],
            @[ wort( @"dwi|diffusion|dw|trace"), @"DWI"],
            @[ wort( @"swi|swan"), @"SWI"],
            @[ wort( @"hyce"), @"HYCE"],
            @[ wort( @"pd|pdw|pdwi|pd-?w|proton\\s*density"), @"PD"],
            @[ wort( @"t2\\*|t2star|t2-?\\*"), @"T2*"],
            @[ wort( @"(?:sst|t)1(?:w|wi|-w)?|mprage|vibe|thrive|lava"), @"T1"],
            @[ wort( @"(?:sst|t)2(?:w|wi|-w)?|ciss|fiesta|space|cube"), @"T2"],
        ] retain];
        reKM = wort( @"post\\s*(?:km|kontrast|contrast|gd|c)|\\+\\s*(?:km|c|gd)|km|gd|gado[A-Za-z0-9_]*|ce|contrast");
        reKMPlus = [[NSRegularExpression alloc] initWithPattern: @"\\+\\s*(?:km|c|gd|ce)(?![A-Za-z0-9])|(?:^|[^A-Za-z0-9])c\\s*\\+" options: NSRegularExpressionCaseInsensitive error: nil];
        reOhneKM = wort( @"(?:ohne|kein|keine|no|non|without|w\\s*/?\\s*o|sans|pre|prae|prä|vor)[\\s\\-]*(?:i\\.?\\s?v\\.?[\\s\\-]*)?(?:km|kontrastmittel|kontrast|contrast|gd|gado[A-Za-z0-9]*|ce|c|enhanced|enhancement)");
        reSUB = wort( @"sub");
        reGradientenecho = wort( @"gradient\\s*echo|gre|ffe|fl2d|fl3d|t2-?ffe");
    });
}

@implementation SekhmetSequenz

+ (NSString*) kontrastFuer:(NSString*) beschreibung km:(BOOL*) km sub:(BOOL*) sub
{
    regelnAnlegen();
    NSString *s = [(beschreibung ? beschreibung : @"") stringByReplacingOccurrencesOfString: @"_" withString: @" "];

    NSString *kontrast = nil;
    for( NSArray *regel in regeln)
        if( trifft( regel[0], s)) { kontrast = regel[1]; break; }

    // Gradientenecho mit T2-Gewichtung ist T2* — so heisst es am Befundtisch.
    if( [kontrast isEqualToString: @"T2"] && trifft( reGradientenecho, s))
        kontrast = @"T2*";

    BOOL istSub = trifft( reSUB, s);
    if( sub) *sub = istSub;
    if( km)
    {
        // SekhVet Paket CS: a negated or pre-contrast phrase is taken out first — otherwise the "KM" inside
        // "ohne KM" / "vor KM" / "pre contrast" counted as contrast.
        NSString *ohne = [reOhneKM stringByReplacingMatchesInString: s options: 0 range: NSMakeRange( 0, s.length) withTemplate: @" "];
        *km = !istSub && (trifft( reKM, ohne) || trifft( reKMPlus, ohne));
    }
    return kontrast;
}

// SekhVet Paket CS: CT phase rule, moved here from SekhmetUeberlagerung so that the standalone test
// (SekhVet/test/sequenz-test.sh) covers it. A negation or "before" directly in front of the contrast word wins
// ("ohne KM", "pre KM", "vor KM", "without contrast", "w/o contrast"), then contrast, then the plain native words.
+ (int) ctPhaseFuer:(NSString*) beschreibung
{
    static NSRegularExpression *reTrenner = nil, *reOhne = nil, *reCtKM = nil, *reNativ = nil;
    static dispatch_once_t einmal;
    dispatch_once( &einmal, ^{
        reTrenner = [[NSRegularExpression alloc] initWithPattern: @"[_,;()/+\\-]+" options: 0 error: nil];
        reOhne = [[NSRegularExpression alloc] initWithPattern: @"\\s(OHNE|KEIN|KEINE|NO|NON|WITHOUT|WO|W\\s+O|SANS|PRE|PRAE|PRÄ|VOR)\\s+(I\\.?\\s?V\\.?\\s+)?(KM|KONTRASTMITTEL|KONTRAST|CONTRAST|CE|C|ENHANCED|ENHANCEMENT)\\s" options: 0 error: nil];
        reCtKM = [[NSRegularExpression alloc] initWithPattern: @"\\s(KM|CE|C|KONTRASTMITTEL|KONTRAST|CONTRAST|POST\\s+KM)\\s" options: 0 error: nil];
        reNativ = [[NSRegularExpression alloc] initWithPattern: @"\\s(NATIV|NATIVE|N|NON\\s+CONTRAST|NONCONTRAST|PRE|PRECONTRAST|PREKONTRAST|PREKM|PLAIN|UNENHANCED|NONENHANCED)\\s" options: 0 error: nil];
    });
    NSString *u = [(beschreibung ? beschreibung : @"") uppercaseString];
    u = [reTrenner stringByReplacingMatchesInString: u options: 0 range: NSMakeRange( 0, u.length) withTemplate: @" "];
    u = [NSString stringWithFormat: @" %@ ", u];
    if( trifft( reOhne, u)) return 1;   // "ohne KM" first, otherwise the KM inside it counts as contrast
    if( trifft( reCtKM, u)) return 2;
    if( trifft( reNativ, u)) return 1;
    return 0;
}

+ (NSString*) farbeFuerKontrast:(NSString*) kontrast
{
    if( [kontrast isEqualToString: @"T1"]) return @"#f2c14e";
    if( [kontrast isEqualToString: @"T2"] || [kontrast isEqualToString: @"T2*"]) return @"#5aa9ff";
    if( [kontrast isEqualToString: @"FLAIR"]) return @"#b48cff";
    if( [kontrast isEqualToString: @"STIR"]) return @"#4ecdc4";
    return @"#c8c8c8";
}

#if SEKHVET_TESTHAKEN   // SekhVet Paket CS: subtraktionsName:minus: has no caller in the app yet (only the unit test)
static NSArray* woerter( NSString *s)
{
    NSRegularExpression *ws = [NSRegularExpression regularExpressionWithPattern: @"wirbels[äa]ule" options: NSRegularExpressionCaseInsensitive error: nil];
    s = [ws stringByReplacingMatchesInString: s options: 0 range: NSMakeRange( 0, s.length) withTemplate: @""];
    NSMutableArray *w = [NSMutableArray array];
    for( NSString *t in [s componentsSeparatedByCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @" \t\r\n_"]])
        if( t.length) [w addObject: t];
    return w;
}
#endif // SEKHVET_TESTHAKEN

static NSString* ohneRand( NSString *s)
{
    return [s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#if SEKHVET_TESTHAKEN
static NSString* hoechstens( NSString *s, NSUInteger n)
{
    return s.length > n ? [s substringToIndex: n] : s;
}

static NSString* nurIn( NSArray *a, NSArray *b)
{
    NSMutableSet *klein = [NSMutableSet set];
    for( NSString *w in b) [klein addObject: w.lowercaseString];
    NSMutableArray *r = [NSMutableArray array];
    for( NSString *w in a) if( ![klein containsObject: w.lowercaseString]) [r addObject: w];
    return [r componentsJoinedByString: @" "];
}

+ (NSString*) subtraktionsName:(NSString*) plus minus:(NSString*) minus
{
    NSArray *p = woerter( plus ? plus : @""), *m = woerter( minus ? minus : @"");
    NSString *nurP = nurIn( p, m), *nurM = nurIn( m, p);
    NSString *a = nurP.length ? nurP : hoechstens( ohneRand( [p componentsJoinedByString: @" "]), 10);
    if( a.length == 0) a = @"B";
    NSString *name = nurM.length ? [NSString stringWithFormat: @"SUB %@-%@", a, nurM] : [NSString stringWithFormat: @"SUB %@", a];
    return ohneRand( hoechstens( name, 24));
}
#endif // SEKHVET_TESTHAKEN

static NSColor* farbe( NSString *hex)
{
    unsigned int v = 0;
    [[NSScanner scannerWithString: [hex substringFromIndex: 1]] scanHexInt: &v];
    return [NSColor colorWithSRGBRed: ((v >> 16) & 0xff) / 255.0 green: ((v >> 8) & 0xff) / 255.0 blue: (v & 0xff) / 255.0 alpha: 1];
}

+ (NSImage*) bild:(NSImage*) bild mitPlakettenFuer:(NSString*) beschreibung
{
    return [self bild: bild mitPlakettenFuer: beschreibung modalitaet: nil];
}

+ (NSImage*) bild:(NSImage*) bild mitPlakettenFuer:(NSString*) beschreibung modalitaet:(NSString*) modalitaet
{
    if( bild == nil || bild.size.width < 16 || bild.size.height < 16) return bild;

    BOOL km = NO, sub = NO;
    NSString *kontrast = [self kontrastFuer: beschreibung km: &km sub: &sub];
    // SekhVet Paket CS: the weighting (T1/T2/...) is an MR term — a radiograph or CT named after vertebrae
    // ("BWS T1-T5 lat", "T2-L1 Knochen") must not get a T1/T2 badge. nil = modality unknown = as before.
    if( modalitaet.length && [modalitaet caseInsensitiveCompare: @"MR"] != NSOrderedSame) kontrast = nil;

    NSMutableArray *teile = [NSMutableArray array];   // { Text, Farbe }
    if( kontrast) [teile addObject: @[ kontrast, farbe( [self farbeFuerKontrast: kontrast])]];
    if( km) [teile addObject: @[ @"KM", farbe( @"#ff9f5a")]];
    if( sub) [teile addObject: @[ @"SUB", farbe( @"#7ee787")]];
    if( teile.count == 0) return bild;

    // 10 pt auf der 68-Pixel-Miniatur wie in ImagoPilot; kleine/grosse Listen skalieren mit.
    NSSize g = bild.size;
    CGFloat pt = MIN( 13, MAX( 7, 10 * g.width / 68.0));
    NSFont *font = [NSFont boldSystemFontOfSize: pt];

    return [NSImage imageWithSize: g flipped: NO drawingHandler: ^BOOL( NSRect r) {
        [bild drawInRect: r fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1];

        // Wie das Flex-Wrap der Vorlage: 2 pt Rand, 2 pt Abstand, von unten links; was nicht
        // mehr in die Zeile passt, rutscht eine Zeile hoeher.
        CGFloat x = 2, y = 2, zeile = 0;
        for( NSArray *t in teile)
        {
            NSDictionary *attr = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: t[1]};
            NSSize ts = [t[0] sizeWithAttributes: attr];
            NSSize ps = NSMakeSize( ceil( ts.width) + 6, ceil( ts.height) + 2);
            if( x > 2 && x + ps.width > g.width - 2) { x = 2; y += zeile + 2; zeile = 0; }

            [[NSColor colorWithCalibratedWhite: 0 alpha: 0.78] setFill];
            [[NSBezierPath bezierPathWithRoundedRect: NSMakeRect( x, y, ps.width, ps.height) xRadius: 3 yRadius: 3] fill];
            [t[0] drawAtPoint: NSMakePoint( x + 3, y + 1) withAttributes: attr];

            x += ps.width + 2;
            zeile = MAX( zeile, ps.height);
        }
        return YES;
    }];
}

+ (NSString*) name:(NSString*) name dreiZeilenBreite:(CGFloat) breite font:(NSFont*) font
{
    if( name.length == 0 || font == nil || breite < 10) return name;

    NSTextStorage *ts = [[[NSTextStorage alloc] init] autorelease];
    NSLayoutManager *lm = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *tc = [[[NSTextContainer alloc] initWithContainerSize: NSMakeSize( breite, CGFLOAT_MAX)] autorelease];
    tc.lineFragmentPadding = 0;
    tc.maximumNumberOfLines = 3;
    [lm addTextContainer: tc];
    [ts addLayoutManager: lm];

    NSUInteger (^passt)( NSString*) = ^NSUInteger( NSString *s) {
        [ts setAttributedString: [[[NSAttributedString alloc] initWithString: s attributes: @{ NSFontAttributeName: font}] autorelease]];
        NSRange gl = [lm glyphRangeForTextContainer: tc];
        return NSMaxRange( [lm characterRangeForGlyphRange: gl actualGlyphRange: NULL]);
    };

    // Umbrueche selbst setzen: die Zelle bekommt fertige Zeilen, jede schmaler als die Breite.
    // Am Geraet zeichnete die Zelle der offenen Serie den Namen sonst einzeilig und schnitt
    // ihn links und rechts ab (Rueckmeldung vom 27.09., erster Stand von Build 121).
    NSString* (^zeilen)( NSString*) = ^NSString*( NSString *s) {
        passt( s);
        NSMutableArray *z = [NSMutableArray array];
        [lm enumerateLineFragmentsForGlyphRange: [lm glyphRangeForTextContainer: tc] usingBlock: ^( NSRect rect, NSRect used, NSTextContainer *c, NSRange gl, BOOL *stop) {
            NSString *t = ohneRand( [s substringWithRange: [lm characterRangeForGlyphRange: gl actualGlyphRange: NULL]]);
            if( t.length) [z addObject: t];
        }];
        return z.count ? [z componentsJoinedByString: @"\n"] : s;
    };
    
    NSUInteger n = passt( name);
    if( n >= name.length) return zeilen( name);

    // Kuerzen, bis Text + "…" in drei Zeilen passt; nie mitten in ein zusammengesetztes Zeichen.
    for( ; n > 0; n--)
    {
        NSRange r = [name rangeOfComposedCharacterSequencesForRange: NSMakeRange( 0, n)];
        if( NSMaxRange( r) > n) continue;
        NSString *k = [ohneRand( [name substringToIndex: n]) stringByAppendingString: @"…"];
        if( passt( k) >= k.length) return zeilen( k);
    }
    return name;
}

@end
