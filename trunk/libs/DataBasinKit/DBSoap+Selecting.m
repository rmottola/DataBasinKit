/*
   Project: DataBasinKit

   Copyright (C) 2008-2017 Free Software Foundation

   Author: multix

   Created: 2017-11-10 11:35:34 +0100 by multix

   This application is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This application is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/

#import "DBSoap.h"
#import "DBSObject.h"

#import "DBProgressProtocol.h"
#import "DBLoggerProtocol.h"

#import "DBSFTypeWrappers.h"


@implementation DBSoap (Selecting)

- (NSString *)_query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects declaredSize:(NSUInteger *)ds progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableDictionary   *queryOptionsDict;
  NSMutableDictionary   *parmsDict;
  NSMutableDictionary   *queryParmDict;
  NSDictionary          *resultDict;
  NSDictionary          *queryResult;
  NSDictionary          *result;
  NSString              *doneStr;
  BOOL                  done;
  NSString              *queryLocator;
  NSArray               *records;
  NSDictionary          *queryFault;
  NSDictionary          *coderError;
  NSString              *sizeStr;
  unsigned long         size;
  BOOL                  isCountQuery;
  NSString              *requestName;

  /* if the destination array is nil, exit */
  if (objects == nil)
    return nil;

  /* we need to check if the query contains count() since it requires special handling to fake an AggregateResult */
  isCountQuery = NO;
  if ([queryString rangeOfString:@"count()" options:NSCaseInsensitiveSearch].location != NSNotFound)
    isCountQuery = YES;

  queryLocator = nil;
  *ds = 0;
 
  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  queryOptionsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [queryOptionsDict setObject: [NSNumber numberWithInt:downBatchSize] forKey: @"batchSize"];
  [queryOptionsDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
  
  headerDict = [NSMutableDictionary dictionaryWithCapacity: 3];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: queryOptionsDict forKey: @"QueryOptions"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];
  
  /* prepare the parameters */
  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
  [queryParmDict setObject: queryString forKey: @"queryString"];
  
  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  
  
  /* make the query */
  requestName = @"query";
  if (all)
    requestName = @"queryAll";

  [parmsDict setObject: queryParmDict forKey: requestName];
  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];
  resultDict = [service invokeMethod: @"queryAll"
                         parameters : parmsDict
                              order : nil
                            timeout : queryTimeoutSec];
  
  [logger log: LogDebug: @"[DBSoap query] result: %@\n", resultDict];
  coderError = [resultDict objectForKey:GWSErrorKey];
  if (coderError != nil)
    {
      [logger log: LogStandard :@"[DBSoap query] error: %@\n", coderError];
      [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
    }
  queryFault = [resultDict objectForKey:GWSFaultKey];
  if (queryFault != nil)
    {
      NSDictionary *faultDetail;
      NSString *faultName;
    
      faultDetail = [queryFault objectForKey:@"detail"];
      faultName = [[faultDetail objectForKey:GWSOrderKey] objectAtIndex: 0];
      if (faultName)
	{
	  NSDictionary *fault;
	  NSString *exceptionMessage;

	  [logger log: LogInformative: @"[DBSoap query] fault name: %@\n", faultName];
	  fault = [faultDetail objectForKey:faultName];
	  exceptionMessage = [fault objectForKey:@"exceptionMessage"];

	  [logger log: LogStandard: @"[DBSoap query] exception code: %@\n", [fault objectForKey:@"exceptionCode"]];
	  [logger log: LogStandard: @"[DBSoap query] exception: %@\n", exceptionMessage];
	  [[NSException exceptionWithName:@"DBException" reason:exceptionMessage userInfo:nil] raise];
	}
      else
	{
	  [logger log: LogInformative: @"[DBSoap query] fault detail: %@\n", faultDetail];
	}
      return nil;
    }
  
  queryResult = [resultDict objectForKey:GWSParametersKey];
  result = [queryResult objectForKey:@"result"];
  [logger log: LogDebug: @"[DBSoap query] result: %@\n", result];  
  doneStr = [result objectForKey:@"done"];
  records = [result objectForKey:@"records"];
  sizeStr = [result objectForKey:@"size"];
  
  if (doneStr != nil)
    {
      [logger log: LogDebug: @"[DBSoap query] done: %@\n", doneStr];
      done = NO;
      if ([doneStr isEqualToString:@"true"])
        done = YES;
      else if ([doneStr isEqualToString:@"false"])
        done = NO;
      else
        [logger log: LogStandard: @"[DBSoap query] Done, unexpected value: %@\n", doneStr];
    }
  else
    {
      [logger log: LogStandard: @"[DBSoap query] error, doneStr is nil: unexpected\n"];
      return nil;
    }
  [result retain];
  if (sizeStr != nil)
    {
      NSScanner *scan;
      long long ll;

      scan = [NSScanner scannerWithString:sizeStr];
      if ([scan scanLongLong:&ll])
        {
          size = (unsigned long)ll;
          [logger log: LogInformative: @"[DBSoap query] Declared size is: %lu\n", size];
          *ds = (NSUInteger)ll;
        }
      else
	{
          [logger log: LogStandard : @"[DBSoap query] Could not parse Size string: %@\n", sizeStr];
          [result release];
          return nil;
        }
      
      
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
              NSLog(@"[DBSoap query] unexpected: no records but not a complete count query");
            }
        }
    }
  if (!done)
    {
      queryLocator = [result objectForKey:@"queryLocator"];
      [[queryLocator retain] autorelease];
      [logger log: LogDebug: @"[DBSoap query] should do query more, queryLocator: %@\n", queryLocator];
    }
  
  [result release];
  return queryLocator;
}



