/* -*- mode: objc -*-
  Project: DataBasinKit

  Copyright (C) 2009-2019 Free Software Foundation

  Author: multix

  Created: 2017-11-10 11:49:21 +0100 by multix

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

#import "DBSoap.h"
#import "DBSObject.h"

#import "DBProgressProtocol.h"
#import "DBLoggerProtocol.h"

#import "DBSFTypeWrappers.h"

@implementation DBSoap (Deleting)

- (NSMutableArray *)_delete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p
{
  GWSService            *service;
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableArray        *resultArray;
  NSEnumerator          *enumerator;
  unsigned              batchCounter;
  NSMutableArray        *batchObjArray;
  NSString              *idStr;

  if ([array count] == 0)
    return nil;

  [logger log: LogDebug :@"[DBSoap delete] deleting %u objects...\n", [array count]];
  [p setMaximumValue:[array count]];

  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];

  enumerator = [array objectEnumerator];
  batchCounter = 0;
  batchObjArray = [[NSMutableArray arrayWithCapacity: upBatchSize] retain];
  resultArray = [[NSMutableArray arrayWithCapacity:1] retain];

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  
  do
    {
      NSMutableDictionary   *parmsDict;
      NSMutableDictionary   *queryParmDict;
      NSDictionary          *resultDict;
      NSDictionary          *queryResult;
      id                    result;
      NSDictionary          *queryFault;
      NSDictionary          *queryObjectsDict;
      id                    objToDelete;

      objToDelete = [enumerator nextObject];
      if ([objToDelete isKindOfClass:[DBSObject class]])
        {
          idStr = [(DBSObject *)objToDelete sfId];
        }
      else
        idStr = objToDelete;

      if (idStr)
	{
	  [batchObjArray addObject: idStr];
	  batchCounter++;
	}
 
      /* did we fill a batch or did we reach the end? */
      if (batchCounter && (batchCounter == upBatchSize || idStr == nil))
	{
	  /* prepare the parameters */
	  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
	  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
	  
	  queryObjectsDict = [NSDictionary dictionaryWithObjectsAndKeys: batchObjArray, GWSSOAPValueKey, nil];
	  //	  NSLog(@"Inner delete cycle. Deleting %u objects", (unsigned int)[batchObjArray count]);
	  [queryParmDict setObject: queryObjectsDict forKey: @"ids"];
	  
	  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
	  [parmsDict setObject: queryParmDict forKey: @"delete"];
	  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];  
  
	  /* make the query */  
	  resultDict = [service invokeMethod: @"delete"
				 parameters : parmsDict
				      order : nil
				    timeout : standardTimeoutSec];

	  queryFault = [resultDict objectForKey:GWSFaultKey];
	  if (queryFault != nil)
	    {
	      NSString *faultCode;
	      NSString *faultString;
	      
	      faultCode = [queryFault objectForKey:@"faultcode"];
	      faultString = [queryFault objectForKey:@"faultstring"];
	      NSLog(@"fault code: %@", faultCode);
	      NSLog(@"fault String: %@", faultString);
	      [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
              [batchObjArray release];
              [resultArray release];
              [service release];
	      return nil;
	    }
  
	  queryResult = [resultDict objectForKey:GWSParametersKey];
	  result = [queryResult objectForKey:@"result"];
          // NSLog(@"result: %@", result);

	  if (result != nil)
	    {
	      id resultRow;
	      NSEnumerator   *objEnu;
              NSArray        *results;
	      
	      /* if only one element gets returned, GWS can't interpret it as an array */
	      if (!([result isKindOfClass: [NSArray class]]))
		results = [NSArray arrayWithObject: result];
	      else
                results = (NSArray *)result;
              
	      objEnu = [results objectEnumerator];
	      while ((resultRow = [objEnu nextObject]))
		{
		  NSString *successStr;
		  NSString *objId;
                  NSDictionary *rowDict;

		  successStr = [resultRow objectForKey:@"success"];
		  objId = [resultRow objectForKey:@"id"];
		  
		  // NSLog(@"resultRow: %@", resultRow);
		  if ([successStr isEqualToString:@"true"])
		    {
		      rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
						successStr, @"success",
					      objId, @"id",
					      nil];
                      [resultArray addObject:rowDict];
		    }
		  else
		    {
                      id errorsObj;
                      NSArray *errors;
                      
                      errorsObj = [resultRow objectForKey:@"errors"];
                      if (errorsObj != nil)
                        {
                          NSUInteger ec;
                          NSUInteger howManyErrors;
                          NSString *message;
                          NSString *code;
                          
                          howManyErrors = 1;
                          if (![errorsObj isKindOfClass:[NSArray class]])
                            {
                              errors = [NSArray arrayWithObject:errorsObj];
                            }
                          else
                            {
                              errors = (NSArray *)errorsObj;
                              if (returnMultipleErrors)
                                howManyErrors = [errors count];
                            }
                          for (ec = 0; ec < howManyErrors; ec++)
                            {
                              NSDictionary *error = [errors objectAtIndex:ec];
                              message = [error objectForKey:@"message"];
                              code = [error objectForKey:@"statusCode"];
                            
                              rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                        successStr, @"success",
                                                      objId, @"id",
                                                      message, @"message",
                                                      code, @"statusCode",
                                                      nil];
                              [resultArray addObject:rowDict];      
                            }
                        }
		    }
		}
	    }
          [p incrementCurrentValue:batchCounter];
	  [batchObjArray removeAllObjects];
	  batchCounter = 0;
	} /* of batch */
    }
  while (idStr  && ![p shouldStop]);

  [batchObjArray release];
  [service release];
  return [resultArray autorelease];
}

