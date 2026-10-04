// Sequenz-Plaketten der Serienliste (Paket CA, 27.09.2026): bash SekhVet/test/sequenz-test.sh
// Faelle 1:1 aus ImagoPilot apps/web/test/sequenz.test.ts (28 Faelle).
// SekhVet Paket CS: plus cases without an ImagoPilot original — negated / pre-contrast names, "T1+C",
// the CT phase rule of the overlay (ctPhaseFuer:) and the MR-only weighting badge.

#import "SekhmetSequenz.h"

static int pass = 0, fail = 0;

static void check( NSString *n, BOOL c, NSString *d)
{
    if( c) { pass++; printf( "  ✅ %s\n", n.UTF8String); }
    else { fail++; printf( "  ❌ %s  %s\n", n.UTF8String, (d ? d : @"").UTF8String); }
}

static void erwarte( NSString *name, NSString *kontrast, BOOL km, BOOL sub)
{
    BOOL pkm = NO, psub = NO;
    NSString *pk = [SekhmetSequenz kontrastFuer: name km: &pkm sub: &psub];
    NSString *titel = [NSString stringWithFormat: @"„%@\" → %@%@%@", name, kontrast ? kontrast : @"—", km ? @" +KM" : @"", sub ? @" SUB" : @""];
    BOOL gleich = ((pk == nil && kontrast == nil) || [pk isEqualToString: kontrast]) && pkm == km && psub == sub;
    check( titel, gleich, [NSString stringWithFormat: @"{kontrast:%@, km:%d, sub:%d}", pk, pkm, psub]);
}

// SekhVet Paket CS: CT phase rule (0 unknown, 1 native, 2 contrast)
static void erwartePhase( NSString *name, int phase)
{
    int p = [SekhmetSequenz ctPhaseFuer: name];
    check( [NSString stringWithFormat: @"CT „%@\" → %@", name, phase == 2 ? @"contrast" : phase == 1 ? @"native" : @"unknown"], p == phase, [NSString stringWithFormat: @"{phase:%d}", p]);
}

