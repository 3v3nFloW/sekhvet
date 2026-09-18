/*=========================================================================
 Sekhmet — veterinaere Orientierung, Implementierung. Siehe Header.
 ============================================================================*/

#import "SekhmetMPRKategorie.h" // SekhVet Stufe 6c
#import "SekhmetOrientation.h"
#import "SekhmetTesthaken.h" // SekhVet: Testhaken nur mit Build-Flag SEKHVET_TESTHAKEN=1
#if SEKHVET_TESTHAKEN
#import "SekhmetDCMViewKategorie.h" // only the point tests call into this category
#endif // SEKHVET_TESTHAKEN
#import "ViewerController.h"
#import "DCMView.h"
#import "DCMPix.h"
#import "DicomStudy.h"
#import "DicomSeries.h"
#import "Notifications.h"
#import "DCM.h"
#import "MPRController.h"
#import "MPRDCMView.h"
#import "VRView.h"
#import "Camera.h"
#import "Point3D.h"

NSString* const SekhmetVetPresetKey = @"SekhmetVetOrientationPreset";
NSString* const SekhmetVetKeywordsKey = @"SekhmetVetOrientationKeywords";
NSString* const SekhmetDXRulesKey = @"SekhmetDXRules";
NSString* const SekhmetVetPresetDidChangeNotification = @"SekhmetVetPresetDidChangeNotification";

NSString* const SekhmetRuleTransversalDorsalUp = @"transversalDorsalUp";
NSString* const SekhmetRuleSagittalCranialLeft = @"sagittalCranialLeft";
NSString* const SekhmetRuleDorsalCranialUp = @"dorsalCranialUp";
NSString* const SekhmetRuleLeftOnRight = @"leftOnRight";
NSString* const SekhmetRuleProximalCaudal = @"proximalCaudal"; // SekhVet Paket AF
NSString* const SekhmetMPRLayoutsKey = @"SekhmetMPRLayouts";      // SekhVet Paket AX

// SekhVet Paket AX: Horos' Grundbelegung der drei MPR-Fenster, gemessen 16.09.2026 an einer Wirbelsaeulen-CT
// (hp-dreh-test.sh, erste Protokollzeile vor jedem Eingriff): Normale x / z / y.
static const int sekhmetDefaultMPRAxis[3] = { 0, 2, 1 };

typedef enum { SekhmetPlaneOblique = 0, SekhmetPlaneTransversal, SekhmetPlaneSagittal, SekhmetPlaneDorsal } SekhmetPlane;

static NSMutableDictionary *sekhmetOverrides = nil;      // studyUID -> preset
static NSMutableDictionary *sekhmetStatus = nil;         // NSValue(viewer) -> status
static NSMutableDictionary *sekhmetStationCache = nil;   // srcFile -> StationName

@interface SekhmetOrientation ()
+ (NSString*) applyToViewerInternal:(ViewerController*) v;
+ (NSString*) applyDXRulesToView:(DCMView*) view pix:(DCMPix*) pix modality:(NSString*) modality;
+ (NSString*) stationNameForPix:(DCMPix*) pix;
+ (void) setStatus:(NSString*) status forViewer:(ViewerController*) v;
+ (BOOL) view:(DCMView*) view showsTop:(NSString*) top left:(NSString*) left;
+ (void) setView:(DCMView*) view rotation:(float) r xFlipped:(BOOL) x yFlipped:(BOOL) y;
+ (NSString*) L:(NSString*) letter;
+ (SekhmetPlane) planeForPix:(DCMPix*) pix;
+ (NSDictionary*) defaultRulesForPreset:(NSInteger) preset;
+ (NSArray*) defaultKeywords;
+ (void) viewerWillClose:(NSNotification*) n;
+ (void) straightenMPR:(MPRController*) c preset:(NSInteger) preset;   // SekhVet Paket AN, AX: Achse je Fenster aus dem Preset
+ (BOOL) crossPointOfMPR:(MPRController*) c into:(float*) K;   // SekhVet Paket AN
+ (void) shiftMPR:(MPRController*) c by:(const float*) delta;  // SekhVet Paket AN
@end

// Sekhmet: veterinaere Randbuchstaben — nur Anzeige, Rumpf-Abbildung (keine Gliedmassen-Buchstaben)
NSString* SekhmetVetLetter( NSString* letter)
{
    if( [[NSUserDefaults standardUserDefaults] boolForKey: @"VetOrientationLetters"] == NO) return letter;
    if( [letter isEqualToString: NSLocalizedString( @"A", @"A: Anterior")]) return @"V";
    if( [letter isEqualToString: NSLocalizedString( @"P", @"P: Posterior")]) return @"D";
    if( [letter isEqualToString: NSLocalizedString( @"S", @"S: Superior")]) return @"Cr";
    if( [letter isEqualToString: NSLocalizedString( @"I", @"I: Inferior")]) return @"Cd";
    return letter;
}

@implementation SekhmetOrientation

+ (void) initialize
{
    if( self == [SekhmetOrientation class])
    {
        sekhmetOverrides = [[NSMutableDictionary alloc] init];
        NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey: @"SekhmetVetPresetOverrides"]; // SekhVet Paket AF: Wahl je Studie bleibt ueber Neustarts erhalten
        if( saved) [sekhmetOverrides addEntriesFromDictionary: saved];
        sekhmetStatus = [[NSMutableDictionary alloc] init];
        sekhmetStationCache = [[NSMutableDictionary alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(viewerWillClose:) name: OsirixCloseViewerNotification object: nil];
    }
}

+ (void) viewerWillClose:(NSNotification*) n
{
    if( [n object])
        [sekhmetStatus removeObjectForKey: [NSValue valueWithPointer: [n object]]];
}

#pragma mark - Defaults

+ (NSDictionary*) defaultRulesForPreset:(NSInteger) preset
{
    // Die vier vetHP-Regeln; Extremitaeten: proximal oben statt kranial links.
    // SekhVet Paket AF: Vorderbein (nach vorn gestreckt) -> proximal ist kaudal -> kaudal oben (Screenshot 11.09.: Cd oben, D links / Cd oben, R links)
    BOOL limb = (preset == SekhmetPresetHindlimb || preset == SekhmetPresetForelimb);
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool: YES], SekhmetRuleTransversalDorsalUp,
            [NSNumber numberWithBool: !limb], SekhmetRuleSagittalCranialLeft,
            [NSNumber numberWithBool: YES], SekhmetRuleDorsalCranialUp,
            [NSNumber numberWithBool: YES], SekhmetRuleLeftOnRight,
            [NSNumber numberWithBool: (preset == SekhmetPresetForelimb)], SekhmetRuleProximalCaudal,
            nil];
}

+ (NSArray*) defaultKeywords
{
    NSMutableArray *a = [NSMutableArray array];
    NSArray *head = [NSArray arrayWithObjects: @"Kopf", @"Schädel", @"Schaedel", @"Skull", @"Head", @"Wirbel", @"Spine", @"HWS", @"BWS", @"LWS", @"Hals", @"Neck", @"Gehirn", @"Brain", nil];
    NSArray *fore = [NSArray arrayWithObjects: @"Ellbogen", @"Elbow", @"Schulter", @"Shoulder", @"Karpus", @"Carpus", @"Vordergliedmasse", @"Vorderbein", @"Forelimb", @"Humerus", @"Radius", @"Ulna", @"Extremit", @"Limb", @"Zehe", @"Pfote", nil]; // SekhVet Paket AF
    NSArray *limb = [NSArray arrayWithObjects: @"Knie", @"Stifle", @"Tarsus", @"Sprunggelenk", @"Hüfte", @"Huefte", @"Hip", @"Hintergliedmasse", @"Hinterbein", @"Hindlimb", @"Femur", @"Tibia", @"Becken", @"Pelvis", nil];
    for( NSString *k in head)
        [a addObject: [NSDictionary dictionaryWithObjectsAndKeys: k, @"keyword", [NSNumber numberWithInteger: SekhmetPresetHeadSpine], @"preset", nil]];
    for( NSString *k in fore)
        [a addObject: [NSDictionary dictionaryWithObjectsAndKeys: k, @"keyword", [NSNumber numberWithInteger: SekhmetPresetForelimb], @"preset", nil]];
    for( NSString *k in limb)
        [a addObject: [NSDictionary dictionaryWithObjectsAndKeys: k, @"keyword", [NSNumber numberWithInteger: SekhmetPresetHindlimb], @"preset", nil]];
    return a;
}

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues
{
    [defaultValues setObject: [NSNumber numberWithInteger: SekhmetPresetHeadSpine] forKey: SekhmetVetPresetKey];
    for( NSInteger p = SekhmetPresetHeadSpine; p <= SekhmetPresetLast; p++)
        [defaultValues setObject: [self defaultRulesForPreset: p] forKey: [self rulesKeyForPreset: p]];
    [defaultValues setObject: [self defaultKeywords] forKey: SekhmetVetKeywordsKey];
    [defaultValues setObject: [NSArray array] forKey: SekhmetDXRulesKey];
}

+ (NSArray*) presetNames
{
    // Index = Preset (SekhmetPreset…); SekhVet Paket AF: Forelimbs/Hindlimbs getrennt, zwei programmierbare Protokolle
    return [NSArray arrayWithObjects:
            NSLocalizedString( @"Off", nil),
            NSLocalizedString( @"Head / Spine", nil),
            NSLocalizedString( @"Hindlimbs", nil),
            NSLocalizedString( @"Forelimbs", nil),
            NSLocalizedString( @"Custom 1", nil),
            NSLocalizedString( @"Custom 2", nil), nil];
}

