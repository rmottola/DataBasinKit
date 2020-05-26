/*
   Project: DataBasinKit

  Copyright (C) 2009-2018 Free Software Foundation

   Author: multix

   Created: 2017-11-10 10:54:00 +0100 by multix

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


@implementation DBSoap (Updating)

- (NSMutableArray *)_update :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  GWSService            *service;
  NSMutableDictionary   *headerDict;
  NSDictionary          *resultDict;
  NSMutableDictionary   *assignmentRuleHeaderDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSEnumerator          *enumerator;
  NSArray               *fieldNames;
  unsigned              fieldCount;
  DBSObject             *sObject;
  unsigned              batchCounter;
  NSUInteger            totalCounter;
  NSMutableArray        *queryObjectsArray;
  NSMutableArray        *resultArray;

  if ([objects count] == 0)
    return nil;

  [p setMaximumValue: [objects count]];
  
  /* prepare the header */
  headerDict = [[NSMutableDictionary dictionaryWithCapacity: 2] retain];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];

  /* session header */
  sessionHeaderDict = [[NSMutableDictionary dictionaryWithCapacity: 2] retain];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];

  /* assignmentRuleHeader - set Default assignment rule */
  if (runAssignmentRules)
    {
      assignmentRuleHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
      [assignmentRuleHeaderDict setObject: @"true" forKey: @"useDefaultRule"];
      [assignmentRuleHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
      [headerDict setObject: assignmentRuleHeaderDict forKey: @"AssignmentRuleHeader"];
    }

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  [logger log: LogDebug: @"[DBSoap update] update objects array size: %lu\n", (unsigned long)[objects count]];
  
  [p setCurrentDescription:@"Updating"];
  
  enumerator = [objects objectEnumerator];
  batchCounter = 0;
  totalCounter = 0;
  queryObjectsArray = [[NSMutableArray arrayWithCapacity: upBatchSize] retain];
  resultArray = [[NSMutableArray arrayWithCapacity:[objects count]] retain];
  while ((sObject = [enumerator nextObject])  && ![p shouldStop])
    {
      NSUInteger           i;
      NSMutableDictionary *sObj;
      NSMutableDictionary *sObjType;
      NSMutableArray      *sObjKeyOrder;
      NSDictionary        *queryObjectsDict;
      NSMutableDictionary *parmsDict;
      NSMutableDictionary *queryParmDict;
      NSDictionary        *queryResult;
      id                  result;
      NSDictionary        *queryFault;
      NSDictionary        *queryError;
      NSMutableArray      *fieldsToNullArr;

      sObj = [NSMutableDictionary dictionaryWithCapacity: 2];
      [sObj setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
      sObjKeyOrder = [NSMutableArray arrayWithCapacity: 2];

      /* each objects needs its type specifier which has its own namespace */
      sObjType = [NSMutableDictionary dictionaryWithCapacity: 2];
      [sObjType setObject: @"urn:sobject.partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
      [sObjType setObject: objectName forKey:GWSSOAPValueKey];
      [sObj setObject: sObjType forKey:@"type"];
      [sObjKeyOrder addObject:@"type"];

      /* now we separate fields into two categories:
	 - fields with empty strings are considered NULL
	 - fields with a value are considered to update */
      fieldNames = [sObject fieldNames];
      fieldCount = [fieldNames count];
      fieldsToNullArr = [[NSMutableArray alloc] init];
    
      for (i = 0; i < fieldCount; i++)
	{
	  NSString *keyName;
	  NSString *fieldValue;

	  keyName = [fieldNames objectAtIndex:i];
	  fieldValue = [sObject valueForField:keyName];
	  if ([fieldValue length])
	    {
	      [sObj setObject:fieldValue forKey:keyName];
	      [sObjKeyOrder addObject:keyName];
	    }
	  else
	    {
	      [fieldsToNullArr addObject:keyName];
	    }
	}
      [sObj setObject: sObjKeyOrder forKey: GWSOrderKey];
      [queryObjectsArray addObject: sObj];

      if ([fieldsToNullArr count])
	{
	  NSDictionary *sObjNillablesList;

	  sObjNillablesList = [NSDictionary dictionaryWithObjectsAndKeys: fieldsToNullArr, GWSSOAPValueKey, nil];      
	  [sObj setObject:sObjNillablesList forKey: @"fieldsToNull"];
	  [sObjKeyOrder addObject:@"fieldsToNull"];
	}
      [fieldsToNullArr release];
    
      //    NSLog(@"total counter = %lu of %lu", totalCounter, [objects count]);
      if (batchCounter == upBatchSize-1 || totalCounter == [objects count]-1)
	{
	  /* prepare the parameters */
	  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
	  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

	  queryObjectsDict = [NSDictionary dictionaryWithObjectsAndKeys: queryObjectsArray, GWSSOAPValueKey, nil];

	  [queryParmDict setObject: queryObjectsDict forKey: @"sObjects"];
  
	  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
	  [parmsDict setObject: queryParmDict forKey: @"update"];
	  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];

	  /* make the query */  
	  resultDict = [service invokeMethod: @"update"
				 parameters : parmsDict
				      order : nil
				    timeout : standardTimeoutSec];
	  //NSLog(@"resultDict: %@", resultDict);
	  queryError = [resultDict objectForKey:GWSErrorKey];
	  if (queryError != nil)
	    {
	      [logger log: LogStandard: @"[DBSoap update] Error:%@\n", queryError];
	      [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
              [queryObjectsArray release];
              [sessionHeaderDict release];
              [headerDict release];
              [resultArray release];
              [service release];
              return nil;
	    }
	  queryFault = [resultDict objectForKey:GWSFaultKey];
	  if (queryFault != nil)
	    {
	      NSString *faultCode;
	      NSString *faultString;
	    
	      faultCode = [queryFault objectForKey:@"faultcode"];
	      faultString = [queryFault objectForKey:@"faultstring"];
	      [logger log: LogStandard: @"[DBSoap update] fault code: %@\n", faultCode];
	      [logger log: LogStandard: @"[DBSoap update] fault String: %@\n", faultString];
	      [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
              [queryObjectsArray release];
              [sessionHeaderDict release];
              [headerDict release];
              [resultArray release];
              [service release];
              return nil;
	    }


	  queryResult = [resultDict objectForKey:GWSParametersKey];
	  result = [queryResult objectForKey:@"result"];
	  //NSLog(@"query result: %@", result);

	  if (result != nil)
	    {
	      NSArray *results;
	      NSUInteger j;

	      if (![result isKindOfClass:[NSArray class]])
		{
		  results = [NSArray arrayWithObject:result];
		}
	      else
		{
		  results = (NSArray *)result;
		}

	      for (j = 0; j < [results count]; j++)
		{
		  NSString *objId;
		  NSString *successStr;
		  BOOL success;
		  NSString *message;
		  NSString *code;
		  NSDictionary *r;
		  NSDictionary *rowDict;
                
		  r = [results objectAtIndex:j];
		  objId = [r objectForKey:@"id"];
		  successStr = [r objectForKey:@"success"];
		  success = YES;
		  if (![successStr isEqualToString:@"true"])
		    {
		      success = NO;
		      /* fetch original object */
		      //NSLog(@"totalCounter: %lu, upBatchSize: %lu, progressive: %lu look up %lu", totalCounter, upBatchSize, j, (totalCounter / upBatchSize) + j);
		      objId = [[objects objectAtIndex:((totalCounter / upBatchSize) * upBatchSize) + j] sfId];
		      if (objId == nil)
			{
			  NSLog(@"nil id for object at index: %lu", (unsigned long)((totalCounter / upBatchSize) * upBatchSize) + j);
			  objId = @"";
			}
		    }
		  code = nil;
		  message = nil;
		  if (success)
		    {
		      if (returnSuccessResults)
			{
			  rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
						    successStr, @"success",
						  objId, @"id",
						  @"", @"message",
						  @"", @"statusCode",
						  nil];
			  [resultArray addObject:rowDict];
			}
		    }
		  else
		    {
		      id errorsObj;
		      NSArray *errors;

		      errorsObj = [r objectForKey:@"errors"];
		      if (errorsObj != nil)
			{
			  NSUInteger ec;
			  NSUInteger howManyErrors;

			  howManyErrors = 1;
			  // NSLog(@"errors: %@", errorsObj);
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

	  [p incrementCurrentValue:batchCounter+1];
	  [queryObjectsArray removeAllObjects];
	  batchCounter = 0;
	}
      else /* of batch */
	{
	  batchCounter++;
	}
      totalCounter++;
    } /* while: outer global object enumerator cycle */
  [logger log: LogDebug: @"[DBSoap update] outer cycle ended %lu\n", totalCounter];

  [queryObjectsArray release];
  [sessionHeaderDict release];
  [headerDict release];
  [service release];

  return [resultArray autorelease];
}

- (NSMutableDictionary *)_getUpdated :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate
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

  NSLog(@"getting updated objects of: %@", objectType);
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
  [queryParmDict setObject: startDateStr forKey: @"startDate"];
  [queryParmDict setObject: endDateStr forKey: @"endDate"];

  parmsOrder = [NSMutableArray arrayWithCapacity: 3];
  [parmsOrder addObject:@"objectType"];
  [parmsOrder addObject:@"startDate"];
  [parmsOrder addObject:@"endDate"];
  [queryParmDict setObject: parmsOrder forKey: GWSOrderKey];
  

  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [parmsDict setObject: queryParmDict forKey: @"getUpdated"];
  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  
  /* make the query */  
  resultDict = [service invokeMethod: @"getUpdated"
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
      id updatedRecords;
      id latestDateCovered;
      NSUInteger i;
      NSMutableArray *returnRecords;

      updatedRecords = [result objectForKey:@"ids"];
      latestDateCovered = [result objectForKey:@"latestDateCovered"];

      returnDict = [[NSMutableDictionary alloc] initWithCapacity: 2];
      returnRecords = [[NSMutableArray alloc] initWithCapacity: [updatedRecords count]];

      [returnDict setObject:returnRecords forKey:@"updatedRecords"];
      [returnDict setObject:latestDateCovered forKey:@"latestDateCovered"];
      [returnRecords release];
      
      NSLog(@"updated records: %@", updatedRecords);
      NSLog(@"latest: %@", latestDateCovered);
      for (i = 0; i < [updatedRecords count]; i++)
	{
	  id record;
          NSDictionary *d;

	  record = [updatedRecords objectAtIndex:i];
          d = [[NSDictionary alloc] initWithObjectsAndKeys:record, @"Id", NULL];
	  [returnRecords addObject:d];
          [d release];
	}
    }

  return [returnDict autorelease];
}

@end
