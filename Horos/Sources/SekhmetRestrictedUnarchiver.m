/*=========================================================================
 Sekhmet — eingeschraenktes Auspacken alter NSArchiver-Archive. Siehe Header.
 ============================================================================*/

#import "SekhmetRestrictedUnarchiver.h"

// Tags des Typedstream-Formats (NSArchiver/NSUnarchiver)
enum
{
    kTSInteger2 = 0x81,
    kTSInteger4 = 0x82,
    kTSFloatingPoint = 0x83,
    kTSNew = 0x84,
    kTSNil = 0x85,
    kTSEndOfObject = 0x86,
    kTSInteger8 = 0x87,
};

static const long long kTSFirstReference = -110;   // Referenznummern beginnen nach den Tags
static const int kTSMaximumDepth = 64;              // tiefer als jedes Horos-Archiv, flach genug fuer den Stack
static const int kTSMaximumTypeNesting = 16;

enum { kEntryObject = 1, kEntryClass = 2, kEntryCString = 3 };

typedef struct
{
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger position;
    BOOL bigEndian;
    int depth;
    NSMutableArray *sharedStrings;   // NSData
    NSMutableData *entries;          // je Eintrag ein Byte kEntry*
    NSMutableArray *entryNames;      // je Eintrag der Klassenname (Klassen) oder NSNull
    NSMutableArray *classNames;
    NSString *failure;
} TSWalker;

static BOOL TSFail( TSWalker *w, NSString *reason)
{
    if( w->failure == nil)
        w->failure = [NSString stringWithFormat: @"not a typedstream this reader accepts: %@ at byte %lu", reason, (unsigned long) w->position];
    return NO;
}

static BOOL TSReadByte( TSWalker *w, uint8_t *out)
{
    if( w->position >= w->length) return TSFail( w, @"unexpected end");
    *out = w->bytes[ w->position++];
    return YES;
}

static BOOL TSPeekByte( TSWalker *w, uint8_t *out)
{
    if( w->position >= w->length) return TSFail( w, @"unexpected end");
    *out = w->bytes[ w->position];
    return YES;
}

static BOOL TSSkipRaw( TSWalker *w, long long count, const uint8_t **start)
{
    if( count < 0 || (unsigned long long) count > w->length - w->position) return TSFail( w, @"a length past the end");
    if( start) *start = w->bytes + w->position;
    w->position += (NSUInteger) count;
    return YES;
}

static BOOL TSReadFixed( TSWalker *w, int count, unsigned long long *out)
{
    const uint8_t *raw = NULL;
    if( TSSkipRaw( w, count, &raw) == NO) return NO;
    unsigned long long value = 0;
    for( int i = 0; i < count; i++)
    {
        uint8_t byte = w->bigEndian ? raw[ i] : raw[ count - 1 - i];
        value = (value << 8) | byte;
    }
    *out = value;
    return YES;
}

static BOOL TSReadIntegerWithHead( TSWalker *w, uint8_t head, long long *out)
{
    unsigned long long v = 0;
    switch( head)
    {
        case kTSInteger2: if( TSReadFixed( w, 2, &v) == NO) return NO; *out = (int16_t) v; return YES;
        case kTSInteger4: if( TSReadFixed( w, 4, &v) == NO) return NO; *out = (int32_t) v; return YES;
        case kTSInteger8: if( TSReadFixed( w, 8, &v) == NO) return NO; *out = (int64_t) v; return YES;
        default:
            if( head >= 0x80 && head <= 0x91) return TSFail( w, [NSString stringWithFormat: @"tag %d where an integer belongs", head]);
            *out = (int8_t) head;
            return YES;
    }
}

static BOOL TSReadInteger( TSWalker *w, long long *out)
{
    uint8_t head;
    if( TSReadByte( w, &head) == NO) return NO;
    return TSReadIntegerWithHead( w, head, out);
}

static BOOL TSReadReal( TSWalker *w, int size)
{
    uint8_t head;
    if( TSReadByte( w, &head) == NO) return NO;
    if( head == kTSFloatingPoint) return TSSkipRaw( w, size, NULL);
    long long ignored;
    return TSReadIntegerWithHead( w, head, &ignored);
}

static BOOL TSReadUnsharedBytes( TSWalker *w, NSData **out)
{
    long long length;
    if( TSReadInteger( w, &length) == NO) return NO;
    const uint8_t *start = NULL;
    if( TSSkipRaw( w, length, &start) == NO) return NO;
    if( out) *out = [NSData dataWithBytes: start length: (NSUInteger) length];
    return YES;
}

