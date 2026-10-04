/*=========================================================================
 This file is part of the Horos Project (www.horosproject.org)
 
 Horos is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation,  version 3 of the License.
 
 The Horos Project was based originally upon the OsiriX Project which at the time of
 the code fork was licensed as a LGPL project.  However, not all of the the source-code
 was properly documented and file headers were not all updated with the appropriate
 license terms. The Horos Project, originally was licensed under the  GNU GPL license.
 However, contributors to the software since that time have agreed to modify the license
 to the GNU LGPL in order to be conform to the changes previously made to the
 OsiriX Project.
 
 Horos is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY EXPRESS OR IMPLIED, INCLUDING ANY WARRANTY OF
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE OR USE.  See the
 GNU Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public License
 along with Horos.  If not, see http://www.gnu.org/licenses/lgpl.html
 
 Prior versions of this file were published by the OsiriX team pursuant to
 the below notice and licensing protocol.
 ============================================================================
 Program:   OsiriX
  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - LGPL
  
  See http://www.osirix-viewer.com/copyright.html for details.
     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
 ============================================================================*/

#import "N2ManagedDatabase.h"
#import <AppKit/AppKit.h>
#import "NSMutableDictionary+N2.h"
#import "N2Debug.h"
#import "NSFileManager+N2.h"
#import "NSException+N2.h"
#import "DCMTKQueryNode.h"
//#import "DicomDatabase.h" // for debug purposes, REMOVE

static int gTotalN2ManagedObjectContext = 0;

