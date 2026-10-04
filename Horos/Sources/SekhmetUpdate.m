/*=========================================================================
 SekhVet Paket CB — Update-Pruefung gegen die GitHub-Releases. Siehe Header.
 ============================================================================*/

#import "SekhmetUpdate.h"
#import "SekhmetTesthaken.h"

#define SEKHMET_RELEASES @"https://api.github.com/repos/3v3nFloW/sekhvet/releases"
// SekhVet Paket CS: the only addresses the update dialog may open in the browser
#define SEKHMET_SEITE_PRAEFIX @"https://github.com/3v3nFloW/sekhvet/"
#define SEKHMET_SEITE_RELEASES @"https://github.com/3v3nFloW/sekhvet/releases"
#define SEKHMET_UPDATE_ABSTAND (24 * 60 * 60)

static BOOL laeuft = NO;

static NSInteger ersteZahl( NSString *s, NSString *muster)
{
    if( s.length == 0) return 0;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern: muster options: NSRegularExpressionCaseInsensitive error: nil];
    NSTextCheckingResult *m = [re firstMatchInString: s options: 0 range: NSMakeRange( 0, s.length)];
    return m ? [[s substringWithRange: [m rangeAtIndex: 1]] integerValue] : 0;
}

static NSInteger eigenerBuild( void)
{
    return [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"] integerValue];
}

// SekhVet Paket CS: the GitHub answer is untrusted input -- every field is type-checked before use.
static NSString* text( id v)
{
    return [v isKindOfClass: [NSString class]] ? v : nil;
}

static BOOL wahr( id v)
{
    return [v isKindOfClass: [NSNumber class]] && [v boolValue];
}

// Erstes DMG-Asset eines Releases, nil = keines.
static NSDictionary* dmgAsset( NSDictionary *r)
{
    NSArray *assets = [r[@"assets"] isKindOfClass: [NSArray class]] ? r[@"assets"] : nil;
    for( NSDictionary *a in assets)
        if( [a isKindOfClass: [NSDictionary class]] && [[text( a[@"name"]) lowercaseString] hasSuffix: @".dmg"] && text( a[@"browser_download_url"]).length) return a;
    return nil;
}

static BOOL kommtInFrage( id r, BOOL betas)
{
    if( ![r isKindOfClass: [NSDictionary class]]) return NO;
    if( wahr( r[@"draft"])) return NO;
    if( wahr( r[@"prerelease"]) && !betas) return NO;
    return YES;
}

@implementation SekhmetUpdate

// SekhVet Paket CS: only https://github.com/3v3nFloW/sekhvet/... is ever handed to the browser;
// anything else (other scheme, host or repository, path tricks) falls back to the releases page.
+ (NSString*) sichereAdresse:(id) adresse
{
    NSString *a = text( adresse);
    if( a == nil || ![a hasPrefix: SEKHMET_SEITE_PRAEFIX]) return SEKHMET_SEITE_RELEASES;
    if( [a rangeOfString: @".."].location != NSNotFound || [a rangeOfString: @"\\"].location != NSNotFound || [a rangeOfString: @"@"].location != NSNotFound) return SEKHMET_SEITE_RELEASES;
    if( [a rangeOfString: @"%2e" options: NSCaseInsensitiveSearch].location != NSNotFound || [a rangeOfString: @"%2f" options: NSCaseInsensitiveSearch].location != NSNotFound || [a rangeOfString: @"%5c" options: NSCaseInsensitiveSearch].location != NSNotFound) return SEKHMET_SEITE_RELEASES;
    if( [a rangeOfCharacterFromSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound || [a rangeOfCharacterFromSet: [NSCharacterSet controlCharacterSet]].location != NSNotFound) return SEKHMET_SEITE_RELEASES;
    NSURL *u = [NSURL URLWithString: a];
    if( u == nil || ![[u scheme] isEqualToString: @"https"] || ![[u host] isEqualToString: @"github.com"] || [u port] != nil || [u user] != nil) return SEKHMET_SEITE_RELEASES;
    return a;
}

+ (NSInteger) buildAusName:(NSString*) dmgName tag:(NSString*) tag
{
    NSInteger b = ersteZahl( dmgName, @"build[-_ ]?([0-9]+)");
    // "v1.0-beta.117"; ein "v1.0" ohne DMG-Nummer zaehlt nicht.
    // SekhVet Paket CS: a plain version tag ("v1.1", "v2.0") carries no build number at all -- its last
    // component used to be read as build 1 resp. 0, so "v1.0" was skipped only because it ends in 0.
    if( b == 0 && tag.length && [tag rangeOfString: @"^v?[0-9]+(\\.[0-9]+)?$" options: NSRegularExpressionSearch | NSCaseInsensitiveSearch].location == NSNotFound)
        b = ersteZahl( tag, @"[.-]([0-9]+)$");
    return b;
}

+ (NSDictionary*) angebotAus:(id) json betas:(BOOL) betas
{
    NSArray *liste = [json isKindOfClass: [NSArray class]] ? json : ([json isKindOfClass: [NSDictionary class]] ? @[ json] : nil);

    for( NSDictionary *r in liste)
    {
        if( !kommtInFrage( r, betas)) continue;

        NSDictionary *dmg = dmgAsset( r);
        if( dmg == nil) continue;   // ohne DMG gibt es nichts zu verweisen

        NSString *tag = text( r[@"tag_name"]) ?: @"";
        NSInteger build = [self buildAusName: text( dmg[@"name"]) tag: tag];
        if( build <= 0) continue;

        NSString *name = text( r[@"name"]).length ? text( r[@"name"]) : tag;
        NSString *notizen = text( r[@"body"]) ?: @"";
        // SekhVet Paket CS: both links are restricted to the SekhVet repository on github.com
        return @{ @"build": @(build), @"dmg": [self sichereAdresse: dmg[@"browser_download_url"]], @"name": name, @"seite": [self sichereAdresse: r[@"html_url"]], @"notizen": notizen};
    }
    return nil;
}

// SekhVet Paket CS: the NEWEST release that qualifies (not a draft, DMG attached) carries no build
// number -- neither "build<N>" in the DMG name nor a numeric tag suffix. It cannot be compared with the
// running build (a publishing date is no substitute: the app does not know its own), so it is never
// offered by itself. The explicit "Check for Updates" mentions it instead of claiming "up to date".
// Liefert {name, seite} oder nil.
+ (NSDictionary*) unklaresReleaseAus:(id) json betas:(BOOL) betas
{
    NSArray *liste = [json isKindOfClass: [NSArray class]] ? json : ([json isKindOfClass: [NSDictionary class]] ? @[ json] : nil);

    for( NSDictionary *r in liste)
    {
        if( !kommtInFrage( r, betas)) continue;
        NSDictionary *dmg = dmgAsset( r);
        if( dmg == nil) continue;
        NSString *tag = text( r[@"tag_name"]) ?: @"";
        if( [self buildAusName: text( dmg[@"name"]) tag: tag] > 0) return nil;   // das neueste ist vergleichbar
        NSString *name = text( r[@"name"]).length ? text( r[@"name"]) : tag;
        return @{ @"name": name.length ? name : @"SekhVet", @"seite": [self sichereAdresse: r[@"html_url"]]};
    }
    return nil;
}

+ (void) pruefenNachStart
{
    [self performSelector: @selector(pruefenStill) withObject: nil afterDelay: 15]; // Default-Modus: nie ueber dem Hinweis beim ersten Start
}

+ (void) pruefenStill
{
    [self pruefen: NO];
}

+ (void) pruefen:(BOOL) ausdruecklich
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if( !ausdruecklich)
    {
        if( ![d boolForKey: @"CheckHorosUpdates"]) return;
        NSDate *zuletzt = [d objectForKey: @"SekhmetUpdateLetztePruefung"];
        if( [zuletzt isKindOfClass: [NSDate class]] && -[zuletzt timeIntervalSinceNow] < SEKHMET_UPDATE_ABSTAND) return;
    }
    if( laeuft) return;
    laeuft = YES;

    BOOL betas = [d boolForKey: @"SekhmetUpdateBetas"];
    NSString *adresse = betas ? SEKHMET_RELEASES @"?per_page=10" : SEKHMET_RELEASES @"/latest";
#if SEKHVET_TESTHAKEN   // SekhVet Paket CS: like every other test hook, compiled only into test builds
    if( sekhvetTesthaken( "SEKHVET_UPDATE_URL")) adresse = @(sekhvetTesthaken( "SEKHVET_UPDATE_URL"));
#endif

    NSMutableURLRequest *anfrage = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: adresse] cachePolicy: NSURLRequestReloadIgnoringLocalCacheData timeoutInterval: 15];
    [anfrage setValue: @"application/vnd.github+json" forHTTPHeaderField: @"Accept"];
    [anfrage setValue: [NSString stringWithFormat: @"SekhVet/%ld", (long) eigenerBuild()] forHTTPHeaderField: @"User-Agent"];

    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithRequest: anfrage completionHandler: ^( NSData *daten, NSURLResponse *antwort, NSError *fehler) {
        NSInteger status = [antwort isKindOfClass: [NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*) antwort statusCode] : 200; // file:// im Test
        id json = nil;
        @try { json = daten ? [NSJSONSerialization JSONObjectWithData: daten options: 0 error: nil] : nil; }   // SekhVet Paket CS: background queue, nothing may escape
        @catch (NSException *e) { json = nil; }

        dispatch_async( dispatch_get_main_queue(), ^{
            laeuft = NO;

            // 404 auf /latest = es gibt noch kein stabiles Release; das ist "aktuell", kein Fehler.
            BOOL keinStabiles = (status == 404 && !betas);
            if( fehler || (!keinStabiles && (status != 200 || json == nil)))
            {
                NSLog( @"SekhVet update check failed: HTTP %ld %@", (long) status, fehler.localizedDescription ?: @"");
                if( ausdruecklich)
                {
                    NSAlert *a = [[[NSAlert alloc] init] autorelease];
                    a.messageText = NSLocalizedString( @"No Internet connection", nil);
                    a.informativeText = NSLocalizedString( @"Unable to check latest version available.", nil);
                    [a runModal];
                }
                return;
            }

            [d setObject: [NSDate date] forKey: @"SekhmetUpdateLetztePruefung"];

            NSDictionary *angebot = keinStabiles ? nil : [self angebotAus: json betas: betas];
            NSInteger neu = [angebot[@"build"] integerValue], hier = eigenerBuild();
            NSLog( @"SekhVet update check: this build %ld, offered %ld", (long) hier, (long) neu);

            if( angebot == nil || neu <= hier)
            {
                if( ausdruecklich)
                {
                    // SekhVet Paket CS: newest release without a build number -> say so instead of "up to date"
                    NSDictionary *unklar = keinStabiles ? nil : [self unklaresReleaseAus: json betas: betas];
                    NSAlert *a = [[[NSAlert alloc] init] autorelease];
                    if( unklar)
                    {
                        a.messageText = [NSString stringWithFormat: NSLocalizedString( @"%@ is published", nil), unklar[@"name"]];
                        a.informativeText = [NSString stringWithFormat: NSLocalizedString( @"This release carries no build number, so SekhVet cannot tell whether it is newer than your build %ld. Open the releases page to compare.", nil), (long) hier];
                        [a addButtonWithTitle: NSLocalizedString( @"Open Releases Page", nil)];
                        [a addButtonWithTitle: NSLocalizedString( @"Close", nil)];
                        if( [a runModal] == NSAlertFirstButtonReturn)
                            [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: [self sichereAdresse: unklar[@"seite"]]]];
                        return;
                    }
                    a.messageText = NSLocalizedString( @"SekhVet is up-to-date", nil);
                    a.informativeText = [NSString stringWithFormat: NSLocalizedString( @"You have the most recent version of SekhVet (build %ld).", nil), (long) hier];
                    [a runModal];
                }
                return;
            }

            if( !ausdruecklich && [d integerForKey: @"SekhmetUpdateUebersprungen"] == neu) return;

            [self zeigeAngebot: angebot hier: hier];
        });
    }];
    [t resume];
}