// Referenznummer als Index in eine Tabelle mit count Eintraegen
static BOOL TSReadReference( TSWalker *w, uint8_t head, NSUInteger count, NSUInteger *index)
{
    long long value;
    if( TSReadIntegerWithHead( w, head, &value) == NO) return NO;
    long long i = value - kTSFirstReference;
    if( i < 0 || (unsigned long long) i >= count) return TSFail( w, @"a reference to nothing");
    *index = (NSUInteger) i;
    return YES;
}

// *out = nil fuer den nil-Tag
static BOOL TSReadSharedString( TSWalker *w, NSData **out)
{
    uint8_t head;
    if( TSReadByte( w, &head) == NO) return NO;
    if( head == kTSNil) { *out = nil; return YES; }
    if( head == kTSNew)
    {
        NSData *string = nil;
        if( TSReadUnsharedBytes( w, &string) == NO) return NO;
        [w->sharedStrings addObject: string];
        *out = string;
        return YES;
    }
    NSUInteger index;
    if( TSReadReference( w, head, w->sharedStrings.count, &index) == NO) return NO;
    *out = [w->sharedStrings objectAtIndex: index];
    return YES;
}

static uint8_t TSEntryAt( TSWalker *w, NSUInteger index)
{
    return ((const uint8_t*) w->entries.bytes)[ index];
}

static void TSAddEntry( TSWalker *w, uint8_t kind, NSString *name)
{
    [w->entries appendBytes: &kind length: 1];
    [w->entryNames addObject: name ? (id) name : (id) [NSNull null]];
}

static BOOL TSEnter( TSWalker *w)
{
    w->depth++;
    if( w->depth > kTSMaximumDepth) return TSFail( w, [NSString stringWithFormat: @"nesting deeper than %d", kTSMaximumDepth]);
    return YES;
}

static BOOL TSWalkObject( TSWalker *w);

static BOOL TSWalkGroup( TSWalker *w);

static BOOL TSTypeIs( NSData *type, NSString *expected)
{
    return [type isEqualToData: [expected dataUsingEncoding: NSASCIIStringEncoding]];
}

// Sekhmet: NSArray/NSDictionary/NSData genau pruefen. *handled = YES, wenn der Inhalt hier bis zum Objektende gelesen
// wurde (das Ende-Tag ist dann noch nicht verbraucht).
static BOOL TSWalkCountedObject( TSWalker *w, NSString *className, BOOL *handled)
{
    *handled = NO;
    BOOL array = [className isEqualToString: @"NSArray"] || [className isEqualToString: @"NSMutableArray"];
    BOOL dictionary = [className isEqualToString: @"NSDictionary"] || [className isEqualToString: @"NSMutableDictionary"];
    BOOL data = [className isEqualToString: @"NSData"] || [className isEqualToString: @"NSMutableData"];
    if( array == NO && dictionary == NO && data == NO) return YES;

    NSData *type = nil;
    if( TSReadSharedString( w, &type) == NO) return NO;
    if( TSTypeIs( type, @"i") == NO) return TSFail( w, [NSString stringWithFormat: @"%@ without its count", className]);
    long long count;
    if( TSReadInteger( w, &count) == NO) return NO;
    if( count < 0 || (unsigned long long) count > w->length - w->position) return TSFail( w, [NSString stringWithFormat: @"%@ with a count past the end", className]);

    if( data)
    {
        if( count > 0)
        {
            if( TSReadSharedString( w, &type) == NO) return NO;
            if( TSTypeIs( type, [NSString stringWithFormat: @"[%lldc]", count]) == NO) return TSFail( w, @"NSData whose bytes do not match its length");
            if( TSSkipRaw( w, count, NULL) == NO) return NO;
        }
    }
    else
    {
        long long expected = dictionary ? 2 * count : count, objects = 0;
        while( YES)
        {
            uint8_t next;
            if( TSPeekByte( w, &next) == NO) return NO;
            if( next == kTSEndOfObject) break;
            if( TSReadSharedString( w, &type) == NO) return NO;
            if( TSTypeIs( type, @"@") == NO) return TSFail( w, [NSString stringWithFormat: @"%@ with a member that is not an object", className]);
            if( ++objects > expected) return TSFail( w, [NSString stringWithFormat: @"%@ with more members than its count", className]);
            if( TSWalkObject( w) == NO) return NO;
        }
        if( objects != expected) return TSFail( w, [NSString stringWithFormat: @"%@ with fewer members than its count", className]);
    }

    uint8_t end;
    if( TSPeekByte( w, &end) == NO) return NO;
    if( end != kTSEndOfObject) return TSFail( w, [NSString stringWithFormat: @"%@ with data after its members", className]);
    *handled = YES;
    return YES;
}