+ (NSString*) rulesKeyForPreset:(NSInteger) preset
{
    return [NSString stringWithFormat: @"SekhmetVetRules2_%d", (int) preset]; // SekhVet Paket AF: neue Nummerierung (3 war "Custom"), alte Schluessel bleiben unbenutzt
}

+ (NSDictionary*) rulesForPreset:(NSInteger) preset
{
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey: [self rulesKeyForPreset: preset]];
    if( d == nil) d = [self defaultRulesForPreset: preset];
    return d;
}

+ (void) setRules:(NSDictionary*) rules forPreset:(NSInteger) preset
{
    [[NSUserDefaults standardUserDefaults] setObject: rules forKey: [self rulesKeyForPreset: preset]];
}

#pragma mark - Preset-Wahl

+ (NSString*) descriptionForViewer:(ViewerController*) v
{
    NSMutableString *s = [NSMutableString string];
    @try
    {
        NSString *a = [[v currentStudy] valueForKey: @"studyName"];
        NSString *b = [[v currentSeries] valueForKey: @"name"];
        if( a) [s appendString: a];
        if( b) [s appendFormat: @" %@", b];
    }
    @catch (NSException *e) { }
    return s;
}

+ (NSInteger) presetForStudyUID:(NSString*) uid description:(NSString*) description
{
    if( uid && [sekhmetOverrides objectForKey: uid])
        return [[sekhmetOverrides objectForKey: uid] integerValue];

    if( description.length)
    {
        for( NSDictionary *k in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetVetKeywordsKey])
        {
            NSString *keyword = [k objectForKey: @"keyword"];
            if( keyword.length && [description rangeOfString: keyword options: NSCaseInsensitiveSearch].location != NSNotFound)
                return [[k objectForKey: @"preset"] integerValue];
        }
    }
    return [[NSUserDefaults standardUserDefaults] integerForKey: SekhmetVetPresetKey];
}

+ (void) setPresetOverride:(NSInteger) preset forStudyUID:(NSString*) uid
{
    if( uid == nil) return;
    if( preset < 0) [sekhmetOverrides removeObjectForKey: uid];
    else [sekhmetOverrides setObject: [NSNumber numberWithInteger: preset] forKey: uid];
    [[NSUserDefaults standardUserDefaults] setObject: sekhmetOverrides forKey: @"SekhmetVetPresetOverrides"]; // SekhVet Paket AF
}

#pragma mark - Geometrie

+ (SekhmetPlane) planeForPix:(DCMPix*) pix
{
    float o[ 9];
    [pix orientation: o];

    // Normale aus Zeilen- und Spaltenvektor
    float nx = o[1]*o[5] - o[2]*o[4];
    float ny = o[2]*o[3] - o[0]*o[5];
    float nz = o[0]*o[4] - o[1]*o[3];
    float ax = fabs( nx), ay = fabs( ny), az = fabs( nz);
    const float limit = 0.85; // ~32 Grad Toleranz, darueber gilt die Serie als schraeg

    if( az >= limit && az >= ax && az >= ay) return SekhmetPlaneTransversal;
    if( ax >= limit && ax >= ay && ax >= az) return SekhmetPlaneSagittal;
    if( ay >= limit && ay >= ax && ay >= az) return SekhmetPlaneDorsal;
    return SekhmetPlaneOblique;
}

+ (NSString*) L:(NSString*) letter
{
    // DICOM-Buchstabe -> angezeigter Buchstabe (inkl. Vet-Abbildung, falls eingeschaltet)
    return SekhmetVetLetter( letter);
}

+ (NSString*) oppositeDisplayedLetter:(NSString*) d // SekhVet Paket AF: Gegenrichtung eines angezeigten Buchstabens (V<->D, Cr<->Cd, L<->R)
{
    NSArray *pairs = [NSArray arrayWithObjects: @"A", @"P", @"S", @"I", @"L", @"R", nil];
    for( int k = 0; k < 6; k += 2)
    {
        if( [d isEqualToString: [self L: [pairs objectAtIndex: k]]]) return [self L: [pairs objectAtIndex: k + 1]];
        if( [d isEqualToString: [self L: [pairs objectAtIndex: k + 1]]]) return [self L: [pairs objectAtIndex: k]];
    }
    return d;
}

+ (BOOL) view:(DCMView*) view showsTop:(NSString*) top left:(NSString*) left
{
    NSString *shownLeft = nil, *shownTop = nil;
    [self lettersForView: view left: &shownLeft top: &shownTop];
    return [shownLeft hasPrefix: left] && [shownTop hasPrefix: top];
}

+ (void) setView:(DCMView*) view rotation:(float) r xFlipped:(BOOL) x yFlipped:(BOOL) y
{
    view.yFlipped = y;
    view.xFlipped = x;
    view.rotation = r;
}

+ (BOOL) targetTop:(NSString**) top left:(NSString**) left forPlane:(SekhmetPlane) plane preset:(NSInteger) preset
{
    NSDictionary *rules = [self rulesForPreset: preset];
    BOOL dorsalUp = [[rules objectForKey: SekhmetRuleTransversalDorsalUp] boolValue];
    BOOL cranialLeft = [[rules objectForKey: SekhmetRuleSagittalCranialLeft] boolValue];
    BOOL cranialUp = [[rules objectForKey: SekhmetRuleDorsalCranialUp] boolValue];
    BOOL leftOnRight = [[rules objectForKey: SekhmetRuleLeftOnRight] boolValue];
    BOOL proximalCaudal = [[rules objectForKey: SekhmetRuleProximalCaudal] boolValue]; // SekhVet Paket AF

    NSString *A = NSLocalizedString( @"A", @"A: Anterior"), *P = NSLocalizedString( @"P", @"P: Posterior");
    NSString *S = NSLocalizedString( @"S", @"S: Superior"), *L = NSLocalizedString( @"L", @"L: Left"), *R = NSLocalizedString( @"R", @"R: Right");
    NSString *I = NSLocalizedString( @"I", @"I: Inferior");
    NSString *up = proximalCaudal ? I : S;            // SekhVet Paket AF: "oben" der Laengsachse = kranial oder kaudal
    NSString *sagLeft = proximalCaudal ? P : A;       // 180-Grad-Drehung der Sagittalen: kaudal oben, dorsal links
    NSString *t = nil, *l = nil;

    switch( plane)
    {
        case SekhmetPlaneTransversal:
            t = dorsalUp ? P : A;
            l = leftOnRight ? R : L;
            break;
        case SekhmetPlaneSagittal:
            if( cranialLeft) { l = up; t = P; }
            else { t = up; l = sagLeft; }
            break;
        case SekhmetPlaneDorsal:
            if( cranialUp) { t = up; l = leftOnRight ? R : L; }
            else { l = up; t = leftOnRight ? L : R; }
            break;
        default: return NO;
    }
    *top = [self L: t];
    *left = [self L: l];
    return YES;
}

// Randbuchstaben links/oben genau so, wie DCMView sie zeichnet (drawOrientation: orientationCorrectedToView + getOrientationText)
+ (void) lettersForView:(DCMView*) view left:(NSString**) left top:(NSString**) top
{
    float vectors[ 9]; char s[ 10];
    [view orientationCorrectedToView: vectors];
    [view getOrientationText: s : vectors : YES];
    *left = [NSString stringWithUTF8String: s];
    [view getOrientationText: s : vectors+3 : YES];
    *top = [NSString stringWithUTF8String: s];
}

#if SEKHVET_TESTHAKEN
+ (NSString*) debugLettersForView:(DCMView*) view
{
    NSString *l = nil, *t = nil;
    [self lettersForView: view left: &l top: &t];
    return [NSString stringWithFormat: @"links=%@ oben=%@ rot=%.0f x=%d y=%d", l, t, view.rotation, view.xFlipped, view.yFlipped];
}
#endif // SEKHVET_TESTHAKEN

// Rodrigues: v um die Einheitsachse axis um deg Grad drehen
static void sekhmetRotate( float *v, const float *axis, float deg)
{
    float t = deg * M_PI / 180., c = cosf( t), s = sinf( t);
    float d = axis[0]*v[0] + axis[1]*v[1] + axis[2]*v[2];
    float cx = axis[1]*v[2] - axis[2]*v[1], cy = axis[2]*v[0] - axis[0]*v[2], cz = axis[0]*v[1] - axis[1]*v[0];
    float r0 = v[0]*c + cx*s + axis[0]*d*(1-c), r1 = v[1]*c + cy*s + axis[1]*d*(1-c), r2 = v[2]*c + cz*s + axis[2]*d*(1-c);
    v[0] = r0; v[1] = r1; v[2] = r2;
}

