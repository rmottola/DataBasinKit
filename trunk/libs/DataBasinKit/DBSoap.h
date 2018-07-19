 /*
  Project: DataBasin

  Copyright (C) 2008-2018 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2008-11-13 22:44:45 +0100 by multix

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Library General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free
  Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
  Boston, MA 02111 USA.
*/

#import <Foundation/Foundation.h>
#import <WebServices/WebServices.h>

#if defined(__APPLE__) && (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)
#ifndef NSUInteger
#define NSUInteger unsigned int
#endif
#ifndef NSInteger
#define NSInteger int
#endif
#endif

/* some Salesforce limits */
#define MAX_SOQL_LENGTH 20000
#define MAX_SOQL WHERE_LENGTH 4000
#define MAX_BATCH_SIZE 200
#define RETRIEVE_BATCH_SIZE 2000

#define CLIENT_NAME @"DataBasin"

@class DBSObject;
@protocol DBProgressProtocol;
@protocol DBLoggerProtocol;

@interface DBSoap : NSObject
{
  GWSService *service;
  id<DBLoggerProtocol> logger;
    
  /* salesforce.com session variables */
  NSString     *sessionId;
  NSString     *serverUrl;
  BOOL         passwordExpired;
  NSDictionary *userInfo;

  /* list of all objects, custom and not */
  NSArray  *sObjectList;
  /* list of all object names, custom and not */
  NSMutableArray  *sObjectNamesList;
  /* Map of described objects, for which details are present */
  NSMutableDictionary *sObjectDetailsDict;

  /** create, update, upsert batch size */
  unsigned upBatchSize;

  /** query batch size */
  unsigned downBatchSize;
  
  /** actually used SOQL length, must be inferior to MAX_SOQL_LENGTH */
  unsigned maxSOQLLength;

  /** Timeout in seconds, for generic methods */
  unsigned standardTimeoutSec;

  /** Timeout in seconds, for query methods */
  unsigned queryTimeoutSec;
  
  /** is executing */
  NSUInteger *busyCount;
  NSRecursiveLock *lockBusy;

  /** describe each object in a query to get field types */
  BOOL enableFieldTypesDescribeForQuery;

  /** return positive results */
  BOOL returnSuccessResults;

  /** return multiple errors per object, else only the first is retrieved */
  BOOL returnMultipleErrors;
}

+ (NSArray *)fieldsByParsingQuery:(NSString *)query;
+ (NSURL *)loginURLProduction;
+ (NSURL *)loginURLTest;
+ (GWSService *)gwserviceForDBSoap;

- (void)login :(NSURL *)url :(NSString *)userName :(NSString *)password :(BOOL)useHttps;
- (void)setLogger: (id<DBLoggerProtocol>)l;
- (id<DBLoggerProtocol>)logger;
- (unsigned)upBatchSize;
- (void)setUpBatchSize:(unsigned)size;
- (unsigned)downBatchSize;
- (void)setDownBatchSize:(unsigned)size;
- (unsigned)maxSOQLLength;
- (void)setMaxSOQLLength:(unsigned)size;
- (NSMutableArray *)queryFull :(NSString *)queryString queryAll:(BOOL)all progressMonitor:(id<DBProgressProtocol>)p;
- (NSString *)query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;
- (NSString *)queryMore :(NSString *)locator toArray:(NSMutableArray *)objects;
- (void)queryIdentify :(NSString *)queryString with: (NSArray *)identifiers queryAll:(BOOL)all fromArray:(NSArray *)fromArray toArray:(NSMutableArray *)outArray withBatchSize:(int)batchSize progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableArray *)create :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableArray *)update :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableArray *)delete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableArray *)undelete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;

- (NSMutableArray *)retrieveWithQuery:(NSString *)queryString andObjects:(NSArray *)objectList;
- (NSMutableArray *)retrieveFields:(NSArray *)fieldList ofObject:(NSString *)objectType fromArray:(NSArray *)objectList;


- (NSMutableDictionary *)getUpdated :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate;
- (NSMutableDictionary *)getDeleted :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate;

- (NSArray *)describeGlobal;
- (NSArray *)sObjects;
- (NSArray *)sObjectNames;
- (void)updateObjects;
- (DBSObject *)describeSObject: (NSString *)objectType;
- (NSString *)identifyObjectById:(NSString *)sfId;
- (void)flushObjectDetails;
- (BOOL)enableFieldTypesDescribeForQuery;
- (void)setEnableFieldTypesDescribeForQuery:(BOOL)flag;
- (NSMutableDictionary *)sObjectDetailsDict;
- (void)setSObjectDetailsDict:(NSMutableDictionary *)md;

- (NSString *) sessionId;
- (void) setSessionId:(NSString *)session;
- (NSString *) serverUrl;
- (void) setServerUrl:(NSString *)urlStr;
- (BOOL) passwordExpired;
- (NSDictionary *) userInfo;
- (void)setService:(GWSService *)serv;

- (void)setStandardTimeout:(unsigned)sec;
- (void)setQueryTimeout:(unsigned)sec;
- (unsigned)standardTimeout;
- (unsigned)queryTimeout;

- (BOOL)isBusy;

@end

@interface DBSoap (Selecting)

- (NSString *)_query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects declaredSize:(NSUInteger *)ds progressMonitor:(id<DBProgressProtocol>)p;

- (NSString *)_queryMore :(NSString *)locator toArray:(NSMutableArray *)objects;

- (NSMutableArray *)_queryFull :(NSString *)queryString queryAll:(BOOL)all progressMonitor:(id<DBProgressProtocol>)p;

- (void)_queryIdentify :(NSString *)queryString with: (NSArray *)identifiers queryAll:(BOOL)all fromArray:(NSArray *)fromArray toArray:(NSMutableArray *)outArray withBatchSize:(int)batchSize progressMonitor:(id<DBProgressProtocol>)p;

- (NSMutableArray *)_retrieveFields:(NSArray *)fieldList ofObject:(NSString*)objectType fromObjects:(NSArray *)objectList;


@end


@interface DBSoap (Updating)

- (NSMutableArray *)_update :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableDictionary *)_getUpdated :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate;

@end


@interface DBSoap (Creating)

- (NSMutableArray *)_create :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;

@end


@interface DBSoap (Deleting)

- (NSMutableArray *)_delete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableArray *)_undelete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;
- (NSMutableDictionary *)_getDeleted :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate;

@end

@interface DBSoap (PrivateMethods)
- (DBSObject *)_describeSObject: (NSString *)objectType;
- (NSArray *)_describeGlobal;
- (id)adjustFormatForField:(NSString *)key forValue:(id)value inObject:(DBSObject *)sObj;
- (void)extractQueryRecords:(NSArray *)records toObjects:(NSMutableArray *)objects;
@end
