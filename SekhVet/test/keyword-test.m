// Paket CS (review findings 2 and 12): bash SekhVet/test/keyword-test.sh
// Includes the two source files themselves; with SEKHVET_LOGIC_TEST only their pure logic above the #ifndef compiles.

#import "../../Horos/Sources/SekhmetOrientation.m"
#import "../../Horos/Sources/SekhmetOpening.m"

static int pass = 0, fail = 0;

static void check( NSString *n, BOOL c, NSString *d)
{
    if( c) { pass++; printf( "  ok    %s\n", n.UTF8String); }
    else { fail++; printf( "  FAIL  %s  %s\n", n.UTF8String, (d ? d : @"").UTF8String); }
}

static NSString* presetName( NSInteger p)
{
    switch( p)
    {
        case SekhmetPresetHeadSpine: return @"Head/Spine";
        case SekhmetPresetHindlimb:  return @"Hindlimbs";
        case SekhmetPresetForelimb:  return @"Forelimbs";
        case -1:                     return @"(no keyword)";
        default:                     return [NSString stringWithFormat: @"preset %d", (int) p];
    }
}

static void expectPreset( NSArray *keywords, NSString *description, NSInteger want)
{
    NSInteger got = sekhmetPresetForDescription( description, keywords, nil);
    check( [NSString stringWithFormat: @"\"%@\" -> %@", description, presetName( want)], got == want,
           [NSString stringWithFormat: @"got %@", presetName( got)]);
}

static void expectContrast( NSString *name, NSInteger want)
{
    static NSString * const names[] = { @"any", @"native", @"contrast" };
    NSInteger got = sekhmetContrastForName( name);
    check( [NSString stringWithFormat: @"\"%@\" -> %@", name, names[ want]], got == want, [NSString stringWithFormat: @"got %@", names[ got]]);
}

static NSDictionary* kw( NSString *k, NSInteger p)
{
    return [NSDictionary dictionaryWithObjectsAndKeys: k, @"keyword", [NSNumber numberWithInteger: p], @"preset", nil];
}