// 3D-MPR: VRView legt das Volumen im Patientenraum ab, die Kamera-Achsen sind also DICOM-Richtungen. Je Ebene werden
// Seite (Kamera vor/hinter der Ebene = Spiegelung) und Aufwaerts-Vektor (0/90/180/270 Grad) probiert, bis die Randbuchstaben
// oben/links den Regeln entsprechen; geprueft wird mit denselben Buchstaben-Funktionen wie in der 2D-Ansicht.
// SekhVet Paket AN: Die drei MPR-Ebenen wieder auf die Volumenachsen stellen, ohne den Ort zu verlieren.
// Grund (Rueckmeldung 13.09.): von der Wirbelsaeule zum Knie scrollen, Protokoll auf Hindlimbs wechseln, spaeter zurueck
// auf Kopf/Wirbelsaeule -- die Ebenen blieben schraeg stehen, die Kandidatensuche in applyToMPR probiert aber nur
// 4x90 Grad um die AKTUELLE Normale und findet dann keine passende Lage ("nicht korrigierbar"). Darum vor der Suche:
// Normale und Aufwaertsvektor je Ansicht auf die naechste Hauptachse runden (jede Achse nur einmal vergeben) und
// alle drei Ansichten auf den bisherigen Kreuzungspunkt der Ebenen zentrieren.
static int sekhmetMainAxis( const float *v, int taken)   // Index der groessten Komponente, die noch frei ist
{
    int best = -1; float bestVal = -1;
    for( int k = 0; k < 3; k++)
    {
        if( taken & (1 << k)) continue;
        if( fabsf( v[ k]) > bestVal) { bestVal = fabsf( v[ k]); best = k; }
    }
    return best;
}

// Schnittpunkt dreier Ebenen (n_i . x = d_i) ueber die Cramersche Regel; NO, wenn sie fast parallel liegen
static BOOL sekhmetPlanesIntersection( float n[3][3], float d[3], float *out)
{
    float det = n[0][0]*(n[1][1]*n[2][2] - n[1][2]*n[2][1])
              - n[0][1]*(n[1][0]*n[2][2] - n[1][2]*n[2][0])
              + n[0][2]*(n[1][0]*n[2][1] - n[1][1]*n[2][0]);
    if( fabsf( det) < 1e-4) return NO;
    for( int col = 0; col < 3; col++)
    {
        float m[3][3];
        for( int r = 0; r < 3; r++)
            for( int k = 0; k < 3; k++) m[r][k] = (k == col) ? d[r] : n[r][k];
        float dc = m[0][0]*(m[1][1]*m[2][2] - m[1][2]*m[2][1])
                 - m[0][1]*(m[1][0]*m[2][2] - m[1][2]*m[2][0])
                 + m[0][2]*(m[1][0]*m[2][1] - m[1][1]*m[2][0]);
        out[ col] = dc / det;
    }
    return YES;
}

// Kreuzungspunkt der drei Schnittebenen (Ebene i liegt an der Kameraposition, Normale = Blickrichtung)
+ (BOOL) crossPointOfMPR:(MPRController*) c into:(float*) K
{
    float n[3][3], d[3], P[3][3];
    for( int i = 0; i < 3; i++)
    {
        Camera *cam = [[c sekhmetView: i] camera];
        if( cam == nil || cam.position == nil || cam.focalPoint == nil) return NO;
        P[i][0] = cam.position.x; P[i][1] = cam.position.y; P[i][2] = cam.position.z;
        float f[3] = { cam.focalPoint.x, cam.focalPoint.y, cam.focalPoint.z };
        for( int k = 0; k < 3; k++) n[i][k] = P[i][k] - f[k];
        float l = sqrtf( n[i][0]*n[i][0] + n[i][1]*n[i][1] + n[i][2]*n[i][2]);
        if( l <= 0) return NO;
        for( int k = 0; k < 3; k++) n[i][k] /= l;
        d[i] = n[i][0]*P[i][0] + n[i][1]*P[i][1] + n[i][2]*P[i][2];
    }
    if( sekhmetPlanesIntersection( n, d, K) == NO)
    {
        for( int k = 0; k < 3; k++) K[k] = (P[0][k] + P[1][k] + P[2][k]) / 3.f;
        return NO;
    }
    return YES;
}

// Alle drei Ebenen um denselben Vektor verschieben (Ausrichtung bleibt)
+ (void) shiftMPR:(MPRController*) c by:(const float*) delta
{
    if( fabsf( delta[0]) + fabsf( delta[1]) + fabsf( delta[2]) < 0.01) return;
    for( int i = 0; i < 3; i++)
    {
        MPRDCMView *v = [c sekhmetView: i];
        Camera *cam = v.camera;
        if( cam == nil || cam.position == nil || cam.focalPoint == nil) continue;
        Camera *t = [[[Camera alloc] initWithCamera: cam] autorelease];
        t.position = [Point3D pointWithX: cam.position.x + delta[0] y: cam.position.y + delta[1] z: cam.position.z + delta[2]];
        t.focalPoint = [Point3D pointWithX: cam.focalPoint.x + delta[0] y: cam.focalPoint.y + delta[1] z: cam.focalPoint.z + delta[2]];
        t.forceUpdate = YES;
        v.camera = t;
        [v restoreCamera];
    }
    for( int i = 0; i < 3; i++) { [[c sekhmetView: i] restoreCamera]; [[c sekhmetView: i] updateViewMPR]; }
}