// *hasClass = NO fuer nil, das Ende einer Superklassen-Kette; *className = Name der (abgeleitetsten) Klasse
static BOOL TSWalkClass( TSWalker *w, BOOL *hasClass, NSString **className)
{
    uint8_t head;
    if( className) *className = nil;
    if( TSReadByte( w, &head) == NO) return NO;
    if( head == kTSNil) { *hasClass = NO; return YES; }
    if( head == kTSNew)
    {
        if( TSEnter( w) == NO) return NO;
        NSData *nameBytes = nil;
        if( TSReadSharedString( w, &nameBytes) == NO) { w->depth--; return NO; }
        NSString *name = nameBytes.length ? [[[NSString alloc] initWithData: nameBytes encoding: NSUTF8StringEncoding] autorelease] : nil;
        if( name.length == 0 || memchr( nameBytes.bytes, 0, nameBytes.length)) { w->depth--; return TSFail( w, @"a class without a readable name"); }
        [w->classNames addObject: name];
        long long version;
        if( TSReadInteger( w, &version) == NO) { w->depth--; return NO; }
        TSAddEntry( w, kEntryClass, name);
        BOOL superclass;
        BOOL ok = TSWalkClass( w, &superclass, NULL);
        w->depth--;
        if( ok == NO) return NO;
        *hasClass = YES;
        if( className) *className = name;
        return YES;
    }
    NSUInteger index;
    if( TSReadReference( w, head, w->entries.length, &index) == NO) return NO;
    if( TSEntryAt( w, index) != kEntryClass) return TSFail( w, @"a class reference to something else");
    *hasClass = YES;
    if( className) *className = [w->entryNames objectAtIndex: index];
    return YES;
}

static BOOL TSWalkObject( TSWalker *w)
{
    uint8_t head;
    if( TSReadByte( w, &head) == NO) return NO;
    if( head == kTSNil) return YES;
    if( head == kTSNew)
    {
        if( TSEnter( w) == NO) return NO;
        TSAddEntry( w, kEntryObject, nil);
        BOOL hasClass = NO;
        NSString *className = nil;
        if( TSWalkClass( w, &hasClass, &className) == NO) { w->depth--; return NO; }
        if( hasClass == NO) { w->depth--; return TSFail( w, @"an object without a class"); }
        // Sekhmet: Felder, Woerterbuecher und Daten lesen zuerst eine Anzahl und legen dafuer Speicher an - eine
        // gekippte, riesige Anzahl liess NSArray -initWithCoder: mit einem nicht fangbaren Trap abstuerzen. Die
        // Anzahl muss darum genau zum Inhalt passen.
        BOOL checked = NO;
        if( TSWalkCountedObject( w, className, &checked) == NO) { w->depth--; return NO; }
        while( checked == NO)
        {
            uint8_t next;
            if( TSPeekByte( w, &next) == NO) { w->depth--; return NO; }
            if( next == kTSEndOfObject) break;
            if( TSWalkGroup( w) == NO) { w->depth--; return NO; }
        }
        w->position++;
        w->depth--;
        return YES;
    }
    NSUInteger index;
    if( TSReadReference( w, head, w->entries.length, &index) == NO) return NO;
    if( TSEntryAt( w, index) != kEntryObject) return TSFail( w, @"an object reference to something else");
    return YES;
}

static BOOL TSWalkCString( TSWalker *w)
{
    uint8_t head;
    if( TSReadByte( w, &head) == NO) return NO;
    if( head == kTSNil) return YES;
    if( head == kTSNew)
    {
        TSAddEntry( w, kEntryCString, nil);
        NSData *string = nil;
        if( TSReadSharedString( w, &string) == NO) return NO;
        if( string == nil) return TSFail( w, @"a C string without characters");
        return YES;
    }
    NSUInteger index;
    if( TSReadReference( w, head, w->entries.length, &index) == NO) return NO;
    if( TSEntryAt( w, index) != kEntryCString) return TSFail( w, @"a C string reference to something else");
    return YES;
}