static void N2ManagedDatabaseAppendErrorDetails(NSMutableArray *details, NSError *error, NSUInteger depth)
{
    if (![error isKindOfClass:[NSError class]] || depth > 4)
        return;

    NSString *description = error.localizedDescription.length ? error.localizedDescription : error.description;
    if (description.length)
        [details addObject:[NSString stringWithFormat:@"%@ %ld: %@", error.domain, (long)error.code, description]];

    if (error.localizedFailureReason.length)
        [details addObject:[NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Reason", nil), error.localizedFailureReason]];

    if (error.localizedRecoverySuggestion.length)
        [details addObject:[NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Suggestion", nil), error.localizedRecoverySuggestion]];

    NSString *filePath = [error.userInfo objectForKey:NSFilePathErrorKey];
    if (filePath.length)
        [details addObject:[NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"File", nil), filePath]];

    id underlyingError = [error.userInfo objectForKey:NSUnderlyingErrorKey];
    if ([underlyingError isKindOfClass:[NSError class]])
        N2ManagedDatabaseAppendErrorDetails(details, underlyingError, depth + 1);
    else if ([underlyingError isKindOfClass:[NSArray class]]) {
        for (NSError *nestedError in (NSArray *)underlyingError)
            N2ManagedDatabaseAppendErrorDetails(details, nestedError, depth + 1);
    }
}

static NSString *N2ManagedDatabaseStorageErrorDetails(NSError *error)
{
    NSMutableArray *details = [NSMutableArray array];
    N2ManagedDatabaseAppendErrorDetails(details, error, 0);
    return details.count ? [details componentsJoinedByString:@"\r"] : NSLocalizedString(@"No detailed error was provided by the persistent store.", nil);
}

static NSString *N2ManagedDatabaseBackupPathForSQLFile(NSString *sqlFilePath)
{
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";

    NSString *basePath = [NSString stringWithFormat:@"%@.failed-open-%@", sqlFilePath, [formatter stringFromDate:[NSDate date]]];
    for (NSUInteger index = 0; index < 1000; ++index) {
        NSString *candidate = index ? [NSString stringWithFormat:@"%@-%lu", basePath, (unsigned long)index] : basePath;
        if (![NSFileManager.defaultManager fileExistsAtPath:candidate])
            return candidate;
    }

    return [NSString stringWithFormat:@"%@-%u", basePath, arc4random()];
}

static NSString *N2ManagedDatabaseMoveSQLIndexAside(NSString *sqlFilePath, NSError **error)
{
    NSString *backupPath = N2ManagedDatabaseBackupPathForSQLFile(sqlFilePath);
    if (![NSFileManager.defaultManager moveItemAtPath:sqlFilePath toPath:backupPath error:error])
        return nil;

    for (NSString *suffix in @[@"-journal", @"-shm", @"-wal"]) {
        NSString *sidecarPath = [sqlFilePath stringByAppendingString:suffix];
        if (![NSFileManager.defaultManager fileExistsAtPath:sidecarPath])
            continue;

        NSError *sidecarError = nil;
        if (![NSFileManager.defaultManager moveItemAtPath:sidecarPath toPath:[backupPath stringByAppendingString:suffix] error:&sidecarError])
            NSLog(@"Warning: could not move database sidecar %@ aside: %@", sidecarPath, sidecarError);
    }

    return backupPath;
}

@interface N2ManagedDatabase ()

@property(readwrite,retain) NSString* sqlFilePath;
@property(readwrite,retain) id mainDatabase;

@end

#define N2PersistentStoreCoordinator NSPersistentStoreCoordinator // for debug purposes, disable this #define and enable the commented N2PersistentStoreCoordinator implementation

@interface N2ManagedObjectContext ()

@property (strong) N2ManagedObjectContext *confinementParentContext;

@end

@implementation N2ManagedObjectContext

@synthesize database = _database;
@synthesize confinementParentContext = _confinementParentContext;

- (id)initWithDatabase:(N2ManagedDatabase *)db concurrencyType:(NSManagedObjectContextConcurrencyType)ct
{
    if (!(self = [super initWithConcurrencyType:ct]))
        return nil;
    
    _database = db;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(N2ManagedDatabaseDealloced:) name:@"N2ManagedDatabaseDealloced" object:db];
    
#ifndef NDEBUG
    gTotalN2ManagedObjectContext++;
    
    if( gTotalN2ManagedObjectContext > 10)
        NSLog( @"-- gTotalN2ManagedObjectContext = %d", gTotalN2ManagedObjectContext);
#endif
    
    return self;
}

-(void)N2ManagedDatabaseDealloced:(NSNotification*) n
{
    if( n.object != _database)
        N2LogStackTrace( @"******* N2ManagedDatabaseDealloced");
    _database = nil;
}

-(void)dealloc {
#ifndef NDEBUG
    [_database checkForCorrectContextThread: self];
    
    gTotalN2ManagedObjectContext--;
#endif
    
    [NSNotificationCenter.defaultCenter removeObserver:self];

    self.confinementParentContext = nil;
    _database = nil;
	
    [super dealloc]; //test if db is deallocated
}

-(BOOL)save:(NSError**)error {
    [self lock];
#ifndef NDEBUG
    [_database checkForCorrectContextThread: self];
#endif
    @try {
        return [super save:error];
//        for (NSPersistentStore* ps in [[self persistentStoreCoordinator] persistentStores])
//            if (ps.URL.isFileURL)
//                [NSFileManager.defaultManager applyFileModeOfParentToItemAtPath:ps.URL.path];
    } @catch (...) {
        @throw;
    } @finally {
        [self unlock];
    }
    
    return NO;
}

-(NSManagedObject*)existingObjectWithID:(NSManagedObjectID*)objectID error:(NSError**)error {
    [self lock];
#ifndef NDEBUG
    [_database checkForCorrectContextThread: self];
#endif
    @try {
        return [super existingObjectWithID:objectID error:error];
    } @catch (...) {
        @throw;
    } @finally {
        [self unlock];
    }
    
    return nil;
}

/*
 http://developer.apple.com/DOCUMENTATION/Cocoa/Conceptual/CoreData/Articles/cdMultiThreading.html#//apple_ref/doc/uid/TP40003385-SW2
 "If you lock (or successfully tryLock) a context, that context must be retained until
 you invoke unlock. If you don’t properly retain a context in a multi-threaded environment, you may cause a deadlock."
 */

-(void)lock {
    [self retain];
//    [self.persistentStoreCoordinator lock];
    [super lock];
    
#ifndef NDEBUG
    [_database checkForCorrectContextThread: self];
#endif
    // for debug
/*    if (!lockhist)
        lockhist = [[NSMutableArray alloc] init];
    NSString* stack = nil;
    @try {
        [NSException raise:NSGenericException format:@""];
    } @catch (NSException* e) {
        stack = [e stackTrace];
    }
    if (stack)
        [lockhist addObject:stack];*/
}

-(void)unlock {
  //  [lockhist removeLastObject];
    [super unlock];
//    [self.persistentStoreCoordinator unlock];
    [self autorelease];
}

#ifndef NDEBUG
- (NSArray *)executeFetchRequest:(NSFetchRequest *)request error:(NSError **)error
{
    [_database checkForCorrectContextThread: self];
    
	return [super executeFetchRequest: request error: error];
}

- (void)deleteObject:(NSManagedObject *)object
{
    [_database checkForCorrectContextThread: self];
    
	return [super deleteObject: object];
}
- (NSUInteger)countForFetchRequest:(NSFetchRequest *)request error:(NSError **)error
{
    [_database checkForCorrectContextThread: self];
    
    return [super countForFetchRequest: request error: error];
}
- (NSManagedObject *)objectWithID:(NSManagedObjectID *)objectID
{
    [_database checkForCorrectContextThread: self];
    
    return [super objectWithID: objectID];
}
- (void)mergeChangesFromContextDidSaveNotification:(NSNotification *)notification
{
    [_database checkForCorrectContextThread: self];
    
    return [super mergeChangesFromContextDidSaveNotification: notification];
}
#endif

@end


@implementation N2ManagedDatabase
#ifndef NDEBUG
@synthesize associatedThread;
#endif
@synthesize sqlFilePath = _sqlFilePath;
@synthesize managedObjectContext = _managedObjectContext;
@synthesize mainDatabase = _mainDatabase;

#ifndef NDEBUG
-(void) checkForCorrectContextThread
{
    [self checkForCorrectContextThread: _managedObjectContext];
}

-(void) checkForCorrectContextThread: (NSManagedObjectContext*) c
{

    if( c == _managedObjectContext && associatedThread && associatedThread != [NSThread currentThread])
    {
        NSLog( @"------------------------------");
        NSLog( @"SQL path: %@", _sqlFilePath);
        N2LogStackTrace( @"--- warning : managedObjectContext was created in (%@, mainThread=%d), and is now used in (%@, mainThread=%d)", associatedThread.name, associatedThread == [NSThread mainThread], [[NSThread currentThread] name], [NSThread isMainThread]);
        NSLog( @"--");
    }
}
#endif

-(BOOL)isMainDatabase {
    return (_mainDatabase == nil);
}

-(NSManagedObjectContext*)managedObjectContext {
	return _managedObjectContext;
}

-(void)setManagedObjectContext:(NSManagedObjectContext*)managedObjectContext {
	if (managedObjectContext != _managedObjectContext) {
        [self willChangeValueForKey:@"managedObjectContext"];
        
        [_managedObjectContext autorelease];
		_managedObjectContext = [managedObjectContext retain];
        
#ifndef NDEBUG
        [associatedThread release];
        associatedThread = [[NSThread currentThread] retain];
#endif
        
        [self didChangeValueForKey:@"managedObjectContext"];
    }
}

+(NSString*)modelName {
	[NSException raise:NSGenericException format:@"[class modelName] must be defined"];
	return NULL;
}

-(BOOL) deleteSQLFileIfOpeningFailed
{
    return NO;
}

-(NSManagedObjectModel*)managedObjectModel {
	[NSException raise:NSGenericException format:@"[%@ managedObjectModel] must be defined", self.className];
	return NULL;
}

/*-(NSMutableDictionary*)persistentStoreCoordinatorsDictionary {
	static NSMutableDictionary* dict = NULL;
	if (!dict)
		dict = [[NSMutableDictionary alloc] initWithCapacity:4];
	return dict;
}*/

-(BOOL)migratePersistentStoresAutomatically {
	return YES;
}

- (void) renewManagedObjectContext
{
    self.managedObjectContext = self.isMainDatabase? [self contextAtPath: self.sqlFilePath] : [self.mainDatabase contextAtPath: self.sqlFilePath];
}

- (Class)NSManagedObjectContextClass {
    return N2ManagedObjectContext.class;
}

- (NSManagedObjectContext *)contextAtPath:(NSString *)sqlFilePath {
	sqlFilePath = sqlFilePath.stringByExpandingTildeInPath;
	
    if( sqlFilePath.length == 0)
        return nil;
    
    N2ManagedObjectContext *moc = [[[self.NSManagedObjectContextClass alloc] initWithDatabase:self concurrencyType:NSConfinementConcurrencyType] autorelease];
    //	NSLog(@"---------- NEW %@ at %@", moc, sqlFilePath);
	moc.undoManager = nil;
	
    //	NSMutableDictionary* persistentStoreCoordinatorsDictionary = self.persistentStoreCoordinatorsDictionary;
	
    @try {
        @synchronized (self) {
    //        if (self.managedObjectContext.hasChanges)
    //            [self save];
            
            if ([sqlFilePath isEqualToString:self.sqlFilePath] && [NSFileManager.defaultManager fileExistsAtPath:sqlFilePath]) {
                moc.confinementParentContext = (id)self.managedObjectContext; // just for retain purpose
                moc.persistentStoreCoordinator = self.managedObjectContext.persistentStoreCoordinator;
            }
            
            if (!moc.persistentStoreCoordinator) {
                //			moc.persistentStoreCoordinator = [persistentStoreCoordinatorsDictionary objectForKey:sqlFilePath];
                
                BOOL isNewFile = ![NSFileManager.defaultManager fileExistsAtPath:sqlFilePath];
                if (isNewFile)
                {
                    [[NSFileManager defaultManager] confirmDirectoryAtPath:[sqlFilePath stringByDeletingLastPathComponent]];
                    moc.persistentStoreCoordinator = nil;
                }
                
                if (!moc.persistentStoreCoordinator)
                {
                    NSString *localModelsPath = [[sqlFilePath stringByDeletingPathExtension] stringByAppendingPathExtension: @"momd"];
                    NSManagedObjectModel *models = self.managedObjectModel;
                    
                    if ([[NSFileManager defaultManager] fileExistsAtPath:localModelsPath]) @try {
                        NSManagedObjectModel *localModels = [[[NSManagedObjectModel alloc] initWithContentsOfURL: [NSURL fileURLWithPath: localModelsPath]] autorelease]; //Forward compatibility !
                        models = [NSManagedObjectModel modelByMergingModels: [NSArray arrayWithObjects: self.managedObjectModel, localModels, nil]]; //warning localModels can be nil: put it at last position
                    } @catch (NSException *exception) {
                        models = self.managedObjectModel;
                    }
                    
                    NSPersistentStoreCoordinator* persistentStoreCoordinator = moc.persistentStoreCoordinator = [[[N2PersistentStoreCoordinator alloc] initWithManagedObjectModel: models] autorelease];
                    
                    //[persistentStoreCoordinatorsDictionary setObject:persistentStoreCoordinator forKey:sqlFilePath];
                    
                    // SekhVet Paket CT: the app never runs on a context without a persistent store.
                    //  - Index databases (deleteSQLFileIfOpeningFailed == YES, i.e. the DICOM database), main thread:
                    //    the dialog is repeated until the index opens, the user resets it (moved aside, never deleted)
                    //    or quits. "Continue" used to leave the app running with a store-less context, so received
                    //    files were moved into the database folder without being indexed.
                    //  - Other databases (web portal users): SekhVet goes on without that database, and says so.
                    //  - Not on the main thread (no dialog possible): one retry, then nil is returned and the user is told once.
                    //  - The model copy beside the index (Database.momd) is only refreshed after the index has opened.
                    NSPersistentStore* pStore = nil;
                    BOOL isIndexDatabase = self.deleteSQLFileIfOpeningFailed;
                    int i = 0;
                    do { // try 2 times
                        ++i;
                        
                        NSError* err = nil;
                        NSDictionary* options = @{ NSInferMappingModelAutomaticallyOption: @YES,
                                                   NSMigratePersistentStoresAutomaticallyOption: @([self migratePersistentStoresAutomatically]),
                                                   NSSQLitePragmasOption: @{ @"journal_mode": @"delete" } };
                        NSURL* url = [NSURL fileURLWithPath:sqlFilePath];
                        @try {
                            pStore = [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:&err];
                            
                        } @catch (...) {
                        }
                        
                        if (!pStore)
                            NSLog(@"Error: [N2ManagedDatabase contextAtPath:] attempt %d: %@", i, [err description]);
                        
                        if (!pStore && [NSThread isMainThread] && isIndexDatabase)
                        {
                            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                            [alert setAlertStyle: NSAlertStyleCritical];
                            [alert setMessageText: [NSString stringWithFormat:NSLocalizedString(@"%@ Storage Error", nil), [self className]]];
                            [alert setInformativeText: [NSString stringWithFormat:
                                NSLocalizedString(@"SekhVet could not open the database SQL index file.\r\rThis can happen when the database volume is not mounted, macOS has not granted this copy of SekhVet access to the folder, the file is locked, or the SQL index is damaged.\r\rDatabase SQL index:\r%@\r\rDetails:\r%@\r\rSekhVet does not run without this index, because received images would then be stored without being indexed. Fix the cause and choose Try Again, or quit SekhVet.\r\rNothing is changed unless you choose Reset SQL Index: that moves the old index to a backup file beside it and lets SekhVet build a new one. If this is not the database you expected, do not reset it.", nil),
                                sqlFilePath,
                                N2ManagedDatabaseStorageErrorDetails(err)]];
                            [alert addButtonWithTitle: NSLocalizedString(@"Try Again", nil)];
                            [alert addButtonWithTitle: NSLocalizedString(@"Reveal in Finder", nil)];
                            [alert addButtonWithTitle: NSLocalizedString(@"Reset SQL Index...", nil)];
                            [alert addButtonWithTitle: NSLocalizedString(@"Quit SekhVet", nil)];
                            
                            NSInteger result = [alert runModal];
                            
                            i = 0; // main thread: every choice except Quit tries again, and the dialog returns if that fails too
                            
                            if (result == NSAlertFirstButtonReturn + 1) { // Reveal in Finder
                                [[NSWorkspace sharedWorkspace] selectFile:sqlFilePath inFileViewerRootedAtPath:[sqlFilePath stringByDeletingLastPathComponent]];
                            } else if (result == NSAlertFirstButtonReturn + 2) { // Reset SQL Index...
                                NSInteger confirmation = NSRunCriticalAlertPanel(
                                    [NSString stringWithFormat:NSLocalizedString(@"Reset %@ SQL Index?", nil), [self className]],
                                    @"%@\r\r%@",
                                    NSLocalizedString(@"Cancel", nil),
                                    NSLocalizedString(@"Reset SQL Index", nil),
                                    nil,
                                    NSLocalizedString(@"Only reset the SQL index if this is the database SekhVet should rebuild. If SekhVet is opening an unexpected folder, cancel and choose the correct database instead.\r\rSekhVet will move the existing SQL index to a backup file beside it, then try to create a new one. DICOM image files are not intentionally deleted, but database-only metadata may be missing until the old index is restored.", nil),
                                    sqlFilePath);
                                
                                // Sekhmet (P1, nach ystarrev/horos b587c43b): Index nie still loeschen, nur nach Rueckfrage beiseite legen.
                                if (confirmation == NSAlertAlternateReturn) {
                                    NSError *moveError = nil;
                                    NSString *backupPath = N2ManagedDatabaseMoveSQLIndexAside(sqlFilePath, &moveError);
                                    if (backupPath)
                                        NSLog(@"Moved SQL index %@ to %@ before rebuilding.", sqlFilePath, backupPath);
                                    else
                                        NSRunCriticalAlertPanel(
                                            [NSString stringWithFormat:NSLocalizedString(@"%@ Storage Error", nil), [self className]],
                                            @"%@\r\r%@\r\r%@",
                                            NSLocalizedString(@"OK", nil),
                                            nil,
                                            nil,
                                            NSLocalizedString(@"SekhVet could not move the SQL index aside, so it has not been reset.", nil),
                                            sqlFilePath,
                                            N2ManagedDatabaseStorageErrorDetails(moveError));
                                }
                            } else if (result == NSAlertFirstButtonReturn + 3) { // Quit SekhVet
                                NSLog(@"Quit: the database SQL index could not be opened and the user chose to quit. Nothing was changed.");
                                [[NSUserDefaults standardUserDefaults] synchronize];
                                exit(0);
                            }
                        }
                        else if (!pStore && [NSThread isMainThread] && i == 1)
                        {
                            NSInteger result = NSRunCriticalAlertPanel(
                                [NSString stringWithFormat:NSLocalizedString(@"%@ Storage Error", nil), [self className]],
                                @"%@",
                                NSLocalizedString(@"Continue", nil),
                                NSLocalizedString(@"Reveal in Finder", nil),
                                nil,
                                [NSString stringWithFormat:
                                    NSLocalizedString(@"SekhVet could not open this database file:\r%@\r\rDetails:\r%@\r\rThe file is left untouched. SekhVet continues without it; the functions that need it (for example the web portal user list) do not work until the problem is fixed and SekhVet is restarted.", nil),
                                    sqlFilePath,
                                    N2ManagedDatabaseStorageErrorDetails(err)]);
                            
                            if (result == NSAlertAlternateReturn)
                                [[NSWorkspace sharedWorkspace] selectFile:sqlFilePath inFileViewerRootedAtPath:[sqlFilePath stringByDeletingLastPathComponent]];
                        }
                    } while (!pStore && i < 2);
                    
                    if (!pStore && isIndexDatabase)
                    {
                        // only reached off the main thread
                        NSLog(@"***** [N2ManagedDatabase contextAtPath:] no persistent store for %@ (background thread) - returning no context", sqlFilePath);
                        
                        static BOOL backgroundFailureShown = NO;
                        if (backgroundFailureShown == NO)
                        {
                            backgroundFailureShown = YES;
                            NSString *failedPath = [[sqlFilePath copy] autorelease];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                NSRunCriticalAlertPanel(
                                    NSLocalizedString(@"Database Storage Error", nil),
                                    @"%@",
                                    NSLocalizedString(@"OK", nil),
                                    nil,
                                    nil,
                                    [NSString stringWithFormat: NSLocalizedString(@"SekhVet could not open a database SQL index for a background task:\r%@\r\rThat task was not carried out, and nothing was changed. Check that the database volume is connected and accessible, then quit and reopen SekhVet.", nil), failedPath]);
                            });
                        }
                        
                        [NSException raise:NSGenericException format:@"no persistent store for %@", sqlFilePath]; // caught below: nil is returned instead of a store-less context
                    }
                    
                    // Save the models for forward compatibility with old OsiriX versions that don't know the current model
                    if (pStore && self.saveDatabaseModel){ // SekhVet Paket CT: never beside an index that could not be opened
                        NSString *modelsPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: [[self class] modelName]];
                        [[NSFileManager defaultManager] removeItemAtPath: localModelsPath error: nil];
                        [[NSFileManager defaultManager] copyItemAtPath:modelsPath toPath:localModelsPath error:nil];
                    }

                }
                
                if (isNewFile) {
                    [moc save:NULL];
//                    NSLog(@"New database file created at %@", sqlFilePath);
                }
                
            } else {
                if (self.mainDatabase)
                    N2LogStackTrace(@"****************************: creating independent context from already independent database");
                
                // Our main DicomDatabase context will listen to changes from the independentContext
                // Warning: our independentContext will NOT receive changes from the main DicomDatabase context: add it by yourself if needed (see WebPortalConnection.mm)
                [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(mergeChangesFromContextDidSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:moc];
            }
            
        }
    }
    @catch (NSException *exception) {
        moc = nil;
    }
    
    return moc;
}