+ (void) straightenMPR:(MPRController*) c preset:(NSInteger) preset
{
    // SekhVet Paket AX: Horos' eigenen Reset (MPRController showWindow:) nachbauen — um den Kreuzungspunkt
    // herum und mit der Achsbelegung des Presets.
    // Warum nicht mehr jede Kamera einzeln setzen (Paket AN): Horos leitet die Ebenen der beiden anderen
    // Fenster bei JEDEM Update des aktiven Fensters aus dessen Bildausrichtung ab (MPRController
    // computeCrossReferenceLines:, Block "Center other views on the sender view"). Drei einzeln gesetzte
    // Kameras passen dazu nicht; beim naechsten Update vertauscht Horos zwei Ebenen. Gemessen 16.09.2026
    // (hp-dreh-test.sh, Wirbelsaeulen-CT): nach dem Geraderichten lasen Fenster 1 und 2 die Kamera des jeweils
    // anderen. Hier entsteht nur Fenster 1 von Hand, Fenster 2 und 3 leitet Horos selbst ab.
    float dist[3], K[3];
    BOOL broken = NO;
    for( int i = 0; i < 3 && !broken; i++)
    {
        Camera *cam = [[c sekhmetView: i] camera];
        if( cam == nil || cam.position == nil || cam.focalPoint == nil || cam.viewUp == nil) { broken = YES; break; }
        float n[3] = { cam.position.x - cam.focalPoint.x, cam.position.y - cam.focalPoint.y, cam.position.z - cam.focalPoint.z };
        float u[3] = { cam.viewUp.x, cam.viewUp.y, cam.viewUp.z };
        dist[i] = sqrtf( n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
        float lu = sqrtf( u[0]*u[0] + u[1]*u[1] + u[2]*u[2]);
        if( !(dist[i] > 0) || !isfinite( dist[i]) || !(lu > 0) || !isfinite( lu) || !isfinite( cam.parallelScale)) broken = YES;
        else if( fabsf( n[0]*u[0] + n[1]*u[1] + n[2]*u[2]) / (dist[i] * lu) > 0.9f) broken = YES;   // oben laengs der Blickrichtung: VTK rechnet NaN
    }
    if( !broken)
    {
        [self crossPointOfMPR: c into: K];   // fast parallele Ebenen: Mittel der Kamerapositionen
        if( !isfinite( K[0]) || !isfinite( K[1]) || !isfinite( K[2])) broken = YES;
    }
    if( broken)
    {
        // Aus einem kaputten Stand laesst sich nichts ableiten: Horos' eigener Reset (Werkzeugleiste "Reset").
        // showWindow: plant danach das Hanging Protocol selbst wieder ein.
        NSLog( @"SekhVet HP MPR: unusable camera state - Horos reset");
        [c showWindow: nil];
        return;
    }

    int ax[3];
    for( int i = 0; i < 3; i++) ax[i] = [self mprAxisForView: i preset: preset];
    if( ax[0] == ax[1] || ax[0] == ax[2] || ax[1] == ax[2]) for( int i = 0; i < 3; i++) ax[i] = sekhmetDefaultMPRAxis[i];

    MPRDCMView *v1 = [c sekhmetView: 0], *v2 = [c sekhmetView: 1], *v3 = [c sekhmetView: 2];
    NSWindow *w = [c window];
    NSResponder *before = [w firstResponder];
    v1.angleMPR = 0; v2.angleMPR = 0; v3.angleMPR = 0;

    // Fenster 1: Normale = seine Achse, oben = Achse von Fenster 2. Die Kopplung legt Fenster 2 auf die
    // Spalten- und Fenster 3 auf die Zeilenrichtung von Fenster 1 (bei angleMPR 0).
    float e[3] = { 0, 0, 0 }, u[3] = { 0, 0, 0 };
    e[ ax[0]] = 1; u[ ax[1]] = 1;
    Camera *cam = [[[Camera alloc] initWithCamera: v1.camera] autorelease];
    cam.position = [Point3D pointWithX: K[0] y: K[1] z: K[2]];
    cam.focalPoint = [Point3D pointWithX: K[0] - dist[0]*e[0] y: K[1] - dist[0]*e[1] z: K[2] - dist[0]*e[2]];
    cam.viewUp = [Point3D pointWithX: u[0] y: u[1] z: u[2]];
    cam.rollAngle = 0;
    cam.forceUpdate = YES;
    v1.camera = cam;
    // Aufwaertsvektoren von Fenster 2 und 3 VOR der Kopplung setzen (Horos setzt sie danach, startet aber
    // immer aus seinem Grundzustand). Die Kopplung setzt nur Position und Blickpunkt; stuende der alte
    // Aufwaertsvektor laengs der neuen Blickrichtung, rechnete VTK NaN (gemessen 16.09.).
    // Die Grundbelegung ergibt genau Horos' Werte: Fenster 2 (0,-1,0), Fenster 3 (0,0,1).
    float u2[3] = { 0, 0, 0 }, u3[3] = { 0, 0, 0 };
    u2[ ax[2]] = -1; u3[ ax[1]] = 1;
    v2.camera.viewUp = [Point3D pointWithX: u2[0] y: u2[1] z: u2[2]];
    v2.camera.rollAngle = 0;
    v3.camera.viewUp = [Point3D pointWithX: u3[0] y: u3[1] z: u3[2]];
    v3.camera.rollAngle = 0;
    [w makeFirstResponder: v1];
    [v1 restoreCamera];
    [v1 updateViewMPR];

    // Wie Horos danach: Kopplung einmal von Fenster 3 aus
    [w makeFirstResponder: v3];
    v3.angleMPR = 0;
    [v3 restoreCamera];
    [v3 updateViewMPR];

    if( before) [w makeFirstResponder: before];
    NSLog( @"SekhVet HP MPR reset: axes %d/%d/%d, crossing point (%.1f %.1f %.1f)", ax[0], ax[1], ax[2], K[0], K[1], K[2]);
}

+ (NSString*) applyToMPR:(MPRController*) c
{
    return [self applyToMPR: c straighten: NO];
}

+ (NSString*) applyToMPR:(MPRController*) c straighten:(BOOL) straighten
{
    if( c == nil || [c windowWillClose]) return nil;
    NSInteger preset = [self presetForMPR: c];
    NSArray *layout = preset == SekhmetPresetOff ? nil : [self mprLayoutForPreset: preset];
    // SekhVet Paket AX: beim Oeffnen stehen die Ebenen in Horos' Grundbelegung; weicht die Anordnung des
    // Presets davon ab, muss auch dann umgelegt werden.
    if( !straighten && layout)
        for( int i = 0; i < 3; i++) if( [self mprAxisForView: i preset: preset] != sekhmetDefaultMPRAxis[i]) straighten = YES;
    float crossBefore[3] = { 0, 0, 0 };
    BOOL keepCross = straighten && [self crossPointOfMPR: c into: crossBefore];
    if( straighten) [self straightenMPR: c preset: preset];   // SekhVet Paket AN/AX: Ebenen auf die Achsen des Presets
    if( preset == SekhmetPresetOff) return nil;

    // SekhVet Paket AX: oben/links ueber (a) eine Drehung der Kamera um ihre eigene Blickrichtung und
    // (b) die Spiegelung der Anzeige. Die Blickseite bleibt, wie Horos' Kopplung sie ableitet. Nach der Drehung
    // wird angleMPR genau so nachgefuehrt wie in Horos' Drehwerkzeug (MPRDCMView mouseDragged, tRotate) —
    // sonst legt die Kopplung beim naechsten Update die anderen Ebenen falsch (Paket AF drehte ohne Ausgleich
    // und kehrte die Blickseite um; gemessen 16.09.: zwei Ebenen vertauscht). Eine Anzeige-Drehung geht im MPR
    // nicht: MPRDCMView subDrawRect: setzt rotation bei jedem Zeichnen auf 0.
    int done = 0, skipped = 0;
    for( int i = 0; i < 3; i++)
    {
        MPRDCMView *v = [c sekhmetView: i];
        Camera *cam = v.camera;
        if( cam == nil || cam.position == nil || cam.focalPoint == nil) { NSLog( @"SekhVet Hanging Protocol MPR: view %d without camera - skipped", i); continue; }

        float n[3] = { cam.position.x - cam.focalPoint.x, cam.position.y - cam.focalPoint.y, cam.position.z - cam.focalPoint.z };
        float len = sqrtf( n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
        if( !(len > 0)) continue;
        n[0] /= len; n[1] /= len; n[2] /= len;

        float ax = fabsf( n[0]), ay = fabsf( n[1]), az = fabsf( n[2]);
        const float limit = 0.85;
        SekhmetPlane plane = SekhmetPlaneOblique;
        if( az >= limit && az >= ax && az >= ay) plane = SekhmetPlaneTransversal;
        else if( ax >= limit && ax >= ay && ax >= az) plane = SekhmetPlaneSagittal;
        else if( ay >= limit && ay >= ax && ay >= az) plane = SekhmetPlaneDorsal;
        if( plane == SekhmetPlaneOblique) { skipped++; continue; }

        NSString *top = nil, *left = nil;
        if( layout)   // SekhVet Paket AX: Buchstaben aus "Take from screen"
        {
            NSDictionary *lv = [layout objectAtIndex: i];
            int want = [[lv objectForKey: @"axis"] intValue];
            int have = plane == SekhmetPlaneSagittal ? 0 : plane == SekhmetPlaneDorsal ? 1 : 2;
            if( want != have) { NSLog( @"SekhVet Hanging Protocol MPR: view %d shows axis %d, the layout wants axis %d - skipped", i, have, want); continue; }
            top = [self L: [lv objectForKey: @"top"]];
            left = [self L: [lv objectForKey: @"left"]];
        }
        else if( [self targetTop: &top left: &left forPlane: plane preset: preset] == NO) { NSLog( @"SekhVet Hanging Protocol MPR: view %d plane %d without target in preset %d", i, (int) plane, (int) preset); continue; }

        // Acht Moeglichkeiten (4 Kameradrehungen x Spiegelung) decken jede Kombination von oben/links ab.
        // Drehung 0 und xFlipped zuerst: das ist Horos' Grundzustand, bei Gleichstand bleibt es dabei.
        float before[9];
        [v.pix orientation: before];
        Camera *base = [[[Camera alloc] initWithCamera: cam] autorelease];
        float U[3] = { base.viewUp.x, base.viewUp.y, base.viewUp.z };
        BOOL xf0 = v.xFlipped, yf0 = v.yFlipped, found = NO;
        NSString *sl = nil, *st = nil;
        int turn = 0;
        v.rotation = 0;
        for( int k = 0; k < 4 && !found; k++)
        {
            if( k > 0)
            {
                float u[3] = { U[0], U[1], U[2] };
                sekhmetRotate( u, n, 90.f * k);
                Camera *t = [[[Camera alloc] initWithCamera: base] autorelease];
                t.viewUp = [Point3D pointWithX: u[0] y: u[1] z: u[2]];
                t.forceUpdate = YES;
                v.camera = t;
                [v restoreCamera];
                [v updateViewMPR: NO];   // nur diese Ansicht rendern, ohne Kopplung — wie Horos' Drehwerkzeug
            }
            for( int f = 0; f < 2 && !found; f++)
            {
                v.yFlipped = NO;
                v.xFlipped = (f == 0);
                [self lettersForView: v left: &sl top: &st];
                if( [sl hasPrefix: left] && [st hasPrefix: top]) { found = YES; turn = k; }
            }
        }
        if( found)
        {
            float delta = 0;
            if( turn > 0)
            {
                float after[9];
                [v.vrView getCosMatrix: after];
                delta = [MPRController angleBetweenVector: after andPlane: before];
                v.angleMPR -= delta;
            }
            done++;
            NSLog( @"SekhVet Hanging Protocol MPR: view %d plane %d -> top %@ left %@ (camera %d x 90 deg, crosshair %+.0f, flipped %d)",
                  i, (int) plane, st, sl, turn, -delta, v.xFlipped);
        }
        else
        {
            base.forceUpdate = YES;
            v.camera = base;
            [v restoreCamera];
            [v updateViewMPR: NO];
            v.xFlipped = xf0; v.yFlipped = yf0;
            NSLog( @"SekhVet Hanging Protocol MPR: view %d plane %d - no rotation/flip shows top %@ left %@", i, (int) plane, top, left);
        }
        [v setNeedsDisplay: YES];
    }
    // SekhVet Paket AN: den Versatz einer Slab-Dicke zuruecknehmen, damit man nach mehreren Wechseln
    // noch an derselben Stelle steht.
    if( keepCross)
    {
        float after[3] = { 0, 0, 0 };
        if( [self crossPointOfMPR: c into: after])
        {
            float delta[3] = { crossBefore[0] - after[0], crossBefore[1] - after[1], crossBefore[2] - after[2] };
            float len = sqrtf( delta[0]*delta[0] + delta[1]*delta[1] + delta[2]*delta[2]);
            if( len > 0.01 && len < 50)   // groessere Spruenge kommen nicht vom Versatz -> nicht anfassen
            {
                [self shiftMPR: c by: delta];
                NSLog( @"SekhVet HP MPR: crossing point moved back by (%.2f %.2f %.2f)", delta[0], delta[1], delta[2]);
            }
        }
    }
    NSLog( @"SekhVet Hanging Protocol MPR: %d planes set, %d oblique skipped (preset %@%@)", done, skipped, [[self presetNames] objectAtIndex: preset],
          layout ? @", eigene Anordnung" : @"");
    return [NSString stringWithFormat: @"HP: %@", [[self presetNames] objectAtIndex: preset]];
}

#pragma mark - SekhVet Paket AX: MPR-Anordnung je Preset ("Take from screen")

+ (NSInteger) presetForMPR:(MPRController*) c
{
    ViewerController *v2d = [(id) c viewer];
    return [self presetForStudyUID: [v2d studyInstanceUID] description: [self descriptionForViewer: v2d]];
}

+ (NSArray*) mprLayoutForPreset:(NSInteger) preset
{
    NSArray *l = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLayoutsKey] objectForKey: [NSString stringWithFormat: @"%d", (int) preset]];
    if( ![l isKindOfClass: [NSArray class]] || l.count != 3) return nil;
    int used = 0;   // nur eine echte Vertauschung der drei Achsen gilt, sonst Grundbelegung
    for( NSDictionary *v in l)
    {
        if( ![v isKindOfClass: [NSDictionary class]]) return nil;
        int ax = [[v objectForKey: @"axis"] intValue];
        if( ax < 0 || ax > 2 || (used & (1 << ax)) || [[v objectForKey: @"top"] length] == 0 || [[v objectForKey: @"left"] length] == 0) return nil;
        used |= 1 << ax;
    }
    return l;
}