// Geht einen Wert des Typs ab type[*ti] durch und setzt *ti hinter den Typ
static BOOL TSWalkValue( TSWalker *w, const uint8_t *type, NSUInteger typeLength, NSUInteger *ti, int nesting)
{
    if( nesting >= kTSMaximumTypeNesting) return TSFail( w, @"a type nested too deep");
    if( *ti >= typeLength) return TSFail( w, @"a truncated type");
    uint8_t code = type[ (*ti)++];
    long long ignored;
    uint8_t byte;
    BOOL hasClass;
    NSData *string;

    switch( code)
    {
        case 'c': case 'C':
            return TSReadByte( w, &byte);
        case 's': case 'S': case 'i': case 'I': case 'l': case 'L': case 'q': case 'Q':
            return TSReadInteger( w, &ignored);
        case 'f':
            return TSReadReal( w, 4);
        case 'd':
            return TSReadReal( w, 8);
        case '@':
            return TSWalkObject( w);
        case '#':
            return TSWalkClass( w, &hasClass, NULL);
        case ':':
            return TSReadSharedString( w, &string);
        case '*':
            return TSWalkCString( w);
        case '+':
            return TSReadUnsharedBytes( w, NULL);
        case '[':
        {
            long long count = 0;
            int digits = 0;
            while( *ti < typeLength && type[ *ti] >= '0' && type[ *ti] <= '9')
            {
                count = count * 10 + (type[ *ti] - '0');
                (*ti)++;
                if( ++digits > 9) return TSFail( w, @"an array too long");
            }
            if( digits == 0) return TSFail( w, @"an array without a count");
            if( *ti >= typeLength) return TSFail( w, @"a truncated type");

            NSUInteger elementStart = *ti;
            NSUInteger elementEnd;
            if( type[ elementStart] == 'c' || type[ elementStart] == 'C')
            {
                // [Nc]: N rohe Bytes
                elementEnd = elementStart + 1;
                if( TSSkipRaw( w, count, NULL) == NO) return NO;
            }
            else
            {
                if( count == 0) return TSFail( w, @"an empty array type");
                // jedes Element braucht mindestens ein Byte: eine Anzahl hinter dem Ende ist kein Archiv
                if( (unsigned long long) count > w->length - w->position) return TSFail( w, @"an array past the end");
                if( TSEnter( w) == NO) return NO;
                elementEnd = elementStart;
                for( long long i = 0; i < count; i++)
                {
                    NSUInteger j = elementStart;
                    if( TSWalkValue( w, type, typeLength, &j, nesting + 1) == NO) { w->depth--; return NO; }
                    elementEnd = j;
                }
                w->depth--;
            }
            *ti = elementEnd;
            if( *ti >= typeLength || type[ *ti] != ']') return TSFail( w, @"an unterminated array type");
            (*ti)++;
            return YES;
        }
        case '{':
        {
            // Name bis '=', dann die Felder bis '}'
            while( *ti < typeLength && type[ *ti] != '=')
            {
                uint8_t c = type[ *ti];
                if( c == '{' || c == '}' || c == '[' || c == ']' || c == '"') return TSFail( w, @"a malformed structure type");
                (*ti)++;
            }
            if( *ti >= typeLength) return TSFail( w, @"a structure type without fields");
            (*ti)++;
            if( TSEnter( w) == NO) return NO;
            int fields = 0;
            while( *ti < typeLength && type[ *ti] != '}')
            {
                if( TSWalkValue( w, type, typeLength, ti, nesting + 1) == NO) { w->depth--; return NO; }
                fields++;
            }
            w->depth--;
            if( *ti >= typeLength || fields == 0) return TSFail( w, @"a malformed structure type");
            (*ti)++;
            return YES;
        }
        default:
            return TSFail( w, [NSString stringWithFormat: @"the unsupported type '%c'", code]);
    }
}

static BOOL TSWalkGroup( TSWalker *w)
{
    NSData *typeString = nil;
    if( TSReadSharedString( w, &typeString) == NO) return NO;
    if( typeString.length == 0) return TSFail( w, @"a group without a type");
    const uint8_t *type = typeString.bytes;
    NSUInteger ti = 0;
    while( ti < typeString.length)
        if( TSWalkValue( w, type, typeString.length, &ti, 0) == NO) return NO;
    return YES;
}