- (BOOL)saveDatabaseModel {
    return YES;
}

-(void)mergeChangesFromContextDidSaveNotification:(NSNotification*)n {
    NSManagedObjectContext* moc = [n object];
    
    if (self.managedObjectContext.persistentStoreCoordinator != moc.persistentStoreCoordinator)
        return;
    
    if (self.managedObjectContext == moc)
        return;
    
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(mergeChangesFromContextDidSaveNotification:) withObject:n waitUntilDone:NO];
    }
    else
    {
        [self.managedObjectContext lock];
        @try {
            [self.managedObjectContext mergeChangesFromContextDidSaveNotification:n];
            
        } @catch (NSException* e) {
            N2LogExceptionWithStackTrace(e);
        } @finally {
            [self.managedObjectContext unlock];
        }
    }
}

-(BOOL)lockBeforeDate:(NSDate*) date
{
    while( [[NSDate date] laterDate: date] == date)
    {
        if( [self.managedObjectContext tryLock])
            return YES;
        [NSThread sleepForTimeInterval: 0.1];
    }
    return NO;
}

-(void)lock {
	[self.managedObjectContext lock];
}

-(BOOL)tryLock {
	return [self.managedObjectContext tryLock];
}

-(void)unlock {
	[self.managedObjectContext unlock];
}