- (NSString *)_queryMore :(NSString *)locator toArray:(NSMutableArray *)objects
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *queryOptionsDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableDictionary   *parmsDict;
  NSMutableDictionary   *queryParmDict;
  NSDictionary          *resultDict;
  NSDictionary          *queryResult;
  NSDictionary          *result;
  NSString              *doneStr;
  BOOL                  done;
  NSString              *queryLocator;
  NSArray               *records;
  NSDictionary          *queryFault;

  /* if the destination array is nil, exit */
  if (objects == nil)
    return nil;
  
  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  queryOptionsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [queryOptionsDict setObject: [NSNumber numberWithInt:downBatchSize] forKey: @"batchSize"];
  [queryOptionsDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: queryOptionsDict forKey: @"QueryOptions"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];

  /* prepare the parameters */
  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
  [queryParmDict setObject: locator forKey: @"queryLocator"];  

  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [parmsDict setObject: queryParmDict forKey: @"queryMore"];
  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey]; 

  /* make the query */  
  resultDict = [service invokeMethod: @"queryMore"
                         parameters : parmsDict
                              order : nil
                            timeout : queryTimeoutSec];
  

  queryLocator = nil;
  queryFault = [resultDict objectForKey:GWSFaultKey];
  if (queryFault != nil)
    {
      NSDictionary *faultDetail;
      NSString *faultName;

      faultDetail = [queryFault objectForKey:@"detail"];
      faultName = [[faultDetail objectForKey:GWSOrderKey] objectAtIndex: 0];
      if (faultName)
	{
	  NSDictionary *fault;
	  NSString *exceptionMessage;

	  [logger log: LogInformative: @"[DBSoap queryMore] fault name: %@\n", faultName];
	  fault = [faultDetail objectForKey:faultName];
	  exceptionMessage = [fault objectForKey:@"exceptionMessage"];

	  [logger log: LogStandard: @"[DBSoap queryMore] exception code: %@\n", [fault objectForKey:@"exceptionCode"]];
	  [logger log: LogStandard: @"[DBSoap queryMore] exception: %@\n", exceptionMessage];
	  [[NSException exceptionWithName:@"DBException" reason:exceptionMessage userInfo:nil] raise];
	}
      else
	{
	  [logger log: LogInformative: @"[DBSoap query] fault detail: %@\n", faultDetail];
	}
      return nil;
    }

  queryResult = [resultDict objectForKey:GWSParametersKey];
  result = [queryResult objectForKey:@"result"];

  doneStr = [result objectForKey:@"done"];
  records = [result objectForKey:@"records"];

  if (doneStr != nil)
    {
      [logger log: LogDebug: @"[DBSoap queryMore] done: %@\n", doneStr];
      done = NO;
      if ([doneStr isEqualToString:@"true"])
        done = YES;
      else if ([doneStr isEqualToString:@"false"])
        done = NO;
      else
        [logger log: LogStandard: @"[DBSoap queryMore] Done, unexpected value: %@\n", doneStr];
    }
  else
    {
      [logger log: LogStandard: @"[DBSoap queryMore] error, doneStr is nil: unexpected\n"];
      return nil;
    }

  [result retain];
  // Size returned in queryMore refers to the original size of the query
  // not to the current batch
  // So we can just check against the actually returned records
  if (records != nil)
    {
      /* if we have only one element, put it in an array */
      if (![records isKindOfClass:[NSArray class]])
        {
          records = [NSArray arrayWithObject:records];
        }
      [self extractQueryRecords:records toObjects:objects];
    }
  if (!done)
    {
      queryLocator = [result objectForKey:@"queryLocator"];
      [[queryLocator retain] autorelease];
      [logger log: LogInformative: @"[DBSoap queryMore] should do query more, queryLocator: %@\n", queryLocator];
    }

  [result release];
  return queryLocator;
}