// Kopf und Wurzelobjekt, wie +unarchiveObjectWithData: sie liest. Danach sind nur Null-Bytes erlaubt
// (Auffuellung eines DICOM-Werts).
static BOOL TSWalkRootObject( TSWalker *w)
{
    uint8_t version;
    if( TSReadByte( w, &version) == NO) return NO;
    if( version != 4) return TSFail( w, @"unknown stream version");
    NSData *signature = nil;
    if( TSReadUnsharedBytes( w, &signature) == NO) return NO;
    if( [signature isEqualToData: [@"streamtyped" dataUsingEncoding: NSASCIIStringEncoding]]) w->bigEndian = NO;
    else if( [signature isEqualToData: [@"typedstream" dataUsingEncoding: NSASCIIStringEncoding]]) w->bigEndian = YES;
    else return TSFail( w, @"unknown signature");
    long long systemVersion;
    if( TSReadInteger( w, &systemVersion) == NO) return NO;
    if( systemVersion != 1000) return TSFail( w, @"unknown system version");
    NSData *rootType = nil;
    if( TSReadSharedString( w, &rootType) == NO) return NO;
    if( rootType.length != 1 || ((const uint8_t*) rootType.bytes)[ 0] != '@') return TSFail( w, @"the root is not an object");
    if( TSWalkObject( w) == NO) return NO;
    for( NSUInteger i = w->position; i < w->length; i++)
        if( w->bytes[ i] != 0) return TSFail( w, @"data after the root object");
    return YES;
}

@implementation SekhmetRestrictedUnarchiver

+ (NSSet*) roiClassNames
{
    static NSSet *set = nil;
    if( set == nil)
        set = [[NSSet alloc] initWithObjects: @"ROI", @"MyPoint",
               @"NSObject", @"NSArray", @"NSMutableArray", @"NSDictionary", @"NSMutableDictionary",
               @"NSString", @"NSMutableString", @"NSNumber", @"NSValue", @"NSData", @"NSMutableData", @"NSColor", nil];
    return set;
}

+ (NSSet*) clutClassNames
{
    static NSSet *set = nil;
    if( set == nil)
        set = [[NSSet alloc] initWithObjects: @"NSObject", @"NSArray", @"NSMutableArray", @"NSDictionary", @"NSMutableDictionary",
               @"NSString", @"NSMutableString", @"NSNumber", @"NSValue", @"NSColor", nil];
    return set;
}

+ (NSSet*) propertyListClassNames
{
    static NSSet *set = nil;
    if( set == nil)
        set = [[NSSet alloc] initWithObjects: @"NSObject", @"NSString", @"NSMutableString", @"NSNumber", @"NSValue", @"NSData", @"NSMutableData",
               @"NSArray", @"NSMutableArray", @"NSDictionary", @"NSMutableDictionary", @"NSDate", @"NSCalendarDate", nil];
    return set;
}

+ (NSSet*) colorClassNames
{
    static NSSet *set = nil;
    if( set == nil)
        set = [[NSSet alloc] initWithObjects: @"NSObject", @"NSColor", @"NSString", @"NSMutableString", nil];
    return set;
}

+ (NSSet*) curvedPathClassNames
{
    static NSSet *set = nil;
    if( set == nil)
        set = [[NSSet alloc] initWithObjects: @"CPRCurvedPath", @"N3BezierPath", @"N3MutableBezierPath",
               @"NSArray", @"NSMutableArray", @"NSDictionary", @"NSMutableDictionary",
               @"NSString", @"NSMutableString", @"NSNumber", @"NSValue", @"NSData", @"NSMutableData", nil];
    return set;
}