-(id)initWithPath:(NSString*)p {
	return [self initWithPath:p context:nil mainDatabase:nil];
}

-(id)initWithPath:(NSString*)p context:(NSManagedObjectContext*)c {
    return [self initWithPath:p context:c mainDatabase:nil];
}

-(id)initWithPath:(NSString*)p context:(NSManagedObjectContext*)c mainDatabase:(N2ManagedDatabase*)mainDbReference {
	self = [super init];
	
	self.sqlFilePath = p;
    self.mainDatabase = mainDbReference;
	
//#ifndef NDEBUG
//    if( [NSThread isMainThread] == NO && mainDbReference == nil)
//        NSLog( @"****** WARNING - Creating a MAIN database, NOT on the MAIN thread... Be aware that this managedObjectContext could be later used on the MAIN thread, unless you renewManagedObjectContext on the main thread.");
//#endif
    
	self.managedObjectContext = c? c : [self contextAtPath:p];
    
	return self;
}

-(void)dealloc {
    // this should fix dealloc cycles
    if (_isDeallocating)
        return;
    _isDeallocating = YES;
    
#ifndef NDEBUG
    [associatedThread release];
    associatedThread = nil;
#endif
    
    [NSNotificationCenter.defaultCenter postNotificationName: @"N2ManagedDatabaseDealloced" object:self];
    
    [NSNotificationCenter.defaultCenter removeObserver:self];
    
    if ([self.managedObjectContext hasChanges] && [NSFileManager.defaultManager fileExistsAtPath:[self.sqlFilePath stringByDeletingLastPathComponent]])
        [self save];
    
    if (self.mainDatabase)
        [NSNotificationCenter.defaultCenter removeObserver:self.mainDatabase name:NSManagedObjectContextDidSaveNotification object:self];
    
    self.mainDatabase = nil;
	self.managedObjectContext = nil;
	self.sqlFilePath = nil;
    
	[super dealloc];
}

