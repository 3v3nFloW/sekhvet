// Update-Pruefung (Paket CB, 27.09.2026): bash SekhVet/test/update-test.sh
// Reine Logik: welches Release wird angeboten, welche Build-Nummer hat es.
// SekhVet Paket CS: dazu die Beschraenkung der Adressen und die Typfestigkeit gegen kaputtes JSON.

#import "SekhmetUpdate.h"

static int pass = 0, fail = 0;
static void check( NSString *n, BOOL c, id ist)
{
    if( c) { pass++; printf( "  ✅ %s\n", n.UTF8String); }
    else { fail++; printf( "  ❌ %s  (ist: %s)\n", n.UTF8String, [[ist description] UTF8String]); }
}
static NSDictionary* rel( NSString *tag, BOOL pre, BOOL draft, NSArray *assets)
{
    NSMutableArray *a = [NSMutableArray array];
    for( NSString *n in assets) [a addObject: @{ @"name": n, @"browser_download_url": [@"https://github.com/3v3nFloW/sekhvet/releases/download/x/" stringByAppendingString: n]}];
    return @{ @"tag_name": tag, @"name": [@"SekhVet " stringByAppendingString: tag], @"prerelease": @(pre), @"draft": @(draft), @"html_url": @"https://github.com/3v3nFloW/sekhvet/releases/tag/x", @"body": @"Notes", @"assets": a};
}