- (NSMutableArray *)_undelete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p
{
  GWSService            *service;
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableArray        *resultArray;
  NSEnumerator          *enumerator;
  unsigned              batchCounter;
  NSMutableArray        *batchObjArray;
  NSString              *idStr;

  if ([array count] == 0)
    return nil;

  [logger log: LogDebug :@"[DBSoap undelete] undeleting %u objects...\n", [array count]];
  [p setMaximumValue:[array count]];

  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];

  enumerator = [array objectEnumerator];
  batchCounter = 0;
  batchObjArray = [[NSMutableArray arrayWithCapacity: upBatchSize] retain];
  resultArray = [[NSMutableArray arrayWithCapacity:1] retain];

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  do
    {
      NSMutableDictionary   *parmsDict;
      NSMutableDictionary   *queryParmDict;
      NSDictionary          *resultDict;
      NSDictionary          *queryResult;
      id                    result;
      NSDictionary          *queryFault;
      NSDictionary          *queryObjectsDict;
      id                    objToUndelete;

      objToUndelete = [enumerator nextObject];
      if ([objToUndelete isKindOfClass:[DBSObject class]])
        {
          idStr = [(DBSObject *)objToUndelete sfId];
        }
      else
        idStr = objToUndelete;

      if (idStr)
	{
	  [batchObjArray addObject: idStr];
	  batchCounter++;
	}

      /* did we fill a batch or did we reach the end? */
      if (batchCounter && (batchCounter == upBatchSize || idStr == nil))
	{
	  /* prepare the parameters */
	  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
	  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
	  
	  queryObjectsDict = [NSDictionary dictionaryWithObjectsAndKeys: batchObjArray, GWSSOAPValueKey, nil];
	  [queryParmDict setObject: queryObjectsDict forKey: @"ids"];
	  
	  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
	  [parmsDict setObject: queryParmDict forKey: @"undelete"];
	  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];  
  
	  /* make the query */  
	  resultDict = [service invokeMethod: @"undelete"
				 parameters : parmsDict
				      order : nil
				    timeout : standardTimeoutSec];

	  queryFault = [resultDict objectForKey:GWSFaultKey];
	  if (queryFault != nil)
	    {
	      NSString *faultCode;
	      NSString *faultString;
	      
	      faultCode = [queryFault objectForKey:@"faultcode"];
	      faultString = [queryFault objectForKey:@"faultstring"];
	      NSLog(@"fault code: %@", faultCode);
	      NSLog(@"fault String: %@", faultString);
	      [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
              [batchObjArray release];
              [resultArray release];
              [service release];
	      return nil;
	    }
  
	  queryResult = [resultDict objectForKey:GWSParametersKey];
	  result = [queryResult objectForKey:@"result"];

	  if (result != nil)
	    {
	      id resultRow;
	      NSEnumerator   *objEnu;
              NSArray        *results;
	      
	      /* if only one element gets returned, GWS can't interpret it as an array */
	      if (!([result isKindOfClass: [NSArray class]]))
		results = [NSArray arrayWithObject: result];
	      else
                results = (NSArray *)result;
              
	      objEnu = [results objectEnumerator];
	      while ((resultRow = [objEnu nextObject]))
		{
		  NSString *successStr;
		  NSString *objId;
                  NSDictionary *rowDict;

		  successStr = [resultRow objectForKey:@"success"];
		  objId = [resultRow objectForKey:@"id"];
		  
		  if ([successStr isEqualToString:@"true"])
		    {
		      rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
						successStr, @"success",
					      objId, @"id",
					      nil];
                      [resultArray addObject:rowDict];
		    }
		  else
		    {
                      id errorsObj;
                      NSArray *errors;
                      
                      errorsObj = [resultRow objectForKey:@"errors"];
                      if (errorsObj != nil)
                        {
                          NSUInteger ec;
                          NSUInteger howManyErrors;
                          NSString *message;
                          NSString *code;
                          
                          howManyErrors = 1;
                          if (![errorsObj isKindOfClass:[NSArray class]])
                            {
                              errors = [NSArray arrayWithObject:errorsObj];
                            }
                          else
                            {
                              errors = (NSArray *)errorsObj;
                              if (returnMultipleErrors)
                                howManyErrors = [errors count];
                            }
                          for (ec = 0; ec < howManyErrors; ec++)
                            {
                              NSDictionary *error = [errors objectAtIndex:ec];
                              message = [error objectForKey:@"message"];
                              code = [error objectForKey:@"statusCode"];
                            
                              rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                        successStr, @"success",
                                                      objId, @"id",
                                                      message, @"message",
                                                      code, @"statusCode",
                                                      nil];
                              [resultArray addObject:rowDict];      
                            }
                        }
		    }
		}
	    }
          [p incrementCurrentValue:batchCounter];
	  [batchObjArray removeAllObjects];
	  batchCounter = 0;
	} /* of batch */
    }
  while (idStr  && ![p shouldStop]);

  [batchObjArray release];
  [service release];
  return [resultArray autorelease];
}