- (NSManagedObjectContext *)independentContext:(BOOL)independent {
    if (!independent)
        return self.managedObjectContext;
    
#ifndef NDEBUG
    if ([NSThread isMainThread])
        N2LogStackTrace(@"info: independent context not required on main thread");
#endif
    
	NSManagedObjectContext *ic = [self contextAtPath:self.sqlFilePath];
    
    return ic;
}

- (NSManagedObjectContext *)independentContext {
	return [self independentContext:YES];
}

- (id)independentDatabase {
	return [[[[self class] alloc] initWithPath:self.sqlFilePath context:[self independentContext] mainDatabase:self] autorelease];
}

-(id)objectWithID:(id)oid {
    
#ifndef NDEBUG
    [self checkForCorrectContextThread];
#endif
    [self.managedObjectContext lock];
    @try {
        if ([oid isKindOfClass:[NSManagedObjectID class]]) {
            // nothing, just avoid all other checks for performance
        } else if ([oid isKindOfClass:[NSManagedObject class]]) {
            oid = [oid objectID];
        }
#ifndef OSIRIX_LIGHT
        else if ([oid isKindOfClass:[DCMTKQueryNode class]]) {
            return oid;
        }
#endif
        else if ([oid isKindOfClass:[NSURL class]]) {
            oid = [self.managedObjectContext.persistentStoreCoordinator managedObjectIDForURIRepresentation:oid];
        } else if ([oid isKindOfClass:[NSString class]]) {
            oid = [self.managedObjectContext.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:oid]];
        } // else we're in trouble: oid is invalid, but let's give Core Data a chance to handle it anyway
        return [self.managedObjectContext existingObjectWithID:oid error:NULL];
    } @catch (...) {
        // nothing, just return nil
    } @finally {
        [self.managedObjectContext unlock];
    }
    
    return nil;
}