+ (void) setMPRLayout:(NSArray*) layout forPreset:(NSInteger) preset
{
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLayoutsKey]];
    NSString *key = [NSString stringWithFormat: @"%d", (int) preset];
    if( layout) [all setObject: layout forKey: key];
    else [all removeObjectForKey: key];
    [[NSUserDefaults standardUserDefaults] setObject: all forKey: SekhmetMPRLayoutsKey];
}

+ (int) mprAxisForView:(int) i preset:(NSInteger) preset
{
    NSArray *l = preset == SekhmetPresetOff ? nil : [self mprLayoutForPreset: preset];
    if( l) return [[[l objectAtIndex: i] objectForKey: @"axis"] intValue];
    return sekhmetDefaultMPRAxis[ i];
}

// Erster angezeigter Buchstabe ("Cr" und "Cd" sind zwei Zeichen) als DICOM-Buchstabe
+ (NSString*) rawFirstLetter:(NSString*) shown
{
    if( shown.length == 0) return @"";
    NSString *first = ([shown hasPrefix: @"Cr"] || [shown hasPrefix: @"Cd"]) ? [shown substringToIndex: 2] : [shown substringToIndex: 1];
    for( NSString *raw in [NSArray arrayWithObjects: @"A", @"P", @"S", @"I", @"L", @"R", nil])
        if( [first isEqualToString: [self L: raw]]) return raw;
    return @"";
}

+ (NSArray*) layoutFromMPR:(MPRController*) c error:(NSString**) error
{
    if( c == nil || [c windowWillClose]) { if( error) *error = NSLocalizedString( @"No MPR window is open.", nil); return nil; }
    NSMutableArray *views = [NSMutableArray array];
    int used = 0;
    for( int i = 0; i < 3; i++)
    {
        MPRDCMView *v = [c sekhmetView: i];
        Camera *cam = v.camera;
        if( cam == nil || cam.position == nil || cam.focalPoint == nil) { if( error) *error = NSLocalizedString( @"The MPR window is not ready yet.", nil); return nil; }
        float n[3] = { cam.position.x - cam.focalPoint.x, cam.position.y - cam.focalPoint.y, cam.position.z - cam.focalPoint.z };
        float len = sqrtf( n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
        if( !(len > 0)) { if( error) *error = NSLocalizedString( @"The MPR window is not ready yet.", nil); return nil; }
        int ax = sekhmetMainAxis( n, 0);
        float cosine = fabsf( n[ax]) / len;
        if( cosine < 0.97f)   // ~14 Grad; schraeger laesst sich keine Anordnung festhalten
        {
            if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"View %d is tilted by %.0f°. Rotate the crosshair in steps of 90° only, or switch the preset once to straighten the planes, then try again.", nil),
                                 i + 1, acos( cosine) * 180. / M_PI];
            return nil;
        }
        if( used & (1 << ax)) { if( error) *error = NSLocalizedString( @"Two views show the same plane.", nil); return nil; }
        used |= 1 << ax;
        NSString *shownLeft = nil, *shownTop = nil;
        [self lettersForView: v left: &shownLeft top: &shownTop];
        NSString *top = [self rawFirstLetter: shownTop], *left = [self rawFirstLetter: shownLeft];
        if( top.length == 0 || left.length == 0) { if( error) *error = NSLocalizedString( @"The orientation letters of a view cannot be read.", nil); return nil; }
        [views addObject: [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt: ax], @"axis", top, @"top", left, @"left", nil]];
    }
    return views;
}

+ (MPRController*) frontMPR
{
    for( NSWindow *w in [NSApp orderedWindows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] && [(MPRController*) wc windowWillClose] == NO) return wc;
    }
    return nil;
}

+ (NSString*) describeMPRLayout:(NSArray*) layout
{
    if( layout == nil) return NSLocalizedString( @"standard (1 sagittal, 2 transverse, 3 dorsal)", nil);
    NSArray *planes = [NSArray arrayWithObjects: NSLocalizedString( @"sagittal", nil), NSLocalizedString( @"dorsal", nil), NSLocalizedString( @"transverse", nil), nil];
    NSMutableArray *parts = [NSMutableArray array];
    for( NSUInteger i = 0; i < layout.count; i++)
    {
        NSDictionary *v = [layout objectAtIndex: i];
        [parts addObject: [NSString stringWithFormat: NSLocalizedString( @"%d %@ (top %@, left %@)", nil), (int) i + 1,
                           [planes objectAtIndex: [[v objectForKey: @"axis"] intValue]], [self L: [v objectForKey: @"top"]], [self L: [v objectForKey: @"left"]]]];
    }
    return [parts componentsJoinedByString: @", "];
}

#pragma mark - Headless-Tests (Umgebungsvariablen, AppController ruft 45 s nach dem Start)

#if SEKHVET_TESTHAKEN
+ (void) debugResliceFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_RESLICE_TEST");
    ViewerController *v = [ViewerController frontMostDisplayed2DViewer];
    if( env == NULL || v == nil) { NSLog( @"SekhVet Reslice-Test: kein Viewer"); return; }
    NSLog( @"SekhVet Reslice-Test vorher: %@ status=%@", [self debugLettersForView: [v imageView]], [self statusForViewer: v]);
    BOOL ok = [v setOrientation: atoi( env)];
    NSString *st = [self applyToViewer: v];
    [v setWindowTitle: v];
    NSLog( @"SekhVet Reslice-Test nachher (setOrientation %d = %d): %@ status=%@ preset=%d", atoi( env), ok, [self debugLettersForView: [v imageView]], st,
          (int) [self presetForStudyUID: [v studyInstanceUID] description: [self descriptionForViewer: v]]);
}

+ (void) debugMPRFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_MPR_TEST");
    ViewerController *v = [ViewerController frontMostDisplayed2DViewer];
    if( env == NULL || v == nil) { NSLog( @"SekhVet MPR-Test: kein Viewer"); return; }
    if( strcmp( env, "all") == 0) { for( ViewerController *c in [ViewerController getDisplayed2DViewers]) [c mprViewer: nil]; } // SekhVet Paket AF: Double MPR headless
    else [v mprViewer: nil];
    for( NSNumber *d in [NSArray arrayWithObjects: @1, @3, @6, @15, nil]) // Zeitverlauf nach dem Oeffnen (HP kommt bei 0,5 s)
        [self performSelector: @selector(debugMPRLog) withObject: nil afterDelay: [d floatValue] inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
    if( sekhvetTesthaken( "SEKHVET_MPR_TILT_TEST")) [self performSelector: @selector(debugMPRTilt) withObject: nil afterDelay: 12 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]]; // SekhVet Paket AN
    if( sekhvetTesthaken( "SEKHVET_MPR_TAKE_TEST"))   // SekhVet Paket AX
    {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey: SekhmetMPRLayoutsKey];
        [self performSelector: @selector(debugMPRTake) withObject: nil afterDelay: 16 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
    }
    if( sekhvetTesthaken( "SEKHVET_HP_SWITCH_TEST")) [self performSelector: @selector(debugHPSwitch) withObject: nil afterDelay: 20 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
    if( sekhvetTesthaken( "SEKHVET_DOUBLE_MPR_ZOOM_TEST")) [self performSelector: @selector(debugDoubleMPRZoom) withObject: nil afterDelay: 25 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]]; // SekhVet Paket AT
}
#endif // SEKHVET_TESTHAKEN

// SekhVet Paket AT: Doppelklick-Zoom bei zwei MPR-Fenstern (Double MPR).
// SEKHVET_DOUBLE_MPR_ZOOM_TEST="<Ansicht 1..3>" - klickt doppelt in die genannte Ansicht des
// ERSTEN MPR-Fensters und protokolliert vorher/nachher je Fenster: Zoomzustand, die drei
// Ansichtshoehen (unabhaengiger Beleg, dass der Zoom wirklich griff) und das Fadenkreuz.
// Erwartet: nur das geklickte Fenster zoomt, das zweite behaelt seine Ansichten und sein Fadenkreuz.
// Braucht zwei Fenster, also zusammen mit SEKHVET_MPR_TEST=all.
static MPRDCMView *sekhmetZoomTestView = nil;