- (NSMutableArray *)_queryFull :(NSString *)queryString queryAll:(BOOL)all progressMonitor:(id<DBProgressProtocol>)p
{
  NSString       *qLoc;
  NSMutableArray *sObjects;
  NSUInteger     ds;
  
  sObjects = [[NSMutableArray alloc] init];
  
  qLoc = [self _query: queryString queryAll:all toArray:sObjects declaredSize:&ds progressMonitor:p];
  [logger log: LogInformative: @"[DBSoap queryFull]: query locator after first query: %@\n", qLoc];
  while (qLoc != nil  && ![p shouldStop])
    qLoc = [self _queryMore: qLoc toArray: sObjects];

  // NSLog(@"_query declared size vs. actual size %lu %lu", (unsigned long)ds, (unsigned long)[sObjects count]);
  if (ds != [sObjects count])
    [logger log: LogStandard: @"[DBSoap queryFull]: delcared size and actual array size differ: %lu %lu\n", (unsigned long)ds, (unsigned long)[sObjects count]];
  else
    [logger log: LogInformative: @"[DBSoap queryFull]: declared size %lu vs. actual size:%lu\n", (unsigned long)ds, (unsigned long)[sObjects count]];
  
  [sObjects autorelease];
  
  return sObjects;
}



- (void)_queryIdentify :(NSString *)queryString with: (NSArray *)identifiers queryAll:(BOOL)all fromArray:(NSArray *)fromArray toArray:(NSMutableArray *)outArray withBatchSize:(int)batchSize progressMonitor:(id<DBProgressProtocol>)p
{
  NSUInteger i;
  BOOL batchable;
  BOOL autoBatch;
  BOOL multiKey;
  NSString *identifier;
  NSString *queryFirstPart;
  NSString *queryOptionsPart;
  NSUInteger groupByLocation;
  NSUInteger orderByLocation;
  NSUInteger limitLocation;
  NSUInteger optionsLocation;

  /* SELECT fieldList FROM object WHERE condition GROUP BY list ORDER BY list LIMIT ? */
  multiKey = NO;
  identifier = nil;
  if ([identifiers count] > 1)
    {
      multiKey = YES;
      [logger log: LogDebug: @"[DBSoap queryIdentify], multi-identifier %@\n", identifiers];
    }
  else if ([identifiers count] == 1)
    {
      multiKey = NO;
      identifier = [identifiers objectAtIndex:0];
      [logger log: LogDebug: @"[DBSoap queryIdentify], single identifier: %@\n", identifier];
    }
  else
    {
      [logger log: LogStandard: @"[DBSoap queryIdentify] Unexpected identifier count: %u\n", (unsigned int)[identifiers count]];
    }

  batchable = NO;
  autoBatch = NO;
  if (batchSize < 0)
    {
      autoBatch = YES;
      batchable = YES;
    }
  else if (batchSize > 1)
    batchable = YES;
  
  optionsLocation = NSNotFound;
  groupByLocation = [queryString rangeOfString: @"GROUP BY" options:NSCaseInsensitiveSearch].location;
  orderByLocation = [queryString rangeOfString: @"ORDER BY" options:NSCaseInsensitiveSearch].location;

  if (orderByLocation != NSNotFound)
    optionsLocation = orderByLocation;

  if (groupByLocation != NSNotFound)
    optionsLocation = groupByLocation;

  limitLocation = [queryString rangeOfString: @"LIMIT " options:NSCaseInsensitiveSearch].location;
  if (limitLocation != NSNotFound || optionsLocation != NSNotFound)
    {
      if (batchable)
        {
          [logger log: LogStandard: @"[DBSoap queryIdentify] option specifier incompatible with batch size > 1\n"];
          [[NSException exceptionWithName:@"DBException" reason:@"Query Identify: Option specifier incompatible with batch size > 1" userInfo:nil] raise];
          return;
        }

      if (limitLocation != NSNotFound)
        {
          if (optionsLocation != NSNotFound)
            {
              if  (optionsLocation > limitLocation)
                {
                  [logger log: LogStandard: @"[DBSoap queryIdentify] LIMIT specifier found before ORDER BY or GROUP BY, ignoring\n"];
                  optionsLocation = limitLocation;
                }  
            }
          else
            {
              optionsLocation = limitLocation;
            }
        }
      NSAssert(optionsLocation != NSNotFound, @"[DBSoap queryIdentify] optionsLocation can't be NSNotFound here");
      queryFirstPart = [queryString substringToIndex:optionsLocation];
      queryOptionsPart = [queryString substringFromIndex:optionsLocation];
      [logger log: LogDebug: @"[DBSoap queryIdentify] Query Options: %@\n", queryOptionsPart];
    }
  else
    {
      queryFirstPart = queryString;
      queryOptionsPart = nil;
    }

  i = 0;
  while (i < [fromArray count] && ![p shouldStop])
    {
      unsigned b;

      NSMutableString *completeQuery;
      NSMutableArray *resArray;

      NSString *currKeyString;
      NSArray *currKeyArray;

      if (multiKey)
	{
	  currKeyArray = (NSArray*)[fromArray objectAtIndex: i];
	  currKeyString = nil;
	  [logger log: LogDebug: @"[DBSoap queryIdentify], multi-key %u %@\n", i, currKeyArray];
	}
      else
	{
	  currKeyString = (NSString*)[fromArray objectAtIndex: i];
	  currKeyArray = nil;
	  [logger log: LogDebug: @"[DBSoap queryIdentify], single key %u %@\n", i, currKeyString];
	}

      completeQuery = [[NSMutableString stringWithString: queryFirstPart] retain];
      if ([queryFirstPart rangeOfString:@"WHERE" options:NSCaseInsensitiveSearch].location != NSNotFound)
	{
	  [completeQuery appendString: @" AND "];
	}
      else
	{
	  [completeQuery appendString: @" WHERE "];
	}
      
      if (!batchable)
	{
	  if (!multiKey)
	    {
              NSString *escapedKeyVal;

              /* we need to escape ' or it conflicts with SOQL string delimiters */
              escapedKeyVal = [currKeyString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

	      [completeQuery appendString: identifier];
	      [completeQuery appendString: @" = '"];
	      [completeQuery appendString: escapedKeyVal];
	      [completeQuery appendString: @"'"];
	    }
	  else
	    {
	      NSUInteger k;

	      [completeQuery appendString: @"( "];
	      for (k = 0; k < [currKeyArray count]; k++)
		{
                  NSString *escapedKeyVal;

                  /* we need to escape ' or it conflicts with SOQL string delimiters */
                  escapedKeyVal = [[currKeyArray objectAtIndex: k] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

		  if (k > 0)
		    [completeQuery appendString: @" AND "];
		  [completeQuery appendString: [identifiers objectAtIndex: k]];
		  [completeQuery appendString: @" = '"];
		  [completeQuery appendString: escapedKeyVal];
		  [completeQuery appendString: @"'"];
		}
	      [completeQuery appendString: @" )"];
	    }

          /* append options (GROUP BY, ORDER BY, LIMIT) to clause if present */
          if (optionsLocation != NSNotFound)
            {
              [completeQuery appendString: @" "];
              [completeQuery appendString:queryOptionsPart];
            }
	  i++;
          b = 1;
	}
      else
	{
	  if (!multiKey)
	    {
	      [completeQuery appendString: identifier];
	      b = 0;
	      [completeQuery appendString: @" in ("];
	      /* we always stay inside the maximum soql query size and if we have a batch limit we cap on that */
	      while (((i < [fromArray count]) && ([completeQuery length] < [self maxSOQLLength]-20)) && (autoBatch || (b < batchSize)))
		{
                  NSString *escapedKeyVal;

                  /* we need to escape ' or it conflicts with SOQL string delimiters */
                  escapedKeyVal = [[fromArray objectAtIndex: i] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

		  [completeQuery appendString: @"'"];
		  [completeQuery appendString: escapedKeyVal];
		  [completeQuery appendString: @"',"];
		  i++;
		  b++;
		}
	      if (b > 0)
		[completeQuery deleteCharactersInRange: NSMakeRange([completeQuery length]-1, 1)];
	      [completeQuery appendString: @")"];
	    }
	  else
	    {
	      b = 0;
	      [completeQuery appendString: @" ("];
	      /* we always stay inside the maximum soql query size and if we have a batch limit we cap on that */
	      while (((i < [fromArray count]) && ([completeQuery length] < [self maxSOQLLength]-20)) && (autoBatch || (b < batchSize)))
		{
		  NSUInteger k;

		  [completeQuery appendString: @"( "];
		  for (k = 0; k < [currKeyArray count]; k++)
		    {
                      NSString *escapedKeyVal;

                      /* we need to escape ' or it conflicts with SOQL string delimiters */
                      escapedKeyVal = [[[fromArray objectAtIndex: i] objectAtIndex: k] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

		      if (k > 0)
			[completeQuery appendString: @" AND "];
		      [completeQuery appendString: [identifiers objectAtIndex: k]];
		      [completeQuery appendString: @" = '"];
		      [completeQuery appendString: escapedKeyVal];
		      [completeQuery appendString: @"'"];
		    }
		  [completeQuery appendString: @" ) OR "];

		  i++;
		  b++;
		}
	      if (b > 0)
		[completeQuery deleteCharactersInRange: NSMakeRange([completeQuery length]-3, 3)];
	      [completeQuery appendString: @")"];
	    }
	}
      [logger log: LogDebug: @"[DBSoap queryIdentify] query: %@\n", completeQuery];

      /* since we might get back more records for each object to identify, we need to use query more */
      resArray = [self _queryFull:completeQuery queryAll:all progressMonitor:nil];

      if (resArray && [resArray count])
        {
          [outArray addObjectsFromArray:resArray];
        }
      else
        {
          [logger log: LogInformative: @"[DBSoap queryIdentify] no results in batch\n"];
        }
      [completeQuery release];

      [p incrementCurrentValue: b];
    }
}


@end