-(NSArray*)objectsWithIDs:(NSArray*)objectIDs {
    
#ifndef NDEBUG
    [self checkForCorrectContextThread];
#endif
    
    [self.managedObjectContext lock];
    @try {
        NSMutableArray* r = [NSMutableArray arrayWithCapacity:objectIDs.count];
        for (id oid in objectIDs)
            @try {
                id o = [self objectWithID:oid];
                if (o) [r addObject:o];
            } @catch (NSException* e) {
                // nothing, just look for other objects
            }
        return r;
    } @catch (...) {
        @throw;
    } @finally {
        [self.managedObjectContext unlock];
    }
    
    return nil;
}

-(NSEntityDescription*)entityForName:(NSString*)name {
	return [NSEntityDescription entityForName:name inManagedObjectContext:self.managedObjectContext];
}

-(NSEntityDescription*)_entity:(id*)entity {
    if ([*entity isKindOfClass:[NSString class]])
        *entity = [self entityForName:*entity];
    return *entity;
}

-(NSArray*)objectsForEntity:(id)e {
	return [self objectsForEntity:e predicate:nil error:NULL];
}

-(NSArray*)objectsForEntity:(id)e predicate:(NSPredicate*)p {
	return [self objectsForEntity:e predicate:p error:NULL];
}