+ (void) zeigeAngebot:(NSDictionary*) angebot hier:(NSInteger) hier
{
    NSString *notizen = text( angebot[@"notizen"]) ?: @"";
    if( notizen.length > 700) notizen = [[notizen substringToIndex: [notizen rangeOfComposedCharacterSequenceAtIndex: 700].location] stringByAppendingString: @" …"];

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    a.messageText = [NSString stringWithFormat: NSLocalizedString( @"%@ is available", nil), angebot[@"name"]];
    a.informativeText = [NSString stringWithFormat: NSLocalizedString( @"You are using build %ld; the new version is build %ld.\n\nSekhVet does not update itself. “Download” opens your web browser, which downloads the disk image (.dmg) from GitHub. Install it by hand: quit SekhVet, open the downloaded disk image and drag SekhVet onto the Applications folder, replacing the old version. Your database and settings stay as they are.%@%@", nil),
                         (long) hier, (long) [angebot[@"build"] integerValue], notizen.length ? @"\n\n" : @"", notizen];
    [a addButtonWithTitle: NSLocalizedString( @"Download", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Release Notes", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Later", nil)];
    a.showsSuppressionButton = YES;
    a.suppressionButton.title = NSLocalizedString( @"Skip this version", nil);

    NSModalResponse r = [a runModal];

    if( a.suppressionButton.state == NSControlStateValueOn)
        [[NSUserDefaults standardUserDefaults] setInteger: [angebot[@"build"] integerValue] forKey: @"SekhmetUpdateUebersprungen"];

    // SekhVet Paket CS: checked again at the point of use -- only the SekhVet repository on github.com
    if( r == NSAlertFirstButtonReturn)
        [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: [self sichereAdresse: angebot[@"dmg"]]]];
    else if( r == NSAlertSecondButtonReturn)
        [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: [self sichereAdresse: angebot[@"seite"]]]];
}

@end