+ (id) unarchiveKeyedObjectWithData:(NSData*) data allowedClassNames:(NSSet*) allowed
{
    if( [data isKindOfClass: [NSData class]] == NO || data.length == 0) return nil;

    id plist = nil;
    @try
    {
        plist = [NSPropertyListSerialization propertyListWithData: data options: NSPropertyListImmutable format: NULL error: NULL];
    }
    @catch( NSException *e) { plist = nil; }

    NSArray *objects = [plist isKindOfClass: [NSDictionary class]] ? [plist objectForKey: @"$objects"] : nil;
    if( [objects isKindOfClass: [NSArray class]] == NO)
    {
        NSLog( @"SekhVet: refused to unarchive %lu bytes: not a keyed archive", (unsigned long) data.length);
        return nil;
    }
    for( id o in objects)
    {
        if( [o isKindOfClass: [NSDictionary class]] == NO || [o objectForKey: @"$classname"] == nil) continue;
        id name = [o objectForKey: @"$classname"];
        if( [name isKindOfClass: [NSString class]] == NO || [allowed containsObject: name] == NO || [NSKeyedUnarchiver classForClassName: name] != nil)
        {
            NSLog( @"SekhVet: refused to unarchive %lu bytes: the keyed archive names the class %@, which this archive does not hold", (unsigned long) data.length, name);
            return nil;
        }
    }

    id root = nil;
    @try
    {
        NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingFromData: data error: NULL] autorelease];
        unarchiver.requiresSecureCoding = NO;   // die Klassen sind oben geprueft; CPRCurvedPath kann kein NSSecureCoding
        root = [unarchiver decodeObjectForKey: NSKeyedArchiveRootObjectKey];
        [unarchiver finishDecoding];
    }
    @catch( NSException *e)
    {
        NSLog( @"SekhVet: refused to unarchive %lu bytes: NSKeyedUnarchiver raised %@", (unsigned long) data.length, e.reason ? e.reason : e.name);
        root = nil;
    }
    return root;
}

+ (NSArray*) classNamesInData:(NSData*) data reason:(NSString**) reason
{
    if( reason) *reason = nil;
    if( data.length == 0) { if( reason) *reason = @"no data"; return nil; }

    TSWalker w;
    memset( &w, 0, sizeof( w));
    w.bytes = data.bytes;
    w.length = data.length;
    w.sharedStrings = [NSMutableArray array];
    w.entries = [NSMutableData data];
    w.entryNames = [NSMutableArray array];
    w.classNames = [NSMutableArray array];

    BOOL ok = NO;
    @try
    {
        ok = TSWalkRootObject( &w);
    }
    @catch( NSException *e)
    {
        ok = NO;
        TSFail( &w, e.reason ? e.reason : e.name);
    }
    if( ok == NO)
    {
        if( reason) *reason = w.failure ? w.failure : @"unreadable";
        return nil;
    }
    return w.classNames;
}

+ (id) unarchiveObjectWithData:(NSData*) data allowedClassNames:(NSSet*) allowed
{
    if( [data isKindOfClass: [NSData class]] == NO || data.length == 0) return nil;

    NSString *reason = nil;
    NSArray *names = [self classNamesInData: data reason: &reason];
    if( names == nil)
    {
        NSLog( @"SekhVet: refused to unarchive %lu bytes: %@", (unsigned long) data.length, reason);
        return nil;
    }
    for( NSString *name in names)
    {
        // auch keine Umleitung einer erlaubten Klasse auf eine andere (+decodeClassName:asClassName:)
        if( [allowed containsObject: name] == NO || [[NSUnarchiver classNameDecodedForArchiveClassName: name] isEqualToString: name] == NO)
        {
            NSLog( @"SekhVet: refused to unarchive %lu bytes: the archive names the class %@, which this archive does not hold", (unsigned long) data.length, name);
            return nil;
        }
    }

    id object = nil;
    @try
    {
        object = [NSUnarchiver unarchiveObjectWithData: data];
    }
    @catch( NSException *e)
    {
        NSLog( @"SekhVet: refused to unarchive %lu bytes: NSUnarchiver raised %@", (unsigned long) data.length, e.reason ? e.reason : e.name);
        object = nil;
    }
    return object;
}

+ (NSArray*) unarchiveROIsWithData:(NSData*) data
{
    id object = [self unarchiveObjectWithData: data allowedClassNames: [self roiClassNames]];
    return [object isKindOfClass: [NSArray class]] ? object : nil;
}

+ (NSArray*) unarchiveROIsWithFile:(NSString*) path
{
    if( path.length == 0) return nil;
    return [self unarchiveROIsWithData: [NSData dataWithContentsOfFile: path]];
}

+ (id) unarchiveCLUTWithData:(NSData*) data
{
    return [self unarchiveObjectWithData: data allowedClassNames: [self clutClassNames]];
}

+ (id) unarchiveCLUTWithFile:(NSString*) path
{
    if( path.length == 0) return nil;
    return [self unarchiveCLUTWithData: [NSData dataWithContentsOfFile: path]];
}

@end