-(NSArray*)objectsForEntity:(id)e predicate:(NSPredicate*)p error:(NSError**)error {
    return [self objectsForEntity:e predicate:p error:error fetchLimit:0 sortDescriptors:nil];
}

-(NSArray*)objectsForEntity:(id)e predicate:(NSPredicate*)p error:(NSError**)error fetchLimit:(NSUInteger)fetchLimit sortDescriptors:(NSArray*)sortDescriptors{
	[self _entity:&e];
    
#ifndef NDEBUG
    [self checkForCorrectContextThread];
#endif
    
    NSFetchRequest* req = [[[NSFetchRequest alloc] init] autorelease];
	req.entity = e;
	req.predicate = p? p : [NSPredicate predicateWithValue:YES];
    req.sortDescriptors = sortDescriptors;
    if( fetchLimit>0)
        req.fetchLimit = fetchLimit;
    
    [self.managedObjectContext lock];
    @try {
        return [self.managedObjectContext executeFetchRequest:req error:error];
    } @catch (NSException* e) {
        if (error && !*error)
            *error = [NSError errorWithDomain:N2ErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:e.reason forKey:NSLocalizedDescriptionKey]];
        else N2LogException(e);
    } @finally {
        [self.managedObjectContext unlock];
    }
    
    return nil;
}