int main( void)
{
    @autoreleasepool
    {
        printf( "[Esaote-Namen aus echten Studien]\n");
        erwarte( @"HKCL Gradient Echo T2 tra HawkAI", @"T2*", NO, NO);
        erwarte( @"HKCL 3D HYCE dor HawkAI", @"HYCE", NO, NO);
        erwarte( @"HKCL 3D SST1 dor post KM HawkAI", @"T1", YES, NO);
        erwarte( @"HKCL 3D SST1 dor HawkAI", @"T1", NO, NO);
        erwarte( @"HKCL SE T1 tra post KM HawkAI", @"T1", YES, NO);
        erwarte( @"HKCL FSE T2 sag HawkAI", @"T2", NO, NO);
        erwarte( @"HKCL Fast FLAIR dor HawkAI", @"FLAIR", NO, NO);
        erwarte( @"HKCL Fast STIR dor HawkAI", @"STIR", NO, NO);
        erwarte( @"HKCL FSE T2 sag FAST HawkAI", @"T2", NO, NO);

        printf( "[Andere Hersteller]\n");
        erwarte( @"t1_tse_tra", @"T1", NO, NO);
        erwarte( @"T1W_TSE +C", @"T1", YES, NO);
        erwarte( @"t2_tse_sag", @"T2", NO, NO);
        erwarte( @"T2W_FFE", @"T2*", NO, NO);
        erwarte( @"ep2d_diff_b1000 TRACE", @"DWI", NO, NO);
        erwarte( @"ADC", @"ADC", NO, NO);
        erwarte( @"PD_SPAIR cor", @"PD", NO, NO);
        erwarte( @"t1_mprage_sag Gd", @"T1", YES, NO);

        printf( "[Keine Fehltreffer]\n");
        erwarte( @"Serie 10", nil, NO, NO);
        erwarte( @"Localizer", nil, NO, NO);
        erwarte( @"CT Wirbelsule KM 080 Br40 S2", nil, YES, NO);
        erwarte( @"CT Wirbelsule nativ 080 Br40 S2", nil, NO, NO);
        erwarte( @"SUB KM-nativ", nil, NO, YES);
        erwarte( @"", nil, NO, NO);

        printf( "[Name der Differenzserie]\n");
        NSString *n1 = [SekhmetSequenz subtraktionsName: @"HKCL SE T1 tra post KM HawkAI" minus: @"HKCL SE T1 tra HawkAI"];
        check( [NSString stringWithFormat: @"MR → „SUB post KM\" (ist: %@)", n1], [n1 isEqualToString: @"SUB post KM"], nil);
        NSString *n2 = [SekhmetSequenz subtraktionsName: @"CT Wirbelsule KM 080 Br40 S2" minus: @"CT Wirbelsule nativ 080 Br40 S2"];
        check( [NSString stringWithFormat: @"CT → „SUB KM-nativ\" (ist: %@)", n2], [n2 isEqualToString: @"SUB KM-nativ"], nil);
        NSString *n3 = [SekhmetSequenz subtraktionsName: @"Serie X" minus: @"Serie X"];
        check( [NSString stringWithFormat: @"gleiche Namen → nicht leer (ist: %@)", n3], [n3 isEqualToString: @"SUB Serie X"], nil);
        NSString *lang = [@"" stringByPaddingToLength: 40 withString: @"a" startingAtIndex: 0];
        check( @"höchstens 24 Zeichen", [SekhmetSequenz subtraktionsName: lang minus: @"b"].length <= 24, nil);
        BOOL km = YES, sub = NO;
        [SekhmetSequenz kontrastFuer: n1 km: &km sub: &sub];
        check( @"Plakette erkennt den neuen Namen als SUB", sub && !km, nil);

        // SekhVet Paket CS: everything below has no ImagoPilot original.
        printf( "[MR: negated / pre-contrast names are not KM]\n");
        erwarte( @"T1 tra ohne KM", @"T1", NO, NO);
        erwarte( @"T1 vor KM", @"T1", NO, NO);
        erwarte( @"T1 pre KM", @"T1", NO, NO);
        erwarte( @"T1 pre contrast", @"T1", NO, NO);
        erwarte( @"T1 pre-contrast", @"T1", NO, NO);
        erwarte( @"T1 non contrast", @"T1", NO, NO);
        erwarte( @"T1 without contrast", @"T1", NO, NO);
        erwarte( @"T1 w/o contrast", @"T1", NO, NO);
        erwarte( @"t1_tse_sag_ohne_KM", @"T1", NO, NO);
        erwarte( @"T1 sans gado", @"T1", NO, NO);
        erwarte( @"T1 nativ", @"T1", NO, NO);
        erwarte( @"T1 unenhanced", @"T1", NO, NO);
        erwarte( @"T1 ohne i.v. KM", @"T1", NO, NO);

        printf( "[MR: contrast names]\n");
        erwarte( @"T1 post KM", @"T1", YES, NO);
        erwarte( @"T1 KM", @"T1", YES, NO);
        erwarte( @"T1+C", @"T1", YES, NO);
        erwarte( @"T1 +C", @"T1", YES, NO);
        erwarte( @"T1 C+", @"T1", YES, NO);
        erwarte( @"T1 tra +KM", @"T1", YES, NO);
        erwarte( @"T1 CE", @"T1", YES, NO);
        erwarte( @"T1 contrast", @"T1", YES, NO);
        erwarte( @"T1 mit KM", @"T1", YES, NO);
        erwarte( @"T1 with contrast", @"T1", YES, NO);
        erwarte( @"T1 pre und post KM", @"T1", YES, NO);
        erwarte( @"T1 tra C5-C7", @"T1", NO, NO);

        printf( "[CT phase rule of the overlay]\n");
        erwartePhase( @"Wirbelsäule nativ 0,80 Br40", 1);
        erwartePhase( @"Schulter Ellbogen KM 0 60 Br40 S2", 2);
        erwartePhase( @"Wirbelsäule ohne KM", 1);
        erwartePhase( @"Abdomen post KM", 2);
        erwartePhase( @"SST1", 0);
        erwartePhase( @"CT Kopf", 0);
        erwartePhase( @"Thorax C+", 2);
        erwartePhase( @"Thorax +C", 2);
        erwartePhase( @"Abdomen pre KM", 1);
        erwartePhase( @"Abdomen vor KM", 1);
        erwartePhase( @"Abdomen pre-KM 1.0", 1);
        erwartePhase( @"Abdomen without contrast", 1);
        erwartePhase( @"Abdomen w/o contrast", 1);
        erwartePhase( @"Abdomen pre contrast", 1);
        erwartePhase( @"Abdomen non contrast", 1);
        erwartePhase( @"Abdomen no contrast", 1);
        erwartePhase( @"Abdomen sans contrast", 1);
        erwartePhase( @"Abdomen ohne i.v. KM", 1);
        erwartePhase( @"Abdomen plain", 1);
        erwartePhase( @"Abdomen unenhanced", 1);
        erwartePhase( @"Abdomen native", 1);
        erwartePhase( @"Abdomen pre", 1);
        erwartePhase( @"Abdomen mit KM", 2);
        erwartePhase( @"Abdomen with contrast", 2);
        erwartePhase( @"Abdomen contrast", 2);
        erwartePhase( @"Abdomen CE", 2);
        erwartePhase( @"Abdomen KM portalvenös", 2);
        erwartePhase( @"Abdomen pre und post KM", 2);
        erwartePhase( @"Abdomen 1.0 Br40", 0);
        erwartePhase( @"", 0);
        erwartePhase( nil, 0);

        printf( "[Weighting badge only for MR]\n");
        {
            NSImage *m68 = [[[NSImage alloc] initWithSize: NSMakeSize( 68, 68)] autorelease];
            check( @"CR „BWS T1-T5 lat\" → no badge", [SekhmetSequenz bild: m68 mitPlakettenFuer: @"BWS T1-T5 lat" modalitaet: @"CR"] == m68, nil);
            check( @"CT „T2-L1 Knochen\" → no badge", [SekhmetSequenz bild: m68 mitPlakettenFuer: @"T2-L1 Knochen" modalitaet: @"CT"] == m68, nil);
            check( @"CT „Abdomen KM\" → KM badge stays", [SekhmetSequenz bild: m68 mitPlakettenFuer: @"Abdomen KM" modalitaet: @"CT"] != m68, nil);
            check( @"MR „SE T1 tra\" → badge", [SekhmetSequenz bild: m68 mitPlakettenFuer: @"SE T1 tra" modalitaet: @"MR"] != m68, nil);
            check( @"modality unknown (nil) → as before, badge", [SekhmetSequenz bild: m68 mitPlakettenFuer: @"BWS T1-T5 lat" modalitaet: nil] != m68, nil);
            check( @"old signature → as before, badge", [SekhmetSequenz bild: m68 mitPlakettenFuer: @"SE T1 tra"] != m68, nil);
        }

        printf( fail ? "▸ ROT (%d/%d)\n" : "▸ GRÜN (%d)\n", fail ? fail : pass, pass + fail);

        // Zusatz ohne Vorlage (nicht in den 28): Zeichnen und Drei-Zeilen-Kuerzung laufen ohne Ausnahme.
        NSImage *mini = [[[NSImage alloc] initWithSize: NSMakeSize( 68, 68)] autorelease];
        NSImage *mit = [SekhmetSequenz bild: mini mitPlakettenFuer: @"HKCL SE T1 tra post KM HawkAI"];
        NSString *k = [SekhmetSequenz name: @"HKCL 3D SST1 dor post KM HawkAI mit einem sehr langen Anhang ohne Ende und noch mehr Text" dreiZeilenBreite: 92 font: [NSFont systemFontOfSize: 8.5]];
        NSString *kurz = [SekhmetSequenz name: @"HKCL SE T1 tra HawkAI" dreiZeilenBreite: 92 font: [NSFont boldSystemFontOfSize: 8.5]];
        printf( "  Zusatz: Zeilen \u201e%s\"\n", [kurz stringByReplacingOccurrencesOfString: @"\n" withString: @" | "].UTF8String);
        k = [k stringByReplacingOccurrencesOfString: @"\n" withString: @" | "];
        printf( "  Zusatz: Plakettenbild %s, gekürzt: „%s\"\n", mit != mini ? "neu" : "UNVERAENDERT", k.UTF8String);
        if( getenv( "SEKHVET_SEQUENZ_PNG"))
        {
            NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 136 pixelsHigh: 136 bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0] autorelease];
            rep.size = NSMakeSize( 68, 68);
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
            [[NSColor grayColor] setFill]; NSRectFill( NSMakeRect( 0, 0, 68, 68));
            [mit drawInRect: NSMakeRect( 0, 0, 68, 68)];
            [NSGraphicsContext restoreGraphicsState];
            [[rep representationUsingType: NSBitmapImageFileTypePNG properties: @{}] writeToFile: @(getenv( "SEKHVET_SEQUENZ_PNG")) atomically: YES];
        }
    }
    return fail ? 1 : 0;
}