int main( void)
{
    @autoreleasepool
    {
        NSInteger H = SekhmetPresetHeadSpine, HL = SekhmetPresetHindlimb, FL = SekhmetPresetForelimb;
        NSArray *defaults = sekhmetDefaultKeywords();

        printf( "[Hanging protocol, default keywords: hind before generic (review finding 2)]\n");
        expectPreset( defaults, @"CT Hindlimb", HL);
        expectPreset( defaults, @"Hindlimbs bilateral", HL);
        expectPreset( defaults, @"Hind limb left", HL);
        expectPreset( defaults, @"MR Pelvic limb", HL);
        expectPreset( defaults, @"CT Hinterextremität links", HL);
        expectPreset( defaults, @"Hinterextremitaeten", HL);
        expectPreset( defaults, @"Hintergliedmasse rechts", HL);
        expectPreset( defaults, @"Hintergliedmaße", HL);
        expectPreset( defaults, @"Hinterbein", HL);
        expectPreset( defaults, @"Hinterpfote li", HL);

        printf( "[Femoral head / neck are not head / neck]\n");
        expectPreset( defaults, @"Femoral head ostectomy control", HL);
        expectPreset( defaults, @"Femoral neck", HL);
        expectPreset( defaults, @"Femurkopf", HL);
        expectPreset( defaults, @"Femur head", HL);
        expectPreset( defaults, @"Hüftkopf / Schenkelhals", HL);
        expectPreset( defaults, @"Hueftgelenk bds", HL);
        expectPreset( defaults, @"Hip dysplasia", HL);
        expectPreset( defaults, @"Hips", HL);

        printf( "[Forelimbs and the generic fallback stay]\n");
        expectPreset( defaults, @"Forelimb", FL);
        expectPreset( defaults, @"Thoracic limb", FL);
        expectPreset( defaults, @"Vorderextremität", FL);
        expectPreset( defaults, @"Vordergliedmasse", FL);
        expectPreset( defaults, @"Fore limb right", FL);
        expectPreset( defaults, @"Ellbogen bds", FL);
        expectPreset( defaults, @"Limb", FL);
        expectPreset( defaults, @"Extremitaet", FL);
        expectPreset( defaults, @"Radius/Ulna", FL);

        printf( "[Head / spine]\n");
        expectPreset( defaults, @"CT Kopf nativ", H);
        expectPreset( defaults, @"Head and Neck", H);
        expectPreset( defaults, @"HWS/BWS", H);
        expectPreset( defaults, @"Halswirbelsäule", H);
        expectPreset( defaults, @"MR Brain", H);
        expectPreset( defaults, @"Kopf-Hals", H);

        printf( "[Short keywords need a word boundary]\n");
        expectPreset( defaults, @"Hippocampus T2", -1);
        expectPreset( defaults, @"Chip reader", -1);
        expectPreset( defaults, @"Kniegelenk", HL);
        expectPreset( defaults, @"li.Knie", HL);
        expectPreset( defaults, @"Thorax", -1);
        expectPreset( defaults, @"", -1);

        printf( "[List as stored BEFORE this package (first hit used to win): longest match repairs it]\n");
        NSMutableArray *old = [NSMutableArray array];
        for( NSString *k in @[ @"Kopf", @"Schädel", @"Schaedel", @"Skull", @"Head", @"Wirbel", @"Spine", @"HWS", @"BWS", @"LWS", @"Hals", @"Neck", @"Gehirn", @"Brain"]) [old addObject: kw( k, H)];
        for( NSString *k in @[ @"Ellbogen", @"Elbow", @"Schulter", @"Shoulder", @"Karpus", @"Carpus", @"Vordergliedmasse", @"Vorderbein", @"Forelimb", @"Humerus", @"Radius", @"Ulna", @"Extremit", @"Limb", @"Zehe", @"Pfote"]) [old addObject: kw( k, FL)];
        for( NSString *k in @[ @"Knie", @"Stifle", @"Tarsus", @"Sprunggelenk", @"Hüfte", @"Huefte", @"Hip", @"Hintergliedmasse", @"Hinterbein", @"Hindlimb", @"Femur", @"Tibia", @"Becken", @"Pelvis"]) [old addObject: kw( k, HL)];
        expectPreset( old, @"CT Hindlimb", HL);
        expectPreset( old, @"Hindlimbs", HL);
        expectPreset( old, @"Hintergliedmasse", HL);
        expectPreset( old, @"Femurkopf", HL);
        expectPreset( old, @"Forelimb", FL);
        expectPreset( old, @"CT Kopf", H);
        printf( "   (old list without the added keywords: these still need the one-time migration)\n");
        expectPreset( old, @"Pelvic limb", FL);
        expectPreset( old, @"Hinterextremität", FL);

        printf( "[User list: order decides only between equally long keywords; deleted protocol is skipped]\n");
        NSArray *user = @[ kw( @"Spine", H), kw( @"Elbow", FL), kw( @"Tarsus", 7), kw( @"Tars", HL)];
        expectPreset( user, @"Spine Elbow", H);
        expectPreset( user, @"Elbow Spine", H);
        check( @"\"Tarsus\" with protocol 7 deleted -> Hindlimbs (next longest)",
               sekhmetPresetForDescription( @"Tarsus", user, ^BOOL( NSInteger p) { return p != 7; }) == HL, nil);
        check( @"damaged entries are ignored",
               sekhmetPresetForDescription( @"Spine", @[ @"text", @{ @"keyword": @5 }, @{ @"preset": @1 }, kw( @"Spine", H)], nil) == H, nil);

        printf( "[Contrast phase of a series name (review finding 12)]\n");
        expectContrast( @"Wirbelsäule nativ 0,80 Br40 S2", SekhmetContrastNative);
        expectContrast( @"Wirbelsäule KM 0,80 Br64", SekhmetContrastAgent);
        expectContrast( @"WT nativ Vol 0.5  FC26", SekhmetContrastNative);
        expectContrast( @"KF KM Vol 0.5  BONE", SekhmetContrastAgent);
        expectContrast( @"Head N", SekhmetContrastNative);
        expectContrast( @"Head C", SekhmetContrastAgent);
        expectContrast( @"Thorax Bone N", SekhmetContrastNative);
        expectContrast( @"Head Bone Plus N", SekhmetContrastNative);
        expectContrast( @"Body 1.0 CE FC08", SekhmetContrastAgent);
        expectContrast( @"HKCL SE T1 tra HawkAI", SekhmetContrastAny);
        expectContrast( @"HKCL SE T1 tra post KM HawkAI", SekhmetContrastAgent);
        expectContrast( @"Topogramm 0,70 Tr20 sag", SekhmetContrastAny);
        expectContrast( @"CSPINE stitch", SekhmetContrastAny);
        expectContrast( @"C1-Th3 N", SekhmetContrastNative);
        expectContrast( @"C Spine T2", SekhmetContrastAny);
        expectContrast( @"C-Bogen Thorax", SekhmetContrastAny);
        expectContrast( @"N. ischiadicus T2", SekhmetContrastAny);
        expectContrast( @"C", SekhmetContrastAny);
        expectContrast( @"T1 tra ohne KM", SekhmetContrastNative);
        expectContrast( @"Abdomen without contrast", SekhmetContrastNative);
        expectContrast( @"non-contrast CT", SekhmetContrastNative);
        expectContrast( @"T1 pre KM", SekhmetContrastNative);
        expectContrast( @"T1W_TSE +C", SekhmetContrastAgent);
        expectContrast( @"T1+C tra", SekhmetContrastAgent);
        expectContrast( @"T1 +Cor", SekhmetContrastAny);
        expectContrast( @"Abdomen post contrast", SekhmetContrastAgent);
        expectContrast( @"Thorax post", SekhmetContrastAgent);
        expectContrast( @"Knie post OP", SekhmetContrastAny);
        expectContrast( @"Thorax plain", SekhmetContrastNative);
        expectContrast( @"Abdomen pre", SekhmetContrastNative);
        expectContrast( @"SUB KM-nativ", SekhmetContrastAgent);
        expectContrast( @"", SekhmetContrastAny);

        printf( "\n%d passed, %d failed\n", pass, fail);
    }
    return fail ? 1 : 0;
}