- (NSMutableDictionary *)_getDeleted :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate
{
  GWSService            *service;
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  
  NSMutableDictionary   *parmsDict;
  NSMutableDictionary   *queryParmDict;
  NSMutableArray        *parmsOrder;
  NSDictionary          *resultDict;
  NSDictionary          *queryResult;
  id                    result;
  NSDictionary          *queryFault;

  NSMutableDictionary   *returnDict;
  
  NSString *startDateStr;
  NSString *endDateStr;

  returnDict = nil;

  startDateStr = nil;
  if (startDate)
    {
      NSCalendarDate *cd;
      
      cd = [NSCalendarDate dateWithTimeIntervalSince1970:[startDate timeIntervalSince1970]];
      startDateStr = [cd descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S.%FZ"];
    }

  endDateStr = nil;
  if (endDate)
    {
      NSCalendarDate *cd;
      
      cd = [NSCalendarDate dateWithTimeIntervalSince1970:[endDate timeIntervalSince1970]];
      endDateStr = [cd descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S.%FZ"];
    }

  NSLog(@"getting deleted objects of: %@", objectType);
  NSLog(@"from %@ to %@", startDateStr, endDateStr);

  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];

  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 4];
  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  [queryParmDict setObject: objectType forKey: @"objectType"];

  if (startDateStr)
    [queryParmDict setObject: startDateStr forKey: @"startDate"];
  else
    [logger log: LogStandard: @"[DBSoap getDeleted] exception: empty start date\n"];

  if (endDateStr)
    [queryParmDict setObject: endDateStr forKey: @"endDate"];
  else
    [logger log: LogStandard: @"[DBSoap getDeleted] exception: empty end date\n"];

  parmsOrder = [NSMutableArray arrayWithCapacity: 3];
  [parmsOrder addObject:@"objectType"];
  [parmsOrder addObject:@"startDate"];
  [parmsOrder addObject:@"endDate"];
  [queryParmDict setObject: parmsOrder forKey: GWSOrderKey];
  

  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [parmsDict setObject: queryParmDict forKey: @"getDeleted"];
  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  /* make the query */  
  resultDict = [service invokeMethod: @"getDeleted"
			 parameters : parmsDict
			      order : nil
			    timeout : standardTimeoutSec];
  [service release];

  queryFault = [resultDict objectForKey:GWSFaultKey];
  if (queryFault != nil)
    {
      NSString *faultCode;
      NSString *faultString;
	      
      faultCode = [queryFault objectForKey:@"faultcode"];
      faultString = [queryFault objectForKey:@"faultstring"];
      NSLog(@"fault code: %@", faultCode);
      NSLog(@"fault String: %@", faultString);
      [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
      [resultDict release];
      return nil;
    }
  
  queryResult = [resultDict objectForKey:GWSParametersKey];
  result = [queryResult objectForKey:@"result"];
  NSLog(@"result: %@", result);

  if (result != nil)
    {
      id deletedRecords;
      id earliestDateAvailable;
      id latestDateCovered;
      NSUInteger i;
      NSMutableArray *returnRecords;

      deletedRecords = [result objectForKey:@"deletedRecords"];
      latestDateCovered = [result objectForKey:@"latestDateCovered"];
      earliestDateAvailable = [result objectForKey:@"earliestDateAvailable"];

      returnDict = [[NSMutableDictionary alloc] initWithCapacity: 3];
      returnRecords = [[NSMutableArray alloc] initWithCapacity: [deletedRecords count]];

      [returnDict setObject:returnRecords forKey:@"deletedRecords"];
      [returnDict setObject:latestDateCovered forKey:@"latestDateCovered"];
      [returnDict setObject:earliestDateAvailable forKey:@"earliestDateAvailable"];
      [returnRecords release];
      
      NSLog(@"deleted records: %@", deletedRecords);
      NSLog(@"latest: %@", latestDateCovered);
      NSLog(@"earliest: %@", earliestDateAvailable);
      for (i = 0; i < [deletedRecords count]; i++)
	{
	  id record;

	  record = [deletedRecords objectAtIndex:i];
	  [returnRecords addObject:record];
	  NSLog(@"%lu: %@", i, record);
	}
    }

  return [returnDict autorelease];
}

@end
