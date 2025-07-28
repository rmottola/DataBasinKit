/* -*- mode: objc -*-
   Project: DataBasinKit

   Copyright (C) 2019-2025 Free Software Foundation

   Author: Riccardo Mottola

   Created: 2019-05-13 14:40:47 +0000 by Riccardo Mottola

   This application is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This application is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
*/

#import "DBRest.h"
#import "DBSObject.h"

#import "DBProgressProtocol.h"
#import "DBLoggerProtocol.h"

@implementation DBRest

+ (NSString *)encodeQueryString:(NSString *)query
{
  NSMutableString *eq;

  eq = [NSMutableString stringWithString:query];
  [eq replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [eq length])];

  return [NSString stringWithString:eq];
}

- (id)init
{
  if ((self = [super init]))
    {
    }
  return self;
}

- (void)setLogger: (id<DBLoggerProtocol>)l
{
  if (logger)
    [logger release];
  logger = [l retain];
}

- (id<DBLoggerProtocol>)logger
{
  return logger;
}

/** <p>execute SOQL query and write the resulting DBSObjects into the <i>objects</i> array
 which must be valid and allocated. </p>
 <p>If the query locator is returned,  a query more has to be executed.</p>
 <p>Returns exception</p>
 */
- (NSString *)query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  NSString *queryLocator;
  NSUInteger ds;

  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBRest query] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  queryLocator = nil;
  NS_DURING
    queryLocator = [self _query:queryString queryAll:all toArray:objects declaredSize:&ds progressMonitor:p];
  NS_HANDLER
    {
      [lockBusy lock];
      busyCount--;
      [lockBusy unlock];
      [localException raise];
    }
  NS_ENDHANDLER

  [lockBusy lock];
  busyCount--;
  [lockBusy unlock];

  return queryLocator;
}

/* A record of the result - may contain nested objects of subqueries */
- (DBSObject *)extractQueryRecord:(NSDictionary *)record
{
  NSUInteger      j;
  DBSObject      *sObj;
  NSMutableArray *keys;
  NSDictionary    *attributes;

  sObj = [[DBSObject alloc] init];

  NSLog(@"extract record: %@", record);

  keys = [[record allKeys] mutableCopy];
  attributes = [record objectForKey:@"attributes"];

  if (attributes)
    {
      NSDictionary *propDict;
      NSString *typeStr;

      typeStr = [attributes objectForKey: @"type"];
      propDict = [NSDictionary dictionaryWithObject:typeStr forKey:@"type"];
      [sObj setObjectProperties: propDict];
      [keys removeObject:@"attributes"];
    }

  for (j = 0; j < [keys count]; j++)
    {
      id       obj;
      id       value;
      NSString *key;

      key = [keys objectAtIndex:j];
      obj = [record objectForKey: key];
      //      NSLog(@"analyzing %@ : %@", key, obj);
      if ([key isEqualToString:@"Id"])
	{
	  [sObj setValue: obj forField: key];
	}
      else if ([obj isKindOfClass:[NSDictionary class]])
	{
	  // This is recurisve, it is a sub-query result
	  NSDictionary *result = (NSDictionary *)obj;
	  id           subRecords;

	  subRecords = [obj objectForKey:@"records"];
	  if (subRecords != nil)
	    {
	      NSString       *sizeStr;
	      int             size;

	      // We have a sub-query or otherwise a list of records
	      sizeStr = [result objectForKey:@"size"];
	      size = [sizeStr intValue];

	      /* if we have only one element, we just recurse */
	      if (size == 1)
		{
		  DBSObject *o;
		  o = [self extractQueryRecord:subRecords];
		  [sObj setValue:o forField: key];
		}
	      else
		{
		  NSMutableArray *subObjects;
		  subObjects = [NSMutableArray new];
		  [self extractQueryRecords:subRecords toObjects:subObjects];
		  [sObj setValue:subObjects forField: key];
		  [subObjects release];
		}
	    }
	  else
	    {
	      value = obj;
	      //NSLog(@"complex field: %@", value);
	      // we have a complex field, but not an object
	      if (enableFieldTypesDescribeForQuery)
		{
		  value = [self adjustFormatForField:key forValue:value inObject:sObj];
		}
	      [sObj setValue: value forField: key];
	    }
	}
      else
	{
	  value = obj;
	  if (enableFieldTypesDescribeForQuery)
	    {
	      value = [self adjustFormatForField:key forValue:value inObject:sObj];
	    }
	  [sObj setValue: value forField: key];
	}
    }

  NSLog(@"extracted sObject is: %@", sObj);
  return [sObj autorelease];
}
/*
 Parses a result: this can be the main result but can also be nested in case of a subquery (nested query)
 */
- (void)extractQueryRecords:(NSArray *)records toObjects:(NSMutableArray *)objects
{
  NSUInteger     i;
  NSUInteger     batchSize;
  NSMutableArray *keys;

  if (records == nil || [records count] == 0)
    return;

  [records retain];
  batchSize = [records count];

  [logger log: LogInformative :@"[DBSoap extractQueryRecords] records size is: %d\n", batchSize];

  /* now cycle all the records and read out the fields */
  for (i = 0; i < batchSize; i++)
    {
      DBSObject *sObj;
      NSDictionary          *record;

      record = [records objectAtIndex:i];
      [logger log: LogDebug: @"[DBSoap query] record :%@\n", record];

      sObj = [self extractQueryRecord:record];

      [objects addObject:sObj];
    }
  [records release];
}