int main( int argc, char **argv)
{
    @autoreleasepool
    {
        printf( "[Build-Nummer]\n");
        check( @"DMG „SekhVet-1.0-beta-build117-macOS.dmg\" → 117", [SekhmetUpdate buildAusName: @"SekhVet-1.0-beta-build117-macOS.dmg" tag: @"v1.0-beta.117"] == 117, nil);
        check( @"DMG „SekhVet-1.0-build130-macOS.dmg\", Tag v1.0 → 130", [SekhmetUpdate buildAusName: @"SekhVet-1.0-build130-macOS.dmg" tag: @"v1.0"] == 130, nil);
        check( @"DMG ohne Nummer, Tag v1.0-beta.117 → 117", [SekhmetUpdate buildAusName: @"SekhVet.dmg" tag: @"v1.0-beta.117"] == 117, nil);
        check( @"DMG ohne Nummer, Tag v1.0 → 0 (nicht anbieten)", [SekhmetUpdate buildAusName: @"SekhVet.dmg" tag: @"v1.0"] == 0, nil);
        check( @"DMG ohne Nummer, Tag v1.1 → 0 (die Versionsziffer ist keine Build-Nummer)", [SekhmetUpdate buildAusName: @"SekhVet.dmg" tag: @"v1.1"] == 0 && [SekhmetUpdate buildAusName: @"SekhVet.dmg" tag: @"2.12"] == 0, nil);   // SekhVet Paket CS
        check( @"DMG ohne Nummer, Tag v1.0-130 → 130", [SekhmetUpdate buildAusName: @"SekhVet.dmg" tag: @"v1.0-130"] == 130, nil);
        
        printf( "[Echte GitHub-Antwort vom 27.09.2026 (nur Pre-releases)]\n");
        NSData *daten = [NSData dataWithContentsOfFile: @(argv[1])];
        id liste = [NSJSONSerialization JSONObjectWithData: daten options: 0 error: nil];
        NSDictionary *b = [SekhmetUpdate angebotAus: liste betas: YES];
        check( @"mit Betas → build 117 mit DMG-Link", [b[@"build"] integerValue] == 117 && [b[@"dmg"] hasSuffix: @"SekhVet-1.0-beta-build117-macOS.dmg"], b);
        check( @"ohne Betas → kein Angebot", [SekhmetUpdate angebotAus: liste betas: NO] == nil, [SekhmetUpdate angebotAus: liste betas: NO]);
        
        printf( "[Erstes stabiles Release (/releases/latest liefert ein Objekt)]\n");
        NSDictionary *st = [SekhmetUpdate angebotAus: rel( @"v1.0", NO, NO, @[ @"SekhVet-1.0-build130-macOS.zip", @"SekhVet-1.0-build130-macOS.dmg"]) betas: NO];
        check( @"v1.0 → build 130, Link zeigt auf die .dmg (nicht die .zip)", [st[@"build"] integerValue] == 130 && [st[@"dmg"] hasSuffix: @".dmg"], st);
        check( @"Name und Seite uebernommen", [st[@"name"] isEqualToString: @"SekhVet v1.0"] && [st[@"seite"] hasPrefix: @"https://github.com/"], st);
        
        printf( "[Keine Fehlangebote]\n");
        check( @"Entwurf wird uebersprungen", [[SekhmetUpdate angebotAus: @[ rel( @"v1.1", NO, YES, @[ @"SekhVet-1.1-build140-macOS.dmg"]), rel( @"v1.0", NO, NO, @[ @"SekhVet-1.0-build130-macOS.dmg"])] betas: NO][@"build"] integerValue] == 130, nil);
        check( @"Release ohne DMG wird uebersprungen", [SekhmetUpdate angebotAus: rel( @"v1.0", NO, NO, @[ @"SekhVet-1.0-build130-macOS.zip"]) betas: NO] == nil, nil);
        check( @"Beta vor dem stabilen: ohne Betas gilt das stabile", [[SekhmetUpdate angebotAus: @[ rel( @"v1.1-beta.141", YES, NO, @[ @"SekhVet-1.1-beta-build141-macOS.dmg"]), rel( @"v1.0", NO, NO, @[ @"SekhVet-1.0-build130-macOS.dmg"])] betas: NO][@"build"] integerValue] == 130, nil);
        check( @"Kaputte Antwort (Fehlermeldung von GitHub) → nil", [SekhmetUpdate angebotAus: @{ @"message": @"Not Found"} betas: NO] == nil, nil);
        check( @"nil → nil", [SekhmetUpdate angebotAus: nil betas: NO] == nil, nil);
        
        // SekhVet Paket CS
        printf( "[Nur Adressen des SekhVet-Repos auf github.com]\n");
        NSString *releases = @"https://github.com/3v3nFloW/sekhvet/releases";
        NSString *gut = @"https://github.com/3v3nFloW/sekhvet/releases/download/v1.0/SekhVet-1.0-build130-macOS.dmg";
        check( @"DMG-Link des Repos bleibt", [[SekhmetUpdate sichereAdresse: gut] isEqualToString: gut], [SekhmetUpdate sichereAdresse: gut]);
        check( @"Tag-Seite des Repos bleibt", [[SekhmetUpdate sichereAdresse: @"https://github.com/3v3nFloW/sekhvet/releases/tag/v1.0"] hasSuffix: @"/tag/v1.0"], nil);
        for( id boese in @[ @"http://github.com/3v3nFloW/sekhvet/releases/download/x/a.dmg", @"https://evil.example/SekhVet.dmg", @"https://github.com/evil/sekhvet/releases/download/x/a.dmg",
                            @"https://github.com/3v3nFloW/sekhvet/../../evil/x/releases/download/x/a.dmg", @"https://github.com/3v3nFloW/sekhvet/%2e%2e/%2E%2E/evil/a.dmg",
                            @"https://github.com/3v3nFloW/sekhvet-evil/a.dmg", @"https://github.com.evil.example/3v3nFloW/sekhvet/a.dmg", @"file:///Applications/Calculator.app",
                            @"smb://server/share", @"https://github.com/3v3nFloW/sekhvet/a b.dmg", @"", @42, [NSNull null], @[ gut], @{ @"url": gut}])
            check( [NSString stringWithFormat: @"%@ → Releases-Seite", [[boese description] stringByReplacingOccurrencesOfString: @"\n" withString: @" "]], [[SekhmetUpdate sichereAdresse: boese] isEqualToString: releases], [SekhmetUpdate sichereAdresse: boese]);
        check( @"nil → Releases-Seite", [[SekhmetUpdate sichereAdresse: nil] isEqualToString: releases], nil);
        NSMutableDictionary *fremd = [[rel( @"v1.0", NO, NO, @[]) mutableCopy] autorelease];
        fremd[@"assets"] = @[ @{ @"name": @"SekhVet-1.0-build130-macOS.dmg", @"browser_download_url": @"https://evil.example/SekhVet-1.0-build130-macOS.dmg"}];
        fremd[@"html_url"] = @"javascript:alert(1)";
        NSDictionary *fa = [SekhmetUpdate angebotAus: fremd betas: NO];
        check( @"Angebot mit fremdem DMG-Link und fremder Seite → beide auf die Releases-Seite", [fa[@"build"] integerValue] == 130 && [fa[@"dmg"] isEqualToString: releases] && [fa[@"seite"] isEqualToString: releases], fa);

        printf( "[JSON mit falschen Typen stuerzt nicht ab]\n");
        NSArray *kaputt = @[ [NSNull null], @"text", @7, @[ @1],
                             @{ @"draft": [NSNull null], @"prerelease": [NSNull null], @"assets": [NSNull null]},
                             @{ @"draft": @"no", @"prerelease": @{}, @"assets": @"SekhVet.dmg"},
                             @{ @"assets": @{ @"name": @"SekhVet-1.0-build999-macOS.dmg"}},
                             @{ @"assets": @[ [NSNull null], @"x", @5, @{ @"name": [NSNull null], @"browser_download_url": @1}, @{ @"name": @7, @"browser_download_url": [NSNull null]}]},
                             @{ @"tag_name": @130, @"name": [NSNull null], @"body": @[], @"html_url": @{}, @"assets": @[ @{ @"name": @"SekhVet-1.0-build131-macOS.dmg", @"browser_download_url": @[ gut]}]},
                             @{ @"tag_name": [NSNull null], @"name": @12, @"body": [NSNull null], @"html_url": [NSNull null], @"draft": @NO, @"prerelease": @NO,
                                @"assets": @[ @{ @"name": @"SekhVet-1.0-build132-macOS.dmg", @"browser_download_url": gut}]}];
        NSDictionary *k = nil; BOOL geworfen = NO;
        @try { k = [SekhmetUpdate angebotAus: kaputt betas: NO]; [SekhmetUpdate unklaresReleaseAus: kaputt betas: NO]; for( id e in kaputt) { [SekhmetUpdate angebotAus: e betas: YES]; [SekhmetUpdate unklaresReleaseAus: e betas: YES]; } }
        @catch (NSException *e) { geworfen = YES; }
        check( @"keine Exception bei NSNull / Zahl / Text / Array an jeder Stelle", geworfen == NO, nil);
        check( @"das einzige brauchbare Release der kaputten Liste wird gefunden (build 132, Name = leerer Tag, Seite = Releases)", [k[@"build"] integerValue] == 132 && [k[@"name"] isEqualToString: @""] && [k[@"seite"] isEqualToString: releases] && [k[@"notizen"] isEqualToString: @""], k);
        check( @"draft als NSNull gilt nicht als Entwurf, draft = YES schon", [SekhmetUpdate angebotAus: @{ @"draft": @YES, @"tag_name": @"v1.0", @"assets": @[ @{ @"name": @"SekhVet-1.0-build130-macOS.dmg", @"browser_download_url": gut}]} betas: NO] == nil, nil);

        printf( "[Neuestes Release ohne Build-Nummer]\n");
        NSDictionary *ohne = rel( @"v1.1", NO, NO, @[ @"SekhVet.dmg"]);
        check( @"wird nicht angeboten …", [SekhmetUpdate angebotAus: ohne betas: NO] == nil, nil);
        NSDictionary *u = [SekhmetUpdate unklaresReleaseAus: ohne betas: NO];
        check( @"… aber als nicht vergleichbar gemeldet (Name, Seite)", [u[@"name"] isEqualToString: @"SekhVet v1.1"] && [u[@"seite"] hasPrefix: releases], u);
        check( @"neuestes MIT Nummer → nichts Unklares", [SekhmetUpdate unklaresReleaseAus: @[ rel( @"v1.1", NO, NO, @[ @"SekhVet-1.1-build140-macOS.dmg"]), ohne] betas: NO] == nil, nil);
        check( @"Entwurf ohne Nummer vor einem nummerierten → nichts Unklares", [SekhmetUpdate unklaresReleaseAus: @[ rel( @"v1.2", NO, YES, @[ @"SekhVet.dmg"]), rel( @"v1.1", NO, NO, @[ @"SekhVet-1.1-build140-macOS.dmg"])] betas: NO] == nil, nil);
        check( @"ohne Nummer vor einem aelteren nummerierten → unklar gemeldet, das aeltere bleibt das Angebot", [SekhmetUpdate unklaresReleaseAus: @[ ohne, rel( @"v1.0", NO, NO, @[ @"SekhVet-1.0-build130-macOS.dmg"])] betas: NO] != nil && [[SekhmetUpdate angebotAus: @[ ohne, rel( @"v1.0", NO, NO, @[ @"SekhVet-1.0-build130-macOS.dmg"])] betas: NO][@"build"] integerValue] == 130, nil);
        check( @"echte Antwort vom 27.09.2026 → nichts Unklares", [SekhmetUpdate unklaresReleaseAus: liste betas: YES] == nil && [SekhmetUpdate unklaresReleaseAus: liste betas: NO] == nil, nil);

        printf( fail ? "▸ ROT (%d/%d)\n" : "▸ GRÜN (%d)\n", fail ? fail : pass, pass + fail);
    }
    return fail ? 1 : 0;
}
