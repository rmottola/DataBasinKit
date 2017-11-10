/*
   Project: DataBasinKit

   Copyright (C) 2009-2017 Free Software Foundation

   Author: multix

   Created: 2017-11-10 11:17:31 +0100 by multix

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


@implementation DBSoap (Creating)

- (NSMutableArray *)_create :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSDictionary          *resultDict;
  NSEnumerator          *enumerator;
  NSDictionary          *queryResult;
  NSArray               *fieldNames;
  int                   fieldCount;
  NSMutableArray        *queryObjectsArray;
  DBSObject             *sObject;
  unsigned              batchCounter;
  NSUInteger            totalCounter;
  NSMutableArray       *resultArray;

  if ([objects count] == 0)
    return nil;

  [p setMaximumValue: [objects count]];
  
  /* prepare the header */
  sessionHeaderDict = [[NSMutableDictionary dictionaryWithCapacity: 2] retain];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [[NSMutableDictionary dictionaryWithCapacity: 2] retain];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];

  [p setCurrentDescription:@"Creating"];
    
  enumerator = [objects objectEnumerator];
  batchCounter = 0;
  totalCounter = 0;
  queryObjectsArray = [[NSMutableArray arrayWithCapacity: upBatchSize] retain];
  resultArray = [[NSMutableArray arrayWithCapacity:1] retain];

  while ((sObject = [enumerator nextObject])  && ![p shouldStop])
    {
      unsigned            i;
      NSMutableDictionary *sObj;
      NSMutableDictionary *sObjType;
      NSMutableArray      *sObjKeyOrder;
      NSDictionary *queryObjectsDict;
      NSMutableDictionary *parmsDict;
      NSMutableDictionary *queryParmDict;
      id                  result;
      NSDictionary        *queryFault;
      NSDictionary        *queryError;
   
      //NSLog(@"inner cycle: %d", batchCounter);
      sObj = [NSMutableDictionary dictionaryWithCapacity: 2];
      [sObj setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
      sObjKeyOrder = [NSMutableArray arrayWithCapacity: 2];

      /* each objects needs its type specifier which has its own namespace */
      sObjType = [NSMutableDictionary dictionaryWithCapacity: 2];
      [sObjType setObject: @"urn:sobject.partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
      [sObjType setObject: objectName forKey:GWSSOAPValueKey];
      [sObj setObject: sObjType forKey:@"type"];
      [sObjKeyOrder addObject:@"type"];

      fieldNames = [sObject fieldNames];
      fieldCount = [fieldNames count];

      for (i = 0; i < fieldCount; i++)
	{
	  NSString *keyName;

	  keyName = [fieldNames objectAtIndex:i];
	  [sObj setObject: [sObject valueForField:keyName] forKey:keyName];
	  [sObjKeyOrder addObject:keyName];
	}
      [sObj setObject: sObjKeyOrder forKey: GWSOrderKey];
      [queryObjectsArray addObject: sObj];

      if (batchCounter == upBatchSize-1 || totalCounter == [objects count]-1)
	{
	  /* prepare the parameters */
	  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
	  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
	
	  [logger log: LogDebug: @"[DBSoap create] create objects array: %@\n", objects];

	  queryObjectsDict = [NSDictionary dictionaryWithObjectsAndKeys: queryObjectsArray, GWSSOAPValueKey, nil];

	  [queryParmDict setObject: queryObjectsDict forKey: @"sObjects"];
  
	  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
	  [parmsDict setObject: queryParmDict forKey: @"create"];
	  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];

	  /* make the query */  
	  resultDict = [service invokeMethod: @"create"
				 parameters : parmsDict
				      order : nil
				    timeout : standardTimeoutSec];
  
	  queryError = [resultDict objectForKey:GWSErrorKey];
	  if (queryError != nil)
	    {
	      [logger log: LogStandard: @"[DBSoap create] Error:%@\n", queryError];
	      [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
	    }
	  queryFault = [resultDict objectForKey:GWSFaultKey];
	  if (queryFault != nil)
	    {
	      NSString *faultCode;
	      NSString *faultString;


	      faultCode = [queryFault objectForKey:@"faultcode"];
	      faultString = [queryFault objectForKey:@"faultstring"];
	      [logger log: LogStandard: @"[DBSoap create] fault code: %@\n", faultCode];
	      [logger log: LogStandard: @"[DBSoap create] fault String: %@\n", faultString];
	      [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
	    }

	  queryResult = [resultDict objectForKey:GWSParametersKey];
	  result = [queryResult objectForKey:@"result"];
	  [logger log: LogDebug: @"[DBSoap create] result: %@\n", result];
 
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
	      //NSLog(@"results : %@", results);
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
		    success = NO;
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

	  [logger log: LogDebug: @"[DBSoap create] reiniting cycle...\n"];
	  [p incrementCurrentValue: batchCounter+1];
	  [queryObjectsArray removeAllObjects];
	  batchCounter = 0;
	}
      else /* of batch */
	{
	  batchCounter++;
	}
      totalCounter++;
    }
  [logger log: LogDebug: @"[DBSoap create] Outer cycle ended\n"];
  [queryObjectsArray release];
  [sessionHeaderDict release];
  [headerDict release];

  return [resultArray autorelease];
}


@end