#if SEKHVET_TESTHAKEN
+ (void) debugDoubleMPRZoomLog:(NSString*) phase
{
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [(MPRController*) wc windowWillClose]) continue;
        MPRController *c = (MPRController*) wc;
        MPRDCMView *v1 = [c sekhmetView: 0], *v2 = [c sekhmetView: 1], *v3 = [c sekhmetView: 2];
        BOOL z = c.sekhmetFrameZoomed;
        NSLog( @"SekhVet Double-MPR-Zoom %@: [%@] zoomed=%d Hoehen %.0f/%.0f/%.0f Fadenkreuz sichtbar %d/%d/%d",
              phase, [w title], z,
              v1.frame.size.height, v2.frame.size.height, v3.frame.size.height,
              (v1.displayCrossLines && !z), (v2.displayCrossLines && !z), (v3.displayCrossLines && !z));
        for( int i = 0; i < 3; i++)
        {
            MPRDCMView *v = [c sekhmetView: i];
            NSRect f = [v frame], g = [[v vrView] frame];
            NSLog( @"SekhVet Double-MPR-Zoom %@:   Ansicht %d Rahmen %.0fx%.0f | vrView %.0fx%.0f%@ | WL/WW %.0f/%.0f | LOD %.2f",
                  phase, i + 1, f.size.width, f.size.height, g.size.width, g.size.height,
                  (g.size.width < 1 || g.size.height < 1) ? @"  <-- ENTARTET (0 Pixel)" : @"",
                  [v curWL], [v curWW], v.LOD);
        }
    }
}

+ (void) debugDoubleMPRClick
{
    MPRDCMView *v = sekhmetZoomTestView;
    if( v == nil) return;
    NSWindow *w = [v window];
    [w makeFirstResponder: v];
    NSPoint p = [v convertPoint: NSMakePoint( NSMidX( [v bounds]), NSMidY( [v bounds])) toView: nil];
    NSEvent *e = [NSEvent mouseEventWithType: NSLeftMouseDown
                                    location: p
                               modifierFlags: 0
                                   timestamp: [[NSProcessInfo processInfo] systemUptime]
                                windowNumber: [w windowNumber]
                                     context: nil
                                 eventNumber: 0
                                  clickCount: 2
                                    pressure: 1];
    [v mouseDown: e];
}

+ (void) debugDoubleMPRZoom
{
    const char *env = sekhvetTesthaken( "SEKHVET_DOUBLE_MPR_ZOOM_TEST");
    if( env == NULL) return;
    int which = atoi( env);
    if( which < 1 || which > 3) which = 1;

    NSMutableArray *controllers = [NSMutableArray array];
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] && [(MPRController*) wc windowWillClose] == NO)
            [controllers addObject: wc];
    }
    if( controllers.count < 2)
    {
        NSLog( @"SekhVet Double-MPR-Zoom: nur %lu MPR-Fenster - der Test braucht zwei (SEKHVET_MPR_TEST=all)", (unsigned long) controllers.count);
        return;
    }
    sekhmetZoomTestView = [[controllers objectAtIndex: 0] sekhmetView: which-1];
    NSLog( @"SekhVet Double-MPR-Zoom: %lu Fenster, Doppelklick in Ansicht %d von [%@]",
          (unsigned long) controllers.count, which, [[sekhmetZoomTestView window] title]);

    [self debugDoubleMPRZoomLog: @"vorher"];
    [self debugDoubleMPRClick];
    [self debugDoubleMPRZoomLog: @"SOFORT nach dem 1. Doppelklick"];
    [self performSelector: @selector(debugDoubleMPRZoomSpaet) withObject: nil afterDelay: 1.5 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
    [self performSelector: @selector(debugDoubleMPRZoomStep2) withObject: nil afterDelay: 2 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

+ (void) debugDoubleMPRZoomSpaet { [self debugDoubleMPRZoomLog: @"1,5 s spaeter"]; }

+ (void) debugDoubleMPRZoomStep2
{
    [self debugDoubleMPRZoomLog: @"nach dem 1. Doppelklick (gezoomt)"];
    [self debugDoubleMPRClick];
    [self performSelector: @selector(debugDoubleMPRZoomStep3) withObject: nil afterDelay: 2 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

+ (void) debugDoubleMPRZoomStep3
{
    [self debugDoubleMPRZoomLog: @"nach dem 2. Doppelklick (wieder geteilt)"];
}

// SekhVet Paket AN: einen gemeldeten Fall nachstellen — Ebenen schraeg stellen und die Schicht verschieben ("von der
// Wirbelsaeule zum Knie gescrollt und neu ausgerichtet"), damit der folgende Protokollwechsel etwas zu richten hat.
// SEKHVET_MPR_TILT_TEST="<Grad>,<Verschiebung in mm>" (Vorgabe 25,60)
+ (void) debugMPRTilt
{
    const char *env = sekhvetTesthaken( "SEKHVET_MPR_TILT_TEST");
    if( env == NULL) return;
    NSArray *parts = [[NSString stringWithUTF8String: env] componentsSeparatedByString: @","];
    float deg = parts.count > 0 ? [[parts objectAtIndex: 0] floatValue] : 25;
    float shift = parts.count > 1 ? [[parts objectAtIndex: 1] floatValue] : 60;
    // SekhVet Paket AX: dritter Teil "v0".."v2" = Fadenkreuz in dieser Ansicht drehen, also die ANDEREN beiden Ebenen
    // um deren Normale (gemeldet 16.09.: Head/Spine um 90 Grad gedreht, danach griff kein Protokollwechsel mehr)
    int pivot = (parts.count > 2 && [[parts objectAtIndex: 2] hasPrefix: @"v"]) ? [[[parts objectAtIndex: 2] substringFromIndex: 1] intValue] : -1;
    float axis[3] = { 0.30, 0.40, 0.87 };
    float len = sqrtf( axis[0]*axis[0] + axis[1]*axis[1] + axis[2]*axis[2]);
    for( int k = 0; k < 3; k++) axis[k] /= len;

    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [(MPRController*) wc windowWillClose]) continue;
        if( pivot >= 0 && pivot < 3)
        {
            // Wie der gemeldete Handgriff: am Fadenkreuz dieser Ansicht drehen (angleMPR), Horos' Kopplung legt die
            // anderen beiden Ebenen um. Nur im ersten Fenster — der Gleichlauf traegt es ins zweite; beide zu
            // drehen ergab 180 statt 90 Grad (Lauf A, 16.09.).
            MPRDCMView *pv = [(MPRController*) wc sekhmetView: pivot];
            NSResponder *before = [w firstResponder];
            [w makeFirstResponder: pv];
            int steps = MAX( 1, (int) ceil( fabs( deg) / 5.));   // Ziehen = viele kleine Schritte; ein 90-Grad-Sprung legt eine
            for( int st = 0; st < steps; st++)                    // Ebene auf ihren alten Aufwaertsvektor und ergibt NaN
            {
                [pv restoreCamera];   // beim Ziehen hat mouseDown den gemeinsamen vrView schon auf diese Ansicht gestellt
                pv.angleMPR += deg / steps;
                [pv updateViewMPR];
            }
            if( before) [w makeFirstResponder: before];
            NSLog( @"SekhVet MPR-Tilt: [%@] Fadenkreuz in Ansicht %d um %.0f Grad gedreht", [w title], pivot, deg);
            // Paket AX: der Gleichlauf traegt die Drehung ins zweite Fenster; dort muss sie auch beim Scrollen halten
            [self performSelector: @selector(debugCouplingProbe) withObject: nil afterDelay: 2 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
            break;
        }
        for( int i = 0; i < 3; i++)
        {
            if( i == pivot) continue;
            MPRDCMView *v = [(MPRController*) wc sekhmetView: i];
            Camera *cam = v.camera;
            if( cam == nil || cam.position == nil || cam.focalPoint == nil || cam.viewUp == nil) continue;
            float P[3] = { cam.position.x, cam.position.y, cam.position.z };
            float F[3] = { cam.focalPoint.x, cam.focalPoint.y, cam.focalPoint.z };
            float U[3] = { cam.viewUp.x, cam.viewUp.y, cam.viewUp.z };
            float n[3] = { P[0]-F[0], P[1]-F[1], P[2]-F[2] };
            sekhmetRotate( n, axis, deg);
            sekhmetRotate( U, axis, deg);
            Camera *t = [[[Camera alloc] initWithCamera: cam] autorelease];
            t.position = [Point3D pointWithX: P[0] y: P[1] z: P[2] + shift];
            t.focalPoint = [Point3D pointWithX: P[0] - n[0] y: P[1] - n[1] z: P[2] + shift - n[2]];
            t.viewUp = [Point3D pointWithX: U[0] y: U[1] z: U[2]];
            t.forceUpdate = YES;
            v.camera = t;
            [v restoreCamera];
        }
        for( int i = 0; i < 3; i++) { [[(MPRController*) wc sekhmetView: i] restoreCamera]; [[(MPRController*) wc sekhmetView: i] updateViewMPR]; }
        NSLog( @"SekhVet MPR-Tilt: [%@] um %.0f Grad verkippt, %.0f mm verschoben, Drehachse %@ (%.2f %.2f %.2f)", [w title], deg, shift,
              pivot >= 0 ? [NSString stringWithFormat: @"Normale Ansicht %d", pivot] : @"schraeg", axis[0], axis[1], axis[2]);
    }
    [self debugMPRLog];
}

+ (void) debugMPRTake // SekhVet Paket AX: genau der Knopf "Take from screen", ohne Dialog
{
    MPRController *c = nil;
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] && [(MPRController*) wc windowWillClose] == NO) { c = wc; break; }
    }
    NSString *err = nil;
    NSArray *layout = [self layoutFromMPR: c error: &err];
    NSInteger preset = c ? [self presetForMPR: c] : SekhmetPresetOff;
    if( layout && preset != SekhmetPresetOff) [self setMPRLayout: layout forPreset: preset];
    NSLog( @"SekhVet MPR-Take: [%@] Preset %d -> %@%@", [[c window] title], (int) preset,
          layout ? [self describeMPRLayout: layout] : @"KEINE", err ? [NSString stringWithFormat: @" (%@)", err] : @"");
}

