// SekhVet Paket ED: unit test of the automatic-retrieve rule (SekhmetAutoRegel.h).
// Replays 20.10.2026: a US study appears while still arriving, the first retrieve breaks off, the node then has all images.
#import <Foundation/Foundation.h>
#import "SekhmetAutoRegel.h"

static int ok = 0, bad = 0;
static const char *name( SekhmetAutoAction a)
{
    const char *n[] = { "Nothing", "Retrieve", "Arriving", "Waiting", "GaveUp", "Pending" };
    return n[ a];
}
static void check( const char *what, SekhmetAutoAction got, SekhmetAutoAction want)
{
    if( got == want) { ok++; printf( "ok   %-62s %s\n", what, name( got)); }
    else { bad++; printf( "FAIL %-62s %s (expected %s)\n", what, name( got), name( want)); }
}

int main( void)
{
    @autoreleasepool
    {
        NSMutableDictionary *s = [NSMutableDictionary dictionary];
        NSTimeInterval t = 1000;
        // 09:02 the study appears with 9 of (later) 20 images
        check( "1 new study, 9 images, nothing here", sekhmetAutoDecide( s, 0, 9, NO, t), SekhmetAutoArriving);
        check( "2 one minute later 20 images (still arriving)", sekhmetAutoDecide( s, 0, 20, NO, t + 60), SekhmetAutoArriving);
        check( "3 another minute, 20 images: stable -> retrieve", sekhmetAutoDecide( s, 0, 20, NO, t + 120), SekhmetAutoRetrieve);
        check( "4 retrieve running", sekhmetAutoDecide( s, 0, 20, YES, t + 150), SekhmetAutoPending);
        sekhmetAutoEnded( s, YES, t + 170);   // -1005 after 27 MB
        check( "5 failed, 3 of 20 here (old code: never again)", sekhmetAutoDecide( s, 0.15f, 20, NO, t + 180), SekhmetAutoWaiting);
        check( "6 pause over -> second try", sekhmetAutoDecide( s, 0.15f, 20, NO, t + 170 + 181), SekhmetAutoRetrieve);
        sekhmetAutoEnded( s, NO, t + 400);
        check( "7 imported, complete", sekhmetAutoDecide( s, 1, 20, NO, t + 600), SekhmetAutoNothing);
        check( "8 complete stays nothing", sekhmetAutoDecide( s, 1, 20, NO, t + 4000), SekhmetAutoNothing);

        // a study that never gets complete here: three tries, then give up; more images on the node start afresh
        NSMutableDictionary *g = [NSMutableDictionary dictionary];
        sekhmetAutoDecide( g, 0, 10, NO, 0);
        check( "9 try 1", sekhmetAutoDecide( g, 0, 10, NO, 60), SekhmetAutoRetrieve);
        sekhmetAutoEnded( g, NO, 100);
        check( "10 before the pause is over", sekhmetAutoDecide( g, 0.5f, 10, NO, 100 + 179), SekhmetAutoWaiting);
        check( "11 try 2", sekhmetAutoDecide( g, 0.5f, 10, NO, 100 + 180), SekhmetAutoRetrieve);
        sekhmetAutoEnded( g, NO, 300);
        check( "12 second pause is longer", sekhmetAutoDecide( g, 0.5f, 10, NO, 300 + 300), SekhmetAutoWaiting);
        check( "13 try 3", sekhmetAutoDecide( g, 0.5f, 10, NO, 300 + 600), SekhmetAutoRetrieve);
        sekhmetAutoEnded( g, NO, 1000);
        check( "14 given up", sekhmetAutoDecide( g, 0.5f, 10, NO, 5000), SekhmetAutoGaveUp);
        check( "15 node has more images: arriving", sekhmetAutoDecide( g, 0.4f, 12, NO, 5100), SekhmetAutoArriving);
        check( "16 stable again: try afresh", sekhmetAutoDecide( g, 0.4f, 12, NO, 5150), SekhmetAutoRetrieve);
        check( "17 tries counted afresh", [[g objectForKey: @"tries"] intValue] == 1 ? SekhmetAutoNothing : SekhmetAutoGaveUp, SekhmetAutoNothing);

        // stopped by the user: not again, until the node has more images
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        sekhmetAutoDecide( p, 0, 5, NO, 0);
        sekhmetAutoStopped( p);
        check( "18 stopped before any automatic try", sekhmetAutoDecide( p, 0, 5, NO, 100), SekhmetAutoGaveUp);
        check( "19 stopped, much later", sekhmetAutoDecide( p, 0.2f, 5, NO, 9000), SekhmetAutoGaveUp);
        sekhmetAutoDecide( p, 0.2f, 7, NO, 9100);
        check( "20 more images after stop -> retrieve", sekhmetAutoDecide( p, 0.2f, 7, NO, 9200), SekhmetAutoRetrieve);

        // complete from the start: never retrieved; node without image count (remote 0) and nothing here: tried
        NSMutableDictionary *c = [NSMutableDictionary dictionary];
        sekhmetAutoDecide( c, 1, 30, NO, 0);
        check( "21 complete here", sekhmetAutoDecide( c, 1, 30, NO, 100), SekhmetAutoNothing);
        NSMutableDictionary *z = [NSMutableDictionary dictionary];
        sekhmetAutoDecide( z, 0, 0, NO, 0);
        check( "22 node gives no count, nothing here", sekhmetAutoDecide( z, 0, 0, NO, 60), SekhmetAutoRetrieve);

        // due time for the follow-up look
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        sekhmetAutoDecide( d, 0, 3, NO, 50);
        check( "23 due = seenAt + stable", sekhmetAutoDueAt( d, SekhmetAutoArriving) == 50 + SekhmetAutoStableSeconds ? SekhmetAutoNothing : SekhmetAutoGaveUp, SekhmetAutoNothing);

        printf( "\n%d ok, %d failed\n", ok, bad);
    }
    return bad ? 1 : 0;
}