- (NSString *)_query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects declaredSize:(NSUInteger *)ds progressMonitor:(id<DBProgressProtocol>)p
{
  NSURL                 *url;
  NSString              *queryCommand;
  NSDictionary          *headers;
  NSDictionary          *response;
  NSDictionary          *result;
  NSString              *doneStr;
  BOOL                  done;
  GWSService            *gsrv;
  GWSJSONCoder          *coder;
  NSString              *bearerStr;
  NSURLComponents       *urlComp;
  NSDictionary          *queryResult;
  NSDictionary          *coderError;
  NSDictionary          *queryFault;
  NSNumber              *sizeNum;
  NSUInteger            size;
  NSArray               *records;
  BOOL                  isCountQuery;

  /* if the destination array is nil, exit */
  if (objects == nil)
    return nil;

  /* we need to check if the query contains count() since it requires special handling to fake an AggregateResult */
  isCountQuery = NO;
  if ([queryString rangeOfString:@"count()" options:NSCaseInsensitiveSearch].location != NSNotFound)
    isCountQuery = YES;

  *ds = 0;

  bearerStr = [@"Bearer " stringByAppendingString:sessionId];
  headers = [NSDictionary dictionaryWithObjectsAndKeys:
			    @"application/json; charset=utf-8", @"Content-Type",
			  bearerStr, @"Authorization",
			  nil];

  queryCommand = [@"q=" stringByAppendingString:[DBRest encodeQueryString:queryString]];
  urlComp = [NSURLComponents componentsWithURL:serverURL resolvingAgainstBaseURL:NO];
  [urlComp setPath:[[urlComp path] stringByAppendingPathComponent:@"query"]];
  [urlComp setQuery:queryCommand];
  url = [urlComp URL];
  NSLog(@"URL: %@", url);
  gsrv = [[GWSService alloc] init];

  [gsrv setHeaders:headers];
  [gsrv setDebug:YES];
  [gsrv setURL:url];
  [gsrv setHTTPMethod:@"GET"];
  
  coder = [GWSJSONCoder new];
  [gsrv setCoder:coder];
  [coder release];
  [gsrv setDelegate:self];
  response = [gsrv invokeMethod:@"query"
		     parameters: nil
			  order: nil
			timeout: 30];
  [gsrv setDelegate:nil];
  NSLog(@"response: %@", response);

  [logger log: LogDebug: @"[DBRest query] result: %@\n", response];
  coderError = [response objectForKey:GWSErrorKey];

  if ((result = [response objectForKey: GWSErrorKey]) != nil)
    {
      [logger log: LogStandard :@"[DBRest query] error: %@\n", coderError];
      [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
    }
  else if ((result = [response objectForKey: GWSFaultKey]) != nil)
    {
      NSLog(@"Fault!");
    }

  queryResult = [response objectForKey:GWSParametersKey];
  result = [queryResult objectForKey:@"Result"];
  NSLog(@"Result: %@", result);

  [logger log: LogDebug: @"[DBRest query] result: %@\n", result];

  queryFault = [result objectForKey:@"errorCode"];
  if (queryFault != nil)
    {
      NSDictionary *faultDetail;
      NSString *message;

      message = [response objectForKey:@"message"];
      [logger log: LogStandard: @"[DBSoap query] exception: %@\n", message];
      [[NSException exceptionWithName:@"DBException" reason:message userInfo:nil] raise];
    }

  done = [[result objectForKey:@"done"] boolValue];
  records = [result objectForKey:@"records"];
  sizeNum = [result objectForKey:@"totalSize"];

  [logger log: LogDebug: @"[DBRest query] done: %d\n", done];

  if (sizeNum != nil)
    {
      NSScanner *scan;

      size = [sizeNum integerValue];
      [logger log: LogInformative: @"[DBRest query] Declared size is: %lu\n", size];
      *ds = size;
    }
  else
    {
      [logger log: LogStandard : @"[DBRest query] Could not parse Size Value: %@\n", sizeNum];
      return nil;
    }

  if (size == 0)
    return nil;

  [p setMaximumValue: size];

  /* if we have only one element, put it in an array */
  if (records != nil)
    {
      if (size == 1)
	{
	  records = [NSArray arrayWithObject:records];
	}
      [self extractQueryRecords:records toObjects:objects];
    }
  else
    {
      /* Count() is not like to aggregate count(Id) and returns no AggregateResult
	 but returns just a size count without an actual records array.
	 Thus we fake one single object as AggregateResult. */
      if (done && isCountQuery)
	{
	  DBSObject *sObj;

	  sObj = [[DBSObject alloc] init];
	  [sObj setValue: [NSNumber numberWithUnsignedLong:size] forField: @"count"];
	  [objects addObject:sObj];
	  [sObj release];
	}
      else
	{
	  NSLog(@"[DBRest query] unexpected: no records but not a complete count query");
	}
    }

  NSLog(@"Records: %@", records);

  [gsrv release];

  return nil; // should be Query Locator
}

/* GSWService Delegate */
- (NSData*) webService: (GWSService*)service
          buildRequest: (NSString*)method
            parameters: (NSDictionary*)parameters
                 order: (NSArray*)order;
{
  // For REST Requests the body is nil, so return an empty one. Responses are JSON of course.
  // Overriding delegate, otherwise the JSONCoder of WebService creates an empty JSON which is put in the body
  return [NSData data];
}

/* accessors*/
- (NSString *) sessionId
{
  return sessionId;
}

- (void) setSessionId:(NSString *)session
{
  if (sessionId != session)
    {
      [sessionId release];
      sessionId = session;
      [sessionId retain];
    }
}

- (NSURL *) serverURL
{
  return serverURL;
}

/*
 * <host>/services/data/vXX.X/
 */
- (void) setServerURL:(NSURL *)url
{
  if (serverURL != url)
    {
      [serverURL release];
      serverURL = url;
      [serverURL retain];
    }
}


- (void)dealloc
{
  [sessionId release];
  [service release];
  [super dealloc];
}

@end
