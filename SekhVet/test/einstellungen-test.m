// SekhVet Paket DZ: unit test of the settings groups (SekhmetEinstellungen.m, logic part above SEKHVET_LOGIC_TEST).
// Call from the repository root: bash SekhVet/test/einstellungen-test.sh
#import "SekhmetEinstellungen.h"

static int pass = 0, fail = 0;
static void check( NSString *n, BOOL c, id d)
{
    if( c) { pass++; printf( "  ✅ %s\n", n.UTF8String); }
    else { fail++; printf( "  ❌ %s  %s\n", n.UTF8String, [[d description] UTF8String]); }
}

int main( void)
{
    @autoreleasepool
    {
        Class E = [SekhmetEinstellungen class];
        printf( "[Gruppen und Sperrliste]\n");
        check( @"Oeffnungsprotokolle -> opening", [[E gruppeFuerSchluessel: @"SekhmetOpeningProtocols"] isEqualToString: @"opening"], nil);
        check( @"Hanging-Regeln per Praefix", [[E gruppeFuerSchluessel: @"SekhmetVetRules2_7"] isEqualToString: @"hanging"], nil);
        check( @"MPR-Achsenfarbe per Praefix", [[E gruppeFuerSchluessel: @"MPR_AXIS_1_RED"] isEqualToString: @"display"], nil);
        check( @"WLWW3 -> window", [[E gruppeFuerSchluessel: @"WLWW3"] isEqualToString: @"window"], nil);
        check( @"SERVERS -> network", [[E gruppeFuerSchluessel: @"SERVERS"] isEqualToString: @"network"], nil);
        for( NSString *k in @[ @"STORESCP", @"AETITLE", @"AEPORT", @"publishDICOMBonjour", @"DATABASELOCATION", @"localDatabasePaths", @"SekhmetScreenAreas",
                               @"NSWindow Frame QR", @"SekhVetInstallUUID", @"SekhmetDICOMwebAutoRetrieve", @"AUTOROUTINGACTIVATED", @"RoutingRules",
                               @"WebPortalUsers", @"PluginsPath", @"SekhmetPracticeSettingsFolder", @"SekhmetSettingsBackupBuild", @"SomePassword"])
            check( [NSString stringWithFormat: @"%@ gesperrt, keine Gruppe", k], [E istGesperrt: k] && [E gruppeFuerSchluessel: k] == nil, nil);
        check( @"unbekannter Schluessel -> keine Gruppe", [E gruppeFuerSchluessel: @"irgendwas"] == nil, nil);

        printf( "[Bereinigen]\n");
        NSArray *knoten = [E bereinigt: @[ @{ @"name": @"Web", @"url": @"https://x", @"user": @"u", @"password": @"geheim", @"Passwort": @"g2", @"token": @"t", @"sub": @{ @"clientSecret": @"s", @"ok": @1}}]];
        NSDictionary *k0 = knoten[ 0];
        check( @"password/Passwort/token/secret entfernt, Rest bleibt", k0[ @"password"] == nil && k0[ @"Passwort"] == nil && k0[ @"token"] == nil && k0[ @"sub"][ @"clientSecret"] == nil && [k0[ @"sub"][ @"ok"] isEqual: @1] && [k0[ @"user"] isEqual: @"u"], k0);

        printf( "[Export und Uebernahme]\n");
        NSDictionary *domain = @{ @"SekhmetOpeningProtocols": @[ @{ @"name": @"CT spine"}], @"SekhmetOpeningEnabled": @YES, @"STORESCP": @YES, @"AETITLE": @"MAC1",
                                  @"SekhmetVetRules2_1": @{ @"a": @1}, @"SekhmetDICOMwebNodes": @[ @{ @"name": @"Web", @"password": @"geheim"}], @"irgendwas": @3};
        NSDictionary *werte = [E gruppenAus: domain gruppen: @[ @"opening", @"hanging", @"network"]];
        check( @"Export: nur Gruppenschluessel", [werte[ @"opening"] count] == 2 && [werte[ @"hanging"] count] == 1 && werte[ @"window"] == nil, werte);
        check( @"Export: kein Passwort im Netzwerk-Knoten", werte[ @"network"][ @"SekhmetDICOMwebNodes"][ 0][ @"password"] == nil && [werte[ @"network"][ @"SekhmetDICOMwebNodes"][ 0][ @"name"] isEqual: @"Web"], werte[ @"network"]);
        NSDictionary *ziel = @{ @"SekhmetOpeningProtocols": @[ @{ @"name": @"eigen"}], @"SekhmetOpeningSmallMax": @4, @"STORESCP": @NO, @"SekhmetVetRules2_9": @{ @"b": @2}, @"FONTSIZE": @14};
        NSDictionary *neu = [E domain: ziel nachUebernahmeVon: werte gruppen: @[ @"opening"]];
        check( @"Uebernahme ersetzt die Gruppe als Ganzes", [neu[ @"SekhmetOpeningProtocols"] isEqual: domain[ @"SekhmetOpeningProtocols"]] && neu[ @"SekhmetOpeningSmallMax"] == nil && [neu[ @"SekhmetOpeningEnabled"] isEqual: @YES], neu);
        check( @"Uebernahme laesst andere Gruppen und Gesperrtes stehen", [neu[ @"STORESCP"] isEqual: @NO] && [neu[ @"SekhmetVetRules2_9"] isEqual: @{ @"b": @2}] && [neu[ @"FONTSIZE"] isEqual: @14] && neu[ @"AETITLE"] == nil, neu);
        NSDictionary *neu2 = [E domain: ziel nachUebernahmeVon: werte gruppen: @[ @"hanging"]];
        check( @"Praefix-Gruppe: alte Regeln weg, neue da", neu2[ @"SekhmetVetRules2_9"] == nil && [neu2[ @"SekhmetVetRules2_1"] isEqual: @{ @"a": @1}], neu2);
        NSDictionary *boese = @{ @"opening": @{ @"STORESCP": @YES, @"SekhmetOpeningEnabled": @NO}};
        NSDictionary *neu3 = [E domain: ziel nachUebernahmeVon: boese gruppen: @[ @"opening"]];
        check( @"fremder Schluessel in einer Gruppe wird nicht uebernommen", [neu3[ @"STORESCP"] isEqual: @NO] && [neu3[ @"SekhmetOpeningEnabled"] isEqual: @NO], neu3);

        printf( "[Datei pruefen]\n");
        NSDictionary *datei = [E dateiInhaltAus: werte build: 183 version: @"1.1" rechner: @"Mac A"];
        NSString *f = nil;
        NSDictionary *g = [E gepruefterDateiInhalt: datei fehler: &f];
        check( @"eigene Datei ist gueltig", g != nil && [g[ @"Build"] isEqual: @183] && [g[ @"Groups"] count] == 3, f);
        NSMutableDictionary *manip = [NSMutableDictionary dictionaryWithDictionary: datei];
        manip[ @"Groups"] = @{ @"opening": @{ @"SekhmetOpeningEnabled": @YES, @"AETITLE": @"BOESE"}, @"evil": @{ @"x": @1}, @"window": @"keinDict"};
        g = [E gepruefterDateiInhalt: manip fehler: &f];
        check( @"manipulierte Datei: gesperrter Schluessel, fremde Gruppe, falscher Typ verworfen", [g[ @"Groups"][ @"opening"] count] == 1 && g[ @"Groups"][ @"evil"] == nil && g[ @"Groups"][ @"window"] == nil, g);
        check( @"keine Einstellungsdatei -> Fehler", [E gepruefterDateiInhalt: @[ @1] fehler: &f] == nil && f.length, f);
        check( @"neueres Format -> Fehler", [E gepruefterDateiInhalt: @{ @"SekhVetSettings": @2, @"Groups": @{}} fehler: &f] == nil, f);

        printf( "[Zusammenfassung]\n");
        NSString *z = [E zusammenfassungVon: @{ @"SekhmetOpeningProtocols": @[ @{ @"name": @"CT Kopf"}, @{ @"name": @"CT"}]}
                                        nach: @{ @"SekhmetOpeningProtocols": @[ @{ @"name": @"CT head"}, @{ @"name": @"CT spine"}, @{ @"name": @"CT"}]} gruppe: @"opening"];
        check( @"Namen: neu und entfernt", [z rangeOfString: @"2 → 3"].location != NSNotFound && [z rangeOfString: @"new: CT head, CT spine"].location != NSNotFound && [z rangeOfString: @"removed: CT Kopf"].location != NSNotFound, z);
        check( @"keine Aenderung -> nil", [E zusammenfassungVon: @{ @"FONTSIZE": @12} nach: @{ @"FONTSIZE": @12} gruppe: @"display"] == nil, nil);
        z = [E zusammenfassungVon: @{ @"FONTSIZE": @12, @"ROIThickness": @2} nach: @{ @"FONTSIZE": @14} gruppe: @"display"];
        check( @"einfache Werte gezaehlt", [z isEqualToString: @"2 settings change"], z);
        check( @"Vorgabe-Versionen fuer alle Gruppen", [[E vorgabeVersionen] count] == [[E gruppen] count], [E vorgabeVersionen]);
    }
    printf( "%s (%d)\n", fail ? "▸ ROT" : "▸ GRÜN", fail ? fail : pass);
    return fail ? 1 : 0;
}
