// SekhVet Paket ED: the rule of the automatic retrieve (DICOMweb auto-refresh with "retrieve new").
// Foundation only, so SekhVet/test/autoregel-test.sh can run it without the app.
//
// Seen 20.10.2026: a US study appeared on the node while the device was still sending, the automatic retrieve
// started at once, broke off after 27 MB (-1005) and was never tried again -- the study was marked as done with
// the image count of that moment. The rule now:
//   - retrieve only when the node's image count has stood still for SekhmetAutoStableSeconds (still arriving otherwise);
//   - retrieve whenever the study is not complete here and nothing for it is queued or running;
//   - after a try (failed or not complete afterwards) wait, then try again -- at most SekhmetAutoTries times for the
//     same image count; more images on the node start the count afresh.
//
// The state per study is a mutable dictionary kept by the caller:
//   seen / seenAt   image count of the node at the last refresh and since when it stands
//   count / tries   image count of the node at the last try and the number of tries for it
//   last            end (or start) of the last try; failed = YES if it failed; stopped = YES after "Stop"

#ifndef SEKHMET_AUTO_REGEL_H
#define SEKHMET_AUTO_REGEL_H

#import <Foundation/Foundation.h>

typedef NS_ENUM( int, SekhmetAutoAction)
{
    SekhmetAutoNothing = 0,   // complete here
    SekhmetAutoRetrieve,      // retrieve now
    SekhmetAutoArriving,      // image count still changing -- wait
    SekhmetAutoWaiting,       // tried, waiting before the next try
    SekhmetAutoGaveUp,        // tried SekhmetAutoTries times for this count, or stopped by the user
    SekhmetAutoPending        // queued or running
};

static const NSTimeInterval SekhmetAutoStableSeconds = 45;
static const int SekhmetAutoTries = 3;

// pause after try n (1, 2, ...) before the next one: long enough for Horos to import what came
static inline NSTimeInterval sekhmetAutoPause( int tries)
{
    return tries <= 1 ? 180 : 600;
}

static inline SekhmetAutoAction sekhmetAutoDecide( NSMutableDictionary *state, float fraction, int remote, BOOL pending, NSTimeInterval now)
{
    NSNumber *seen = [state objectForKey: @"seen"];
    if( seen == nil || [seen intValue] != remote)
    {
        [state setObject: [NSNumber numberWithInt: remote] forKey: @"seen"];
        [state setObject: [NSNumber numberWithDouble: now] forKey: @"seenAt"];
    }
    if( pending) return SekhmetAutoPending;
    if( fraction >= 1.0f) return SekhmetAutoNothing;
    if( now - [[state objectForKey: @"seenAt"] doubleValue] < SekhmetAutoStableSeconds) return SekhmetAutoArriving;

    NSNumber *count = [state objectForKey: @"count"];
    int tries = [[state objectForKey: @"tries"] intValue];
    if( count && remote > [count intValue])   // the node has more images than at the last try: start afresh
    {
        tries = 0;
        [state removeObjectForKey: @"stopped"];
    }
    else if( [[state objectForKey: @"stopped"] boolValue]) return SekhmetAutoGaveUp;
    else if( count == nil) tries = 0;   // first try
    else if( tries >= SekhmetAutoTries) return SekhmetAutoGaveUp;
    else if( now - [[state objectForKey: @"last"] doubleValue] < sekhmetAutoPause( tries)) return SekhmetAutoWaiting;

    [state setObject: [NSNumber numberWithInt: remote] forKey: @"count"];
    [state setObject: [NSNumber numberWithInt: tries + 1] forKey: @"tries"];
    [state setObject: [NSNumber numberWithDouble: now] forKey: @"last"];
    [state removeObjectForKey: @"failed"];
    return SekhmetAutoRetrieve;
}

// a retrieve job of the study ended; the pause before the next try counts from here
static inline void sekhmetAutoEnded( NSMutableDictionary *state, BOOL failed, NSTimeInterval now)
{
    if( state == nil || [state objectForKey: @"tries"] == nil) return;   // not started by the automatic retrieve
    [state setObject: [NSNumber numberWithDouble: now] forKey: @"last"];
    if( failed) [state setObject: @YES forKey: @"failed"];
}

// the user pressed Stop: no automatic try for this study until the node has more images than now
static inline void sekhmetAutoStopped( NSMutableDictionary *state)
{
    if( state == nil) return;
    [state setObject: @YES forKey: @"stopped"];
    if( [state objectForKey: @"count"] == nil && [state objectForKey: @"seen"]) [state setObject: [state objectForKey: @"seen"] forKey: @"count"];
}

// when the next try (or the next look at an arriving study) is due; 0 = nothing due
static inline NSTimeInterval sekhmetAutoDueAt( NSDictionary *state, SekhmetAutoAction action)
{
    if( action == SekhmetAutoArriving) return [[state objectForKey: @"seenAt"] doubleValue] + SekhmetAutoStableSeconds;
    if( action == SekhmetAutoWaiting) return [[state objectForKey: @"last"] doubleValue] + sekhmetAutoPause( [[state objectForKey: @"tries"] intValue]);
    return 0;
}

#endif