-(NSUInteger)countObjectsForEntity:(id)e {
	return [self countObjectsForEntity:e predicate:nil error:NULL];
}

-(NSUInteger)countObjectsForEntity:(id)e predicate:(NSPredicate*)p {
	return [self countObjectsForEntity:e predicate:p error:NULL];
}

-(NSUInteger)countObjectsForEntity:(id)e predicate:(NSPredicate*)p error:(NSError**)error {
	[self _entity:&e];

	NSFetchRequest* req = [[[NSFetchRequest alloc] init] autorelease];
	req.entity = e;
	req.predicate = p? p : [NSPredicate predicateWithValue:YES];
    
    [self.managedObjectContext lock];
    @try {
        return [self.managedObjectContext countForFetchRequest:req error:error];
    } @catch (NSException* e) {
        if (error && !*error)
            *error = [NSError errorWithDomain:N2ErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:e.reason forKey:NSLocalizedDescriptionKey]];
        else N2LogException(e);
    } @finally {
        [self.managedObjectContext unlock];
    }
    
	return 0;
}

-(id)newObjectForEntity:(id)entity {
    [self _entity:&entity];
    return [NSEntityDescription insertNewObjectForEntityForName:[entity name] inManagedObjectContext:self.managedObjectContext];
}

-(BOOL)save {
    return [self save:NULL];
}

-(BOOL)save:(NSError**)error {
	NSError* perr = NULL;
	if (!error) error = &perr;
	
	BOOL b = NO;
	
#ifndef NDEBUG
    [self checkForCorrectContextThread];
#endif
    
    [self.managedObjectContext lock];
    
    @try {
        b = [self.managedObjectContext save:error];
    } @catch(NSException* e) {
        if (error && !*error)
            *error = [NSError errorWithDomain:N2ErrorDomain code:1 userInfo:[NSDictionary dictionaryWithObject:e.reason forKey:NSLocalizedDescriptionKey]];
        else N2LogException(e);
    } @finally {
        [self.managedObjectContext unlock];
    }
	
	return b;
}


@end