+ (void) debugHPSwitch // SekhVet Paket AF: Folge von Preset-Wechseln (SEKHVET_HP_SWITCH_TEST=3,1,3), je 3 s spaeter Buchstaben je MPR-Fenster
{
    static NSArray *seq = nil; static NSUInteger idx = 0;
    if( seq == nil) seq = [[[NSString stringWithUTF8String: sekhvetTesthaken( "SEKHVET_HP_SWITCH_TEST")] componentsSeparatedByString: @","] retain];
    if( idx >= seq.count) return;
    ViewerController *v = [ViewerController frontMostDisplayed2DViewer];
    NSInteger preset = [[seq objectAtIndex: idx++] integerValue];
    NSLog( @"SekhVet HP-Wechsel-Test Schritt %d: Preset %d auf Studie %@", (int) idx, (int) preset, [v studyInstanceUID]);
    [self setPresetOverride: preset forStudyUID: [v studyInstanceUID]];
    [self applyToAllViewersOfStudyUID: [v studyInstanceUID]];
    [self performSelector: @selector(debugCouplingProbe) withObject: nil afterDelay: 3 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
    if( idx < seq.count) [self performSelector: @selector(debugHPSwitch) withObject: nil afterDelay: 6 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

+ (void) debugPointTest // SekhVet Build 67: SEKHVET_POINT_TEST="tra:256,170;256,400"
{
    static NSArray *pixels = nil; static ViewerController *src = nil; static int step = 0;
    if( pixels == nil)
    {
        NSArray *parts = [[NSString stringWithUTF8String: sekhvetTesthaken( "SEKHVET_POINT_TEST")] componentsSeparatedByString: @":"];
        NSString *key = [parts objectAtIndex: 0];
        pixels = [[[parts lastObject] componentsSeparatedByString: @";"] retain];
        for( ViewerController *v in [ViewerController getDisplayed2DViewers])
            if( [[[[v imageView] seriesObj] valueForKey: @"name"] rangeOfString: key options: NSCaseInsensitiveSearch].location != NSNotFound) src = v;
        if( src == nil) { NSLog( @"SekhVet Point-Test: kein Viewer mit '%@'", key); return; }
        NSLog( @"SekhVet Point-Test: Quelle '%@', %d Viewer, %d Punkte", [[[src imageView] seriesObj] valueForKey: @"name"], (int) [[ViewerController getDisplayed2DViewers] count], (int) pixels.count);
        [[src imageView] setIndex: (short) ([[[src imageView] dcmPixList] count] / 2)]; [src adjustSlider]; // mittlere Schicht wie im Alltag
        [NSApp activateIgnoringOtherApps: YES]; [[src window] makeKeyAndOrderFront: nil]; // Quelle vorn wie beim Klick
    }
    if( step % 2 == 0)
    {
        if( step / 2 >= (int) pixels.count) { NSLog( @"SekhVet Point-Test fertig"); return; }
        NSArray *xy = [[pixels objectAtIndex: step / 2] componentsSeparatedByString: @","];
        [[src imageView] sekhmetSync3DPointAtPixX: [[xy objectAtIndex: 0] floatValue] pixY: [[xy lastObject] floatValue]];
    }
    else
        for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [[v imageView] sekhmetDebugLogPoint];
    step++;
    [self performSelector: @selector(debugPointTest) withObject: nil afterDelay: 1.5 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

// SekhVet Paket AM: Lebensdauer der Punkt-Marker. SEKHVET_POINT_LIFETIME_TEST="tra:256,256"
// Folge: Punkt setzen -> Lage loggen -> Mausrad -> loggen -> Punkt -> Pfeiltaste -> loggen -> Punkt -> Werkzeugwechsel -> loggen.
// Erwartet: nach jedem der drei Schritte meldet JEDER Viewer "kein Punkt".
+ (void) debugPointLifetimeTest
{
    static NSArray *xy = nil; static ViewerController *src = nil; static int step = 0;
    if( xy == nil)
    {
        NSArray *parts = [[NSString stringWithUTF8String: sekhvetTesthaken( "SEKHVET_POINT_LIFETIME_TEST")] componentsSeparatedByString: @":"];
        xy = [[[parts lastObject] componentsSeparatedByString: @","] retain];
        for( ViewerController *v in [ViewerController getDisplayed2DViewers])
            if( [[[[v imageView] seriesObj] valueForKey: @"name"] rangeOfString: [parts objectAtIndex: 0] options: NSCaseInsensitiveSearch].location != NSNotFound) src = v;
        if( src == nil) { NSLog( @"SekhVet Point-Lebensdauer: kein Viewer mit '%@'", [parts objectAtIndex: 0]); return; }
        [[src imageView] setIndex: (short) ([[[src imageView] dcmPixList] count] / 2)]; [src adjustSlider];
        [NSApp activateIgnoringOtherApps: YES]; [[src window] makeKeyAndOrderFront: nil];
        [[src imageView] setCurrentTool: t3Dpoint];   // wie der Toolbar-Knopf "Point"
        NSLog( @"SekhVet Point-Lebensdauer: Quelle '%@', %d Viewer", [[[src imageView] seriesObj] valueForKey: @"name"], (int) [[ViewerController getDisplayed2DViewers] count]);
    }
    DCMView *sv = [src imageView];
    switch( step)
    {
        case 0: case 4: case 8:
            NSLog( @"SekhVet Point-Lebensdauer Schritt %d: Punkt setzen (img %d)", step, [sv curImage]);
            [sv sekhmetSync3DPointAtPixX: [[xy objectAtIndex: 0] floatValue] pixY: [[xy lastObject] floatValue]];
            break;

        case 1: case 3: case 5: case 7: case 9: case 11:
            NSLog( @"SekhVet Point-Lebensdauer Schritt %d: Zustand%@", step, (step == 3 || step == 7 || step == 11) ? @" — hier muss JEDER Viewer leer sein" : @"");
            for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [[v imageView] sekhmetDebugLogPoint];
            break;

        case 2:
        {
            CGEventRef ce = CGEventCreateScrollWheelEvent( NULL, kCGScrollEventUnitLine, 1, -3);
            NSEvent *ev = ce ? [NSEvent eventWithCGEvent: ce] : nil;
            int before = [sv curImage];
            if( ev) [sv scrollWheel: ev];
            NSLog( @"SekhVet Point-Lebensdauer Schritt 2: Mausrad (Ereignis %@, img %d -> %d)", ev ? @"ja" : @"NEIN", before, [sv curImage]);
            if( ce) CFRelease( ce);
            break;
        }

        case 6:
        {
            NSString *right = [NSString stringWithFormat: @"%C", (unichar) NSRightArrowFunctionKey]; // in Horos blaettert links/rechts, hoch/runter zoomt
            NSEvent *ev = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: [NSDate timeIntervalSinceReferenceDate]
                                       windowNumber: [[src window] windowNumber] context: nil characters: right charactersIgnoringModifiers: right isARepeat: NO keyCode: 124];
            int before = [sv curImage];
            if( ev) [sv keyDown: ev];
            NSLog( @"SekhVet Point-Lebensdauer Schritt 6: Pfeiltaste rechts (Ereignis %@, img %d -> %d)", ev ? @"ja" : @"NEIN", before, [sv curImage]);
            break;
        }

        case 10:
            NSLog( @"SekhVet Point-Lebensdauer Schritt 10: Werkzeug wechseln (Point -> WL)");
            [sv setCurrentTool: tWL];
            break;

        default:
            NSLog( @"SekhVet Point-Lebensdauer fertig");
            return;
    }
    step++;
    [self performSelector: @selector(debugPointLifetimeTest) withObject: nil afterDelay: 1.5 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

+ (void) debugCouplingProbe // SekhVet Paket AX: jede Ansicht einmal aktiv + Update, wie beim Scrollen — der Zustand muss das ueberstehen
{
    [self debugMPRLog];
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [(MPRController*) wc windowWillClose]) continue;
        NSResponder *before = [w firstResponder];
        for( int i = 0; i < 3; i++)
        {
            MPRDCMView *mv = [(MPRController*) wc sekhmetView: i];
            [w makeFirstResponder: mv];
            [mv restoreCamera];   // ohne das rendert die Ansicht mit der Kamera, die gerade im gemeinsamen vrView steckt
            [mv updateViewMPR];
        }
        if( before) [w makeFirstResponder: before];
    }
    NSLog( @"SekhVet MPR-Test Kopplungsprobe: jede Ansicht einmal aktiv aktualisiert");
    [self debugMPRLog];
}

+ (void) debugMPRLog
{
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        NSLog( @"SekhVet MPR-Test 2D [%@]: %@ status=%@", [[v window] title], [self debugLettersForView: [v imageView]], [self statusForViewer: v]);
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [(MPRController*) wc windowWillClose]) continue;
        for( int i = 0; i < 3; i++)
        {
            MPRDCMView *mv = [(MPRController*) wc sekhmetView: i];
            float o[9]; [mv.curDCM orientation: o];
            Camera *cm = mv.camera;
            float cn[3] = { 0, 0, 0 };
            if( cm.position && cm.focalPoint) { cn[0] = cm.position.x - cm.focalPoint.x; cn[1] = cm.position.y - cm.focalPoint.y; cn[2] = cm.position.z - cm.focalPoint.z; }
            float cl = sqrtf( cn[0]*cn[0] + cn[1]*cn[1] + cn[2]*cn[2]); if( cl > 0) for( int k = 0; k < 3; k++) cn[k] /= cl;
            NSLog( @"SekhVet MPR-Test [%@] Ansicht %d: %@ | normal %.2f %.2f %.2f | Kamera %.2f %.2f %.2f up %.2f %.2f %.2f rot %.0f xf %d yf %d%@", [w title], i, [self debugLettersForView: mv],
                  o[1]*o[5]-o[2]*o[4], o[2]*o[3]-o[0]*o[5], o[0]*o[4]-o[1]*o[3], cn[0], cn[1], cn[2],
                  cm.viewUp.x, cm.viewUp.y, cm.viewUp.z, mv.rotation, mv.xFlipped, mv.yFlipped,
                  (isnan( cn[0]) || isnan( cm.viewUp.x) || isnan( o[0])) ? @" <-- NaN" : @"");
        }
    }
}
#endif // SEKHVET_TESTHAKEN

#pragma mark - Anwenden

+ (NSString*) stationNameForPix:(DCMPix*) pix
{
    NSString *path = pix.srcFile;
    if( path == nil) return nil;

    NSString *cached = [sekhmetStationCache objectForKey: path];
    if( cached) return cached;

    NSString *station = @"";
    @try
    {
        DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
        NSString *st = [o attributeValueWithName: @"StationName"];
        if( st) station = st;
    }
    @catch (NSException *e) { }

    if( sekhmetStationCache.count > 500) [sekhmetStationCache removeAllObjects];
    [sekhmetStationCache setObject: station forKey: path];
    return station;
}

+ (NSString*) applyDXRulesToView:(DCMView*) view pix:(DCMPix*) pix modality:(NSString*) modality
{
    NSArray *rules = [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetDXRulesKey];
    if( rules.count == 0) return nil;

    NSString *station = [self stationNameForPix: pix];

    for( NSDictionary *rule in rules)
    {
        NSString *match = [rule objectForKey: @"match"];
        if( match.length == 0) continue;

        BOOL hit = NO;
        if( [match caseInsensitiveCompare: modality] == NSOrderedSame) hit = YES;
        else if( station.length && [station rangeOfString: match options: NSCaseInsensitiveSearch].location != NSNotFound) hit = YES;

        if( hit)
        {
            [self setView: view rotation: [[rule objectForKey: @"rotation"] floatValue]
                 xFlipped: [[rule objectForKey: @"xFlipped"] boolValue]
                 yFlipped: [[rule objectForKey: @"yFlipped"] boolValue]];
            [view setNeedsDisplay: YES];
            return [NSString stringWithFormat: NSLocalizedString( @"DX rule \"%@\"", nil), match];
        }
    }
    return nil;
}

+ (void) setStatus:(NSString*) status forViewer:(ViewerController*) v
{
    NSValue *key = [NSValue valueWithPointer: v];
    if( status) [sekhmetStatus setObject: status forKey: key];
    else [sekhmetStatus removeObjectForKey: key];
}

+ (NSString*) statusForViewer:(ViewerController*) v
{
    return [sekhmetStatus objectForKey: [NSValue valueWithPointer: v]];
}

+ (NSString*) titleForViewer:(ViewerController*) v baseTitle:(NSString*) title
{
    NSString *s = [self statusForViewer: v];
    if( s.length == 0) return title;
    return [NSString stringWithFormat: @"%@ — %@", title, s];
}

+ (NSString*) applyToViewer:(ViewerController*) v
{
    NSString *status = [self applyToViewerInternal: v];
    [self setStatus: status forViewer: v];
    return status;
}

+ (NSString*) applyToViewerInternal:(ViewerController*) v
{
    DCMView *view = [v imageView];
    NSArray *pixList = [v pixList];
    if( view == nil || pixList.count == 0) return nil;

    DCMPix *pix = view.curDCM;
    if( pix == nil) pix = [pixList objectAtIndex: 0];

    NSInteger preset = [self presetForStudyUID: [v studyInstanceUID] description: [self descriptionForViewer: v]];
    if( preset == SekhmetPresetOff) return nil;

    NSString *modality = [v modality];
    NSArray *projection = [NSArray arrayWithObjects: @"DX", @"CR", @"MG", @"XA", @"RF", @"OT", nil];
    if( modality && [projection containsObject: modality])
        return [self applyDXRulesToView: view pix: pix modality: modality];

    if( pix.imageType.length && [[pix.imageType uppercaseString] rangeOfString: @"LOCALIZER"].location != NSNotFound)   // ohne Laengenpruefung liefert nil eine Range {0,0} = Treffer (Reslice-Pix haben keinen imageType)
        return NSLocalizedString( @"HP: localizer, not rotated", nil);

    SekhmetPlane plane = [self planeForPix: pix];
    if( plane == SekhmetPlaneOblique)
        return NSLocalizedString( @"HP: oblique series, not rotated", nil);

    NSString *top = nil, *left = nil;
    if( [self targetTop: &top left: &left forPlane: plane preset: preset] == NO) return nil;

    float origRot = view.rotation;
    BOOL origX = view.xFlipped, origY = view.yFlipped;

    float rots[ 4] = { 0, 90, 180, 270 };
    BOOL found = NO;
    float foundRot = 0; BOOL foundX = NO;

    for( int xf = 0; xf < 2 && found == NO; xf++)
    {
        for( int i = 0; i < 4 && found == NO; i++)
        {
            [self setView: view rotation: rots[ i] xFlipped: (xf == 1) yFlipped: NO];
            if( [self view: view showsTop: top left: left])
            {
                found = YES; foundRot = rots[ i]; foundX = (xf == 1);
            }
        }
    }

    if( found == NO)
    {
        [self setView: view rotation: origRot xFlipped: origX yFlipped: origY];
        [view setNeedsDisplay: YES];
        NSLog( @"SekhVet Vet HP: no rotation reaches target top=%@ left=%@ (series %@)", top, left, [self descriptionForViewer: v]);
        return NSLocalizedString( @"HP: no matching rotation", nil);
    }

    // Selbstpruefung: Werte zurueckgelesen und Buchstaben erneut geprueft
    if( view.rotation != foundRot || view.xFlipped != foundX || view.yFlipped != NO || [self view: view showsTop: top left: left] == NO)
    {
        [self setView: view rotation: origRot xFlipped: origX yFlipped: origY];
        [view setNeedsDisplay: YES];
        NSLog( @"SekhVet Vet HP DISABLED: rotation has no effect (rot %f x %d y %d)", view.rotation, view.xFlipped, view.yFlipped);
        return NSLocalizedString( @"HP DISABLED: rotation did not take effect", nil);
    }

    [view setNeedsDisplay: YES];
    return [NSString stringWithFormat: @"HP: %@", [[self presetNames] objectAtIndex: preset]];
}

+ (void) applyToAllViewersOfStudyUID:(NSString*) uid
{
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        if( uid == nil || [[v studyInstanceUID] isEqualToString: uid])
        {
            [self applyToViewer: v];
            [v setWindowTitle: v];
        }
    }
    // SekhVet Paket AF: waehrend des Protokollwechsels kein Fenster-Gleichlauf, sonst ueberschreibt das erste MPR-Fenster
    // das zweite mit seinem alten Stand (Double MPR: nur ein Fenster richtig)
    [MPRController sekhmetSetSyncSuppressed: YES];
    NSMutableArray *done = [NSMutableArray array];
    for( NSWindow *w in [NSApp windows])   // 3D-MPR-Fenster derselben Studie
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] && [(MPRController*) wc windowWillClose] == NO)
        {
            if( uid == nil || [[[(id) wc viewer] studyInstanceUID] isEqualToString: uid])
            {
                [self applyToMPR: wc straighten: YES]; [done addObject: wc];   // SekhVet Paket AN: Protokollwechsel = definierter Ausgangszustand
                NSString *t = [w title]; NSRange r = [t rangeOfString: @": "]; // Titel "MPR: <2D-Titel>" mit dem neuen HP-Badge erneuern (Paket AG)
                [w setTitle: [NSString stringWithFormat: @"%@: %@", (r.location == NSNotFound ? @"MPR" : [t substringToIndex: r.location]), [[[(id) wc viewer] window] title]]];
            }
        }
    }
    for( MPRController *c in done) [c sekhmetSettleAfterHP];
    [MPRController sekhmetSetSyncSuppressed: NO];
    [[NSNotificationCenter defaultCenter] postNotificationName: SekhmetVetPresetDidChangeNotification object: uid];
}

@end
