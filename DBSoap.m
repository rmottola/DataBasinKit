/*
  Project: DataBasin

  Copyright (C) 2008-2016 Free Software Foundation

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

#import <AppKit/AppKit.h>

#import "DBSoap.h"
#import "DBSObject.h"

#import "DBProgressProtocol.h"
#import "DBLoggerProtocol.h"

#if defined(__APPLE__) && (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)

@interface NSString (AdditionsReplacement)
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
@end

@implementation NSString (AdditionsReplacement)
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement
{
  NSRange rT;
  NSString *newS;
  
  newS = [NSString stringWithString:self];
  rT = [newS rangeOfString:target];
  while (rT.location != NSNotFound)
    {
      NSString *s;
      NSRange remainingSubrange;
      s = [newS substringToIndex:rT.location];

      if (replacement)
        s = [s stringByAppendingString:replacement];
      s = [s stringByAppendingString:[newS substringFromIndex:rT.location + [target length]]];
      newS = s;
      remainingSubrange = NSMakeRange(rT.location + [replacement length],  [newS length] - (rT.location + [replacement length]) );
      rT = [newS rangeOfString:target options:0 range:remainingSubrange];
    }
  return newS;
}
@end

#endif


@implementation DBSoap

/**
   <p>Analyzes <em>query</em> and splits the select part into fields.<br>
   These fields can be used, for example, to predict the output returned by
   query and queryAll</p>
   <p>Contains additional logic to work around idiosynchrasies of salesforce.com
   with handling aggregate queryes. Complex objects are flattened to their names.<br>
   E.g. MyObject1__r.MyObject2__r.Field__c returns Field__c.
 */
+ (NSArray *)fieldsByParsingQuery:(NSString *)query
{
  NSMutableArray *fields;
  NSString *selectPart;
  NSArray *components;
  NSRange fromPosition;
  NSRange selectPosition;
  NSUInteger i;

  if (query == nil)
    return nil;

  components = nil;
  fields = nil;
  fromPosition = [query rangeOfString:@"from" options:NSCaseInsensitiveSearch];
  selectPosition = [query rangeOfString:@"select" options:NSCaseInsensitiveSearch];
  /* we assume that we always have select and from in the query */
  if (fromPosition.location != NSNotFound && selectPosition.location != NSNotFound)
    {
      BOOL hasAggregate;
      NSMutableString *cleansedSelectPart;
      NSUInteger exprProgressive; /* to enumerate Expr0, Expr1... */

      exprProgressive = 0;
      selectPart = [query substringWithRange:NSMakeRange([@"select " length], fromPosition.location - [@"select " length])];

      /* check for a nested query */
      if ([selectPart rangeOfString:@"select " options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
          NSLog(@"We have a nested query, it is not supported since we have no information of the nested object");
          [[NSException exceptionWithName:@"DBException" reason:@"Nested query not supported"  userInfo:nil] raise];
        }

      /* we replace certain characters with space */
      cleansedSelectPart = [NSMutableString stringWithString:selectPart];
      [cleansedSelectPart replaceOccurrencesOfString:@"\r" withString:@" " options:0  range:NSMakeRange(0, [cleansedSelectPart length])];
      [cleansedSelectPart replaceOccurrencesOfString:@"\n" withString:@" " options:0  range:NSMakeRange(0, [cleansedSelectPart length])];
      [cleansedSelectPart replaceOccurrencesOfString:@"\t" withString:@" " options:0  range:NSMakeRange(0, [cleansedSelectPart length])];
      
      /* now we do some white-space coalescing */
      while ([cleansedSelectPart replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, [cleansedSelectPart length])] > 0);

      /* now we trust the string enough and get the single comma-separated components */
      components = [cleansedSelectPart componentsSeparatedByString:@","];

      /* if we only have one field, we fake an array to retain the same logic */
      if ([components count] == 0)
        {
          components = [NSArray arrayWithObject:selectPart];
        }

      /* now we look for (, to check if it is an aggregate query */
      hasAggregate = NO;
      if ([cleansedSelectPart rangeOfString:@"(" options:NSCaseInsensitiveSearch].location != NSNotFound)
         hasAggregate = YES;

//      NSLog(@"Does query have aggregate? %d", hasAggregate);
      fields = [NSMutableArray arrayWithCapacity:[components count]];
      for (i = 0; i < [components count]; i++)
        {
          NSString *field;
          NSRange r;

          field = [components objectAtIndex:i];
          field = [field stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

          /* now we safely if the field has aliases */
          r = [field rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if (r.location != NSNotFound)
            { /* alias */
              NSArray *subComponents;
	      NSRange rParRange; // look for the right parenthesis

              subComponents = [field componentsSeparatedByString:@" "];
	      rParRange = [field rangeOfString:@")"];

	      if (rParRange.location != NSNotFound)
		{
		  NSString *lastComponent;
		  NSRange rightPar;

		  NSLog(@"we have an aggregate in %@", field);
		  lastComponent = [subComponents objectAtIndex:[subComponents count]-1];
		  /* now we try to understand if the last component is:
		     - an alias
		     - () of count()
		     - ) of function(id)
		  */
		  rightPar = [lastComponent rangeOfString:@")"];
		  if (rightPar.location != NSNotFound) // we have no alias
		    {
		      if([lastComponent rangeOfString:@"()"].location != NSNotFound)
			{
			  /* old style count */
			  field = @"count";
			}
		      else
			{
			  field = [NSString stringWithFormat:@"Expr%lu", (unsigned long)exprProgressive];
			  exprProgressive++;
			}
		    }
		  else
		    {
		      field = lastComponent;
		    }
		}
	      else
		{
		  NSLog(@"Error, white space but no aggregate function found");
		}
	    }
	  else
	    { /* no alias */
	      /* the field is not aliased and we know we have an aggregate query, count () separated by space was handled above
		 salesforce returns Expr0 for count(id) but count for count()
	      */
	      NSLog(@"no spaces, but we have count, the field is: %@", field);
	      if ([field caseInsensitiveCompare:@"count()"] == NSOrderedSame)
		{
		  field = @"count";
		}
	      else if ([field rangeOfString:@")"].location != NSNotFound)
		{
		  field = [NSString stringWithFormat:@"Expr%lu", (unsigned long)exprProgressive];
		  exprProgressive++;
		}
	      else if (hasAggregate)
		{
		  NSRange dotRange;
		      
		  dotRange = [field rangeOfString:@"." options:NSBackwardsSearch];
		  if (dotRange.location != NSNotFound)
		    {
		      field = [field substringWithRange:NSMakeRange(dotRange.location + 1, [field length]-dotRange.location-1)];
		    }
		}
	    }

          [fields addObject:field];
        }
    }
  return [NSArray arrayWithArray:fields];
}

/** Returns the standard URL for login into production, https. Use this as login: parameter */
+ (NSURL *)loginURLProduction
{
  return [NSURL URLWithString:@"https://www.salesforce.com/services/Soap/u/30.0"];
}

/** Returns the standard URL for login into sandbox, https. Use this as login: parameter */
+ (NSURL *)loginURLTest
{
  return [NSURL URLWithString:@"https://test.salesforce.com/services/Soap/u/30.0"];
}

/** returns a GWSerivce inited usefully for DBSoap */
+ (GWSService *)gwserviceForDBSoap
{
  GWSService    *gws;
  GWSSOAPCoder *coder;

  /* initialize the coder */
  coder = [GWSSOAPCoder new];
  
  /* salesforce WSDL specifies it to be literal */
  [coder setUseLiteral:YES];
  
  
  gws = [[GWSService alloc] init];
  
  [gws setCoder:coder];
  [coder release];
  
  /* set the SOAP action to an empty string, salesforce likes that more */
  [gws setSOAPAction:@"\"\""];
  
  
  return [gws autorelease];
}


- (id)init
{
  if ((self = [super init]))
    {
      NSUserDefaults *defaults;
      id obj;

      defaults = [NSUserDefaults standardUserDefaults];
    
      lockBusy = [[NSRecursiveLock alloc] init];
      busyCount = 0;
      
      standardTimeoutSec = 60;
      queryTimeoutSec = 180;
      
      upBatchSize = 1;
      downBatchSize = 500;
      obj = [defaults objectForKey:@"UpBatchSize"];
      if (obj)
	{
	  int size;
	  
	  size = [obj intValue];
	  if (size > 0)
	    upBatchSize = size;
	}
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

/** sets the size of the batches in which recors are inserted, updated or deleted */
- (void)setUpBatchSize:(unsigned)size
{
  upBatchSize = size;
}

/** Set the maximum suggested query size (download). Maximum effective is 2000, standard is 500. */
- (void)setDownBatchSize:(unsigned)size
{
  downBatchSize = size;
}


- (void)_login :(NSURL *)url :(NSString *)userName :(NSString *)password :(BOOL)useHttps
{
  NSUserDefaults        *defs;
  NSMutableArray        *orderArray;
  NSMutableDictionary   *parmsDict;
  NSMutableDictionary   *loginParmDict;
  NSDictionary          *resultDict;
  NSEnumerator          *enumerator;
  NSString              *key;
  NSDictionary          *loginResult;
  NSDictionary          *loginResult2;
  NSDictionary          *userInfoResult;
  NSDictionary          *queryFault;


  defs = [NSUserDefaults standardUserDefaults];
  [defs registerDefaults:
	  [NSDictionary dictionaryWithObjectsAndKeys:
		    @"80", @"Port",
		  nil]];

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  
  if (!useHttps && [[url scheme] isEqualTo:@"https"])
    {
      if (!useHttps)
        url = [[NSURL alloc] initWithScheme:@"http" host:[url host] path:[url path]];
      else
        url = [[NSURL alloc] initWithScheme:@"https" host:[url host] path:[url path]];
      [url autorelease];
    }
  [service setURL:url];
  
  //  [service setDebug:YES];

  /* prepare the parameters */
  loginParmDict = [NSMutableDictionary dictionaryWithCapacity: 3];
  [loginParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
  [loginParmDict setObject: userName forKey: @"username"];
  [loginParmDict setObject: password forKey: @"password"];

  orderArray = [NSMutableArray arrayWithCapacity: 2];
  [orderArray addObject: @"username"];
  [orderArray addObject: @"password"];
  [loginParmDict setObject: orderArray forKey: GWSOrderKey];
  
  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [parmsDict setObject: loginParmDict forKey: @"login"];

  
  /* invoke the login */  
  resultDict = [service invokeMethod: @"login"
                parameters : parmsDict
		order : nil
		timeout : standardTimeoutSec];

  [logger log: LogDebug: @"[DBSoap Login]:resultDict is %d big\n", [resultDict count]];
  
  queryFault = [resultDict objectForKey:@"GWSCoderFault"];
  if (queryFault != nil)
  {
    NSString *faultCode;
    NSString *faultString;
    
    
    faultCode = [queryFault objectForKey:@"faultcode"];
    faultString = [queryFault objectForKey:@"faultstring"];
    [logger log: LogStandard: @"[DBSoap Login]: fault code: %@\n", faultCode];
    [logger log: LogStandard: @"[DBSoap Login]: fault String: %@\n", faultString];
    [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
  }
  
  loginResult = [resultDict objectForKey:@"GWSCoderParameters"];
  [logger log: LogDebug: @"[DBSoap Login]: coder parameters is %@\n", loginResult];
  
  enumerator = [loginResult keyEnumerator];
  while ((key = [enumerator nextObject]))
  {
    [logger log: LogDebug: @"[DBSoap Login]:%@ - %@\n", key, [loginResult objectForKey:key]]; 
  }
  
 
  loginResult2 = [loginResult objectForKey:@"result"];
  [logger log: LogDebug: @"[DBSoap Login]: %@\n", loginResult2];
  
  enumerator = [loginResult2 keyEnumerator];
  while ((key = [enumerator nextObject]))
  {
    [logger log: LogDebug: @"[DBSoap Login]:%@ - %@\n", key, [loginResult2 objectForKey:key]]; 
  }
    
  [sessionId release];
  sessionId = [loginResult2 objectForKey:@"sessionId"];
  serverUrl = [loginResult2 objectForKey:@"serverUrl"];
  
  passwordExpired = NO;
  if ([[loginResult2 objectForKey:@"serverUrl"] isEqualToString:@"true"])
      passwordExpired = YES;
  
  userInfoResult = [loginResult2 objectForKey:@"userInfo"];
  userInfo = [[NSMutableDictionary dictionaryWithCapacity:5] retain];
  [userInfo setValue:[userInfoResult objectForKey:@"organizationId"] forKey:@"organizationId"];
  [userInfo setValue:[userInfoResult objectForKey:@"organizationName"] forKey:@"organizationName"];
  [userInfo setValue:[userInfoResult objectForKey:@"profileId"] forKey:@"profileId"];
  [userInfo setValue:[userInfoResult objectForKey:@"roleId"] forKey:@"roleId"];
  [userInfo setValue:[userInfoResult objectForKey:@"userId"] forKey:@"userId"];
  [userInfo setValue:[userInfoResult objectForKey:@"userEmail"] forKey:@"userEmail"];
  [userInfo setValue:[userInfoResult objectForKey:@"userFullName"] forKey:@"userFullName"];
  [userInfo setValue:[userInfoResult objectForKey:@"userName"] forKey:@"userName"];
  

  /* since Salesforce seems to be stubborn and returns an https connection
     even if we initiate a non-secure one, we force it to http */
  if ([[serverUrl substringToIndex:5] isEqualToString:@"https"])
  {
    [logger log: LogInformative: @"[DBSoap Login]: preferences set to https....\n"];
    if (!useHttps)
      serverUrl = [@"http" stringByAppendingString:[serverUrl substringFromIndex:5]];
  }
  
  if (sessionId == nil)
  {
    [[NSException exceptionWithName:@"DBException" reason:@"No Session information returned." userInfo:nil] raise];
  }
  else
  {
    [logger log: LogStandard: @"[DBSoap Login]: sessionId: %@\n", sessionId];
    [logger log: LogStandard: @"[DBSoap Login]: serverUrl: %@\n", serverUrl];
  }
  
  [service setURL:serverUrl];

  [sessionId retain];
}



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
  NSDictionary          *record;
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
  coderError = [resultDict objectForKey:@"GWSCoderError"];
  if (coderError != nil)
    {
      [logger log: LogStandard :@"[DBSoap query] error: %@\n", coderError];
      [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
    }
  queryFault = [resultDict objectForKey:@"GWSCoderFault"];
  if (queryFault != nil)
    {
      NSDictionary *faultDetail;
      NSString *faultName;
    
      faultDetail = [queryFault objectForKey:@"detail"];
      faultName = [[faultDetail objectForKey:@"GWSCoderOrder"] objectAtIndex: 0];
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
  
  queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
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
  
  if (sizeStr != nil)
    {
      NSUInteger    i;
      NSUInteger    j;
      NSUInteger    batchSize;
      NSMutableArray *keys;
      NSScanner *scan;
      long long ll;
      BOOL typePresent;

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
          record = [records objectAtIndex:0];
          batchSize = [records count];
        }
      else
        {
          record = nil;
          batchSize = 0;
        }
           
      
      [logger log: LogInformative :@"[DBSoap query] records size is: %d\n", batchSize];
      /* let's get the fields from the keys of the first record */
      keys = [NSMutableArray arrayWithArray:[record allKeys]];
      [keys removeObject:@"GWSCoderOrder"];
      
      /* remove some fields which get added automatically by salesforce even if not asked for */
      typePresent = [keys containsObject:@"type"];
      if (typePresent)
        [keys removeObject:@"type"];
      
      /* remove Id only if it is null, else an array of two populated Id is returned by SF */
      if (![[record objectForKey:@"Id"] isKindOfClass: [NSArray class]])
        [keys removeObject:@"Id"];
      
      
      /* Count() is not like to aggregate count(Id) and returns no AggregateResult
	 but returns just a size count without an actual records array.
	 Thus we fake one single object as AggregateResult. */
      if (batchSize == 0 && done && isCountQuery)
	{
	  DBSObject *sObj;
        
          sObj = [[DBSObject alloc] init];
	  [sObj setValue: [NSNumber numberWithUnsignedLong:size] forField: @"count"];
	  [objects addObject:sObj];
	  [sObj release];
	}

      /* now cycle all the records and read out the fields */
      for (i = 0; i < batchSize; i++)
        {
          DBSObject *sObj;
        
          sObj = [[DBSObject alloc] init];
          record = [records objectAtIndex:i];
	  [logger log: LogDebug: @"[DBSoap query] record :%@\n", record];
          for (j = 0; j < [keys count]; j++)
            {
              id       obj;
              id       value;
              NSString *key;
            
              key = [keys objectAtIndex:j];
              obj = [record objectForKey: key];
              if ([key isEqualToString:@"Id"])
                value = [(NSArray *)obj objectAtIndex: 0];
              else
                value = obj;
              [sObj setValue: value forField: key];
            }

          /* we removed type, but if it is present, set it as a property */
          if (typePresent) 
            {
              NSDictionary *propDict;

              propDict = [NSDictionary dictionaryWithObject:[record objectForKey: @"type"] forKey:@"type"];
              [sObj setObjectProperties: propDict];
            }
          [objects addObject:sObj];
          [sObj release];
        }
    }
  if (!done)
    {
      queryLocator = [result objectForKey:@"queryLocator"];
      [logger log: LogDebug: @"[DBSoap query] should do query more, queryLocator: %@\n", queryLocator];
    }
  
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
  NSDictionary          *record;
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
  queryFault = [resultDict objectForKey:@"GWSCoderFault"];
  if (queryFault != nil)
    {
      NSDictionary *fault;
      NSDictionary *faultDetail;

      faultDetail = [queryFault objectForKey:@"detail"];
      fault = [faultDetail objectForKey:@"fault"];
      NSLog(@"fault: %@", fault);
      NSLog(@"exception code: %@", [fault objectForKey:@"exceptionCode"]);
      NSLog(@"exception code: %@", [fault objectForKey:@"exceptionMessage"]);
    }

  queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
  result = [queryResult objectForKey:@"result"];

  doneStr = [result objectForKey:@"done"];
  records = [result objectForKey:@"records"];

  if (doneStr != nil)
    {
      NSLog(@"query more done: %@", doneStr);
      done = NO;
      if ([doneStr isEqualToString:@"true"])
        done = YES;
      else if ([doneStr isEqualToString:@"false"])
        done = NO;
      else
        NSLog(@"Done, unexpected value: %@", doneStr);
    }
  else
    {
      NSLog(@"error, doneStr is nil: unexpected");
      return nil;
    }

  // Size returned in queryMore refers to the original size of the query
  // not to the current batch
  // So we can just check against the actually returned records
  if (records != nil)
    {
      NSUInteger     i;
      NSUInteger     j;
      NSUInteger     batchSize;
      NSMutableArray *keys;
      BOOL typePresent;
      
      /* if we have only one element, put it in an array */
      if (![records isKindOfClass:[NSArray class]])
        {
          NSLog(@"query more -> only one element");
          records = [NSArray arrayWithObject:records];
        }
      record = [records objectAtIndex:0];
      batchSize = [records count];        
      
      NSLog(@"records size is: %lu", (unsigned long)batchSize);
      
      /* let's get the fields from the keys of the first record */
      keys = [NSMutableArray arrayWithArray:[record allKeys]];
      [keys removeObject:@"GWSCoderOrder"];

      /* remove some fields which get added automatically by salesforce even if not asked for */
      typePresent = [keys containsObject:@"type"];
      if (typePresent)
        [keys removeObject:@"type"];
      
      /* remove Id only if it is null, else an array of two populated Id is returned by SF */
      if (![[record objectForKey:@"Id"] isKindOfClass: [NSArray class]])
          [keys removeObject:@"Id"];

      //NSLog(@"keys: %@", keys);
      
      /* now cycle all the records and read out the fields */
      for (i = 0; i < batchSize; i++)
        {
          DBSObject *sObj;
	  
          sObj = [[DBSObject alloc] init];
          record = [records objectAtIndex:i];
 
          for (j = 0; j < [keys count]; j++)
            {
              id       obj;
              id       value;
              NSString *key;
              
              key = [keys objectAtIndex:j];
              obj = [record objectForKey: key];
              if ([key isEqualToString:@"Id"])
                  value = [(NSArray *)obj objectAtIndex: 0];
              else
                  value = obj;
              [sObj setValue: value forField: key];
            }

          /* we removed type, but if it is present, set it as a property */
          if (typePresent) 
            {
              NSDictionary *propDict;
              
              propDict = [NSDictionary dictionaryWithObject:[record objectForKey: @"type"] forKey:@"type"];
              [sObj setObjectProperties: propDict];
            }

          [objects addObject:sObj];
          [sObj release];
        }
    }
  if (!done)
    {
      queryLocator = [result objectForKey:@"queryLocator"];
      [logger log: LogInformative: @"[DBSoap queryMore] should do query more, queryLocator: %@\n", queryLocator];
    }

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
  unsigned i;
  unsigned j;
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
	      unsigned k;

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
	      while (((i < [fromArray count]) && ([completeQuery length] < MAX_SOQL_SIZE-20)) && (autoBatch || (b < batchSize)))
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
	      while (((i < [fromArray count]) && ([completeQuery length] < MAX_SOQL_SIZE-20)) && (autoBatch || (b < batchSize)))
		{
		  unsigned k;

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
          for (j = 0; j < [resArray count]; j++)
            [outArray addObject: [resArray objectAtIndex: j]];
        }
      else
        {
          [logger log: LogInformative: @"[DBSoap queryIdentify] no results in batch\n"];
        }
      [completeQuery release];

      [p incrementCurrentValue: b];
    }
}



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
  totalCounter = 1;
  queryObjectsArray = [[NSMutableArray arrayWithCapacity: upBatchSize] retain];
  resultArray = [[NSMutableArray arrayWithCapacity:1] retain];

  while ((sObject = [enumerator nextObject])  && ![p shouldStop])
  {
    unsigned            i;
    NSMutableDictionary *sObj;
    NSMutableDictionary *sObjType;
    NSMutableArray      *sObjKeyOrder;
    NSMutableDictionary *queryObjectsDict;
    NSMutableDictionary *parmsDict;
    NSMutableDictionary *queryParmDict;
    NSDictionary        *result;
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

    if (batchCounter == upBatchSize-1 || totalCounter == [objects count])
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
  
        queryError = [resultDict objectForKey:@"GWSCoderError"];
        if (queryError != nil)
          {
            [logger log: LogStandard: @"[DBSoap create] Error:%@\n", queryError];
            [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
          }
	queryFault = [resultDict objectForKey:@"GWSCoderFault"];
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

	queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
	result = [queryResult objectForKey:@"result"];
	[logger log: LogDebug: @"[DBSoap create] result: %@\n", result];
 
        if (result != nil)
          {
            NSArray *results;
            NSUInteger i;

            if (![result isKindOfClass:[NSArray class]])
              {
                NSLog(@"Single result. Repackaging into array");
                results = [NSArray arrayWithObject:result];
              }
            else
              {
                results = (NSArray *)result;
              }

            for (i = 0; i < [results count]; i++)
              {
                NSString *objId;
                NSString *successStr;
                BOOL success;
                NSString *message;
                NSString *code;
                NSDictionary *r;
                NSDictionary *errors;
                NSDictionary *rowDict;

                r = [results objectAtIndex:i];
                objId = [r objectForKey:@"id"];
                successStr = [r objectForKey:@"success"];
                success = NO;
                if ([successStr isEqualToString:@"true"])
                  success = YES;
                code = nil;
                message = nil;
                errors = [r objectForKey:@"errors"];
                if (errors != nil)
                  {
                    message = [errors objectForKey:@"message"];
                    code = [errors objectForKey:@"statusCode"];
                  }
//                NSLog(@"result: %@ -> %d, %@: %@ (%@)", objId, success, code, message, r);
                if (success)
                  {
                    rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                              successStr, @"success",
                                            objId, @"id",
                                            @"", @"message",
                                            @"", @"statusCode",
                                            nil];
                  }
                else
                  {
                    rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                              successStr, @"success",
                                            objId, @"id",
                                            message, @"message",
                                            code, @"statusCode",
                                            nil];
                  }
                [resultArray addObject:rowDict];
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




- (NSMutableArray *)_update :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSDictionary          *resultDict;
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
  sessionHeaderDict = [[NSMutableDictionary dictionaryWithCapacity: 2] retain];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [[NSMutableDictionary dictionaryWithCapacity: 2] retain];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];
  
  [logger log: LogDebug: @"[DBSoap update] update objects array size: %lu\n", (unsigned long)[objects count]];
  
  [p setCurrentDescription:@"Updating"];
  
  enumerator = [objects objectEnumerator];
  batchCounter = 0;
  totalCounter = 1;
  queryObjectsArray = [[NSMutableArray arrayWithCapacity: upBatchSize] retain];
  resultArray = [[NSMutableArray arrayWithCapacity:1] retain];
  while ((sObject = [enumerator nextObject])  && ![p shouldStop])
  {
    unsigned int i;
    NSMutableDictionary *sObj;
    NSMutableDictionary *sObjType;
    NSMutableArray      *sObjKeyOrder;
    NSMutableDictionary *queryObjectsDict;
    NSMutableDictionary *parmsDict;
    NSMutableDictionary *queryParmDict;
    NSDictionary        *queryResult;
    NSDictionary        *result;
    NSDictionary        *queryFault;
    NSDictionary        *queryError;

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
//    NSLog(@"total counter = %lu of %lu", totalCounter, [objects count]);
    if (batchCounter == upBatchSize-1 || totalCounter == [objects count])
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
        NSLog(@"resultDict: %@", resultDict);
        queryError = [resultDict objectForKey:@"GWSCoderError"];
        if (queryError != nil)
          {
            [logger log: LogStandard: @"[DBSoap update] Error:%@\n", queryError];
            [[NSException exceptionWithName:@"DBException" reason:@"Coder Error, check log" userInfo:nil] raise];
          }
	queryFault = [resultDict objectForKey:@"GWSCoderFault"];
	if (queryFault != nil)
	  {
	    NSString *faultCode;
	    NSString *faultString;
	    
	    faultCode = [queryFault objectForKey:@"faultcode"];
	    faultString = [queryFault objectForKey:@"faultstring"];
	    [logger log: LogStandard: @"[DBSoap update] fault code: %@\n", faultCode];
	    [logger log: LogStandard: @"[DBSoap update] fault String: %@\n", faultString];
	    [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
	  }


	queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
	result = [queryResult objectForKey:@"result"];
	//NSLog(@"query result: %@", result);

	if (result != nil)
	  {
            NSArray *results;
            NSUInteger i;

            if (![result isKindOfClass:[NSArray class]])
              {
                results = [NSArray arrayWithObject:result];
              }
            else
              {
                results = (NSArray *)result;
              }

            for (i = 0; i < [results count]; i++)
              {
                NSString *objId;
                NSString *successStr;
                BOOL success;
                NSString *message;
                NSString *code;
                NSDictionary *r;
                NSDictionary *errors;
                NSDictionary *rowDict;
                
                r = [results objectAtIndex:i];
                objId = [r objectForKey:@"id"];
                successStr = [r objectForKey:@"success"];
                success = NO;
                if ([successStr isEqualToString:@"true"])
                  success = YES;
                code = nil;
                message = nil;
                errors = [r objectForKey:@"errors"];
                if (errors != nil)
                  {
                    message = [errors objectForKey:@"message"];
                    code = [errors objectForKey:@"statusCode"];
                  }
                //NSLog(@"result: %@ -> %d, %@: %@ (%@)", objId, success, code, message, r);
		if (success)
		  {
		    rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
					      successStr, @"success",
					    objId, @"id",
					    @"", @"message",
					    @"", @"statusCode",
					    nil];
		  }
		else
		  {
		    rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
					      successStr, @"success",
					    objId, @"id",
					    message, @"message",
					    code, @"statusCode",
					    nil];
		  }
		[resultArray addObject:rowDict];
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

  return [resultArray autorelease];
}





- (NSArray *)_describeGlobal
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableDictionary   *parmsDict;
  NSMutableDictionary   *queryParmDict;
  NSDictionary          *resultDict;
  NSDictionary          *queryResult;
  NSDictionary          *result;
  NSDictionary          *queryFault;
  NSArray               *sobjects;
  NSMutableArray        *objectList;
  unsigned              i;

  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];
  
  /* prepare the parameters */
  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];
  
  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [parmsDict setObject: queryParmDict forKey: @"describeGlobal"];
  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];

  
  /* make the query */  
  resultDict = [service invokeMethod: @"describeGlobal"
                parameters : parmsDict
		order : nil
		timeout : standardTimeoutSec];


  [logger log: LogDebug: @"[DBSoap describeGlobal] Describe Global dict is %lu big\n", [resultDict count]];
  
  queryFault = [resultDict objectForKey:@"GWSCoderFault"];
  if (queryFault != nil)
    {
      NSDictionary *fault;
      NSDictionary *faultDetail;

      faultDetail = [queryFault objectForKey:@"detail"];
      fault = [faultDetail objectForKey:@"fault"];
      NSLog(@"fault: %@", fault);
      [logger log: LogStandard :@"[DBSoap describeGlobal] exception code: %@\n", [fault objectForKey:@"exceptionCode"]];
      [logger log: LogStandard :@"[DBSoap describeGlobal] exception message: %@\n", [fault objectForKey:@"exceptionMessage"]];
      [[NSException exceptionWithName:@"DBException" reason:[fault objectForKey:@"exceptionMessage"] userInfo:nil] raise];
    }

  queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
  result = [queryResult objectForKey:@"result"];
//  NSLog(@"result: %@", result);

  objectList = [NSMutableArray arrayWithCapacity:1];
  sobjects = [result objectForKey:@"sobjects"];

  for (i = 0; i < [sobjects count]; i++)
    {
      NSMutableDictionary *sObj;
      NSArray *propertiesArray;
      NSMutableDictionary *propertiesDict;
      DBSObject *dbObj;
      unsigned j;
    
      sObj = [sobjects objectAtIndex: i];
      propertiesArray = [sObj objectForKey: @"GWSCoderOrder"];
      propertiesDict = [NSMutableDictionary dictionaryWithCapacity: [propertiesArray count]];
      for (j = 0; j < [propertiesArray count]; j++)
	{
	  NSString *key;
          NSString *value;
	  
	  key = [propertiesArray objectAtIndex:j];
          value = [sObj objectForKey: key];
          
          /* we skip certain values */
          if ([key isEqualToString:@"keyPrefix"] && [value isEqualToString:@""])
            value = nil;
          if (value)
	    [propertiesDict setObject:value  forKey: key];
	}
      dbObj = [[DBSObject alloc] init];
      [dbObj setObjectProperties: propertiesDict];
      [objectList addObject: dbObj];
      [dbObj release];
    }

  return [NSArray arrayWithArray: objectList];
}



/* returns the currently stored list of object names
   if the list is nil, a describe global will be run to obtain it */
- (NSArray *)sObjects
{
  if (sObjectList == nil)
    sObjectList = [[self describeGlobal] retain];

  return sObjectList;
}

/* returns the currently stored list of object names
   if the list is nil, a describe global will be run to obtain it */
- (NSArray *)sObjectNames
{
  if (sObjectNamesList == nil)
    {
      unsigned i;

      if (sObjectList == nil)
	sObjectList = [[self describeGlobal] retain];

      sObjectNamesList = [[NSMutableArray arrayWithCapacity:1] retain];
      for (i = 0; i < [sObjectList count]; i++)
	[sObjectNamesList addObject: [[sObjectList objectAtIndex: i] name]];
    }
  
  return sObjectNamesList;
}

/** Force an udpate to the currently stored object  list */
- (void)_updateObjects
{
  unsigned i;
  
  [sObjectList release];
  sObjectList = [[self _describeGlobal] retain];

  [sObjectNamesList release];
  sObjectNamesList = [[NSMutableArray arrayWithCapacity:1] retain];
  for (i = 0; i < [sObjectList count]; i++)
    [sObjectNamesList addObject: [[sObjectList objectAtIndex: i] name]];
}


- (DBSObject *)_describeSObject: (NSString *)objectType
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableDictionary   *parmsDict;
  NSMutableDictionary   *queryParmDict;
  NSDictionary          *resultDict;
  NSDictionary          *queryResult;
  NSDictionary          *result;
  NSDictionary          *queryFault;
  NSArray               *records;
  NSArray               *recordTypeObjs;
  NSDictionary          *record;
  unsigned              i;
  NSMutableArray        *keys;
  DBSObject             *object;
  NSMutableDictionary   *propDict;
  NSMutableArray        *rtArray;
  NSMutableArray        *rtArray2;
  NSMutableString       *queryString;

  /* prepare the header */
  sessionHeaderDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [sessionHeaderDict setObject: sessionId forKey: @"sessionId"];
  [sessionHeaderDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  headerDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [headerDict setObject: sessionHeaderDict forKey: @"SessionHeader"];
  [headerDict setObject: GWSSOAPUseLiteral forKey: GWSSOAPUseKey];
  
  /* prepare the parameters */
  queryParmDict = [NSMutableDictionary dictionaryWithCapacity: 2];
  [queryParmDict setObject: @"urn:partner.soap.sforce.com" forKey: GWSSOAPNamespaceURIKey];

  [queryParmDict setObject: objectType forKey: @"sObjectType"];

  
  parmsDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [parmsDict setObject: queryParmDict forKey: @"describeSObject"];
  [parmsDict setObject: headerDict forKey:GWSSOAPMessageHeadersKey];
  
  /* make the query */  
  resultDict = [service invokeMethod: @"describeSObject"
                parameters : parmsDict
		order : nil
		timeout : standardTimeoutSec];
  
  queryFault = [resultDict objectForKey:@"GWSCoderFault"];
  if (queryFault != nil)
    {
      NSDictionary *fault;
      NSDictionary *faultDetail;

      faultDetail = [queryFault objectForKey:@"detail"];
      fault = [faultDetail objectForKey:@"fault"];
      NSLog(@"fault: %@", fault);
      [logger log: LogStandard :@"[DBSoap describeSObject] exception code: %@\n", [fault objectForKey:@"exceptionCode"]];
      [logger log: LogStandard :@"[DBSoap describeSObject] exception message: %@\n", [fault objectForKey:@"exceptionMessage"]];
      [[NSException exceptionWithName:@"DBException" reason:[fault objectForKey:@"exceptionMessage"] userInfo:nil] raise];
      return nil;
    }

  queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
  result = [queryResult objectForKey:@"result"];

  object = [[DBSObject alloc] init];

  /* Extract Object Properties */
  propDict = [NSMutableDictionary dictionaryWithCapacity: 1];
  [propDict setValue:[result objectForKey:@"name"] forKey: @"name"];
  [propDict setValue:[result objectForKey:@"label"] forKey: @"label"];
  [propDict setValue:[result objectForKey:@"keyPrefix"] forKey: @"keyPrefix"];
  [object setObjectProperties: propDict];


  /* Extract Fields */
  records = [result objectForKey:@"fields"];

  /* if we have only one element, put it in an array */
  if ([records count] == 1)
    records = [NSArray arrayWithObject:records];

  record = [records objectAtIndex:0]; 

  keys = [NSMutableArray arrayWithArray:[record allKeys]];
  [keys removeObject:@"GWSCoderOrder"];


  for (i = 0; i < [records count]; i++)
    {
      NSMutableDictionary *props;
      NSString *fieldName;
      
      record = [records objectAtIndex:i];
      props = [NSMutableDictionary dictionaryWithDictionary: record];
      [props removeObjectForKey:@"GWSCoderOrder"];
      fieldName = [props objectForKey: @"name"];
      [object setProperties:[NSDictionary dictionaryWithDictionary: props] forField: fieldName];
    }

  /* Extract Record Types */
  recordTypeObjs = [result objectForKey:@"recordTypeInfos"];
 
  /* some objects don't have record-types at all, for others get additional information from RecordType */
  if (recordTypeObjs)
    {
      [recordTypeObjs retain]; // we retain, since executing another query would otherwise clean the result

      /* query record-type developer names with a subquery to RecordTypes */
      queryString = [[NSMutableString alloc] init];
      [queryString appendString:@"select Name, DeveloperName, Id from RecordType where SObjectType='"];
      [queryString appendString: objectType];
      [queryString appendString: @"'"];
      NS_DURING
        rtArray2 = [self _queryFull:queryString queryAll:NO progressMonitor:nil];
      NS_HANDLER
        NSLog(@"Exception during record-type sub-query, %@", queryString);
      rtArray2 = nil;
      NS_ENDHANDLER
        [queryString release];

      /* if we have only one element, put it in an array */
      if (![recordTypeObjs isKindOfClass:[NSArray class]])
        {
          [recordTypeObjs autorelease];
          recordTypeObjs = [NSArray arrayWithObject:recordTypeObjs];
          [recordTypeObjs retain];
        }

      rtArray = [NSMutableArray arrayWithCapacity: [recordTypeObjs count]];
      for (i = 0; i < [recordTypeObjs count]; i++)
        {
          NSMutableDictionary *mDict;
          NSString *devName;

          record = [recordTypeObjs objectAtIndex:i];
          mDict = [NSMutableDictionary dictionaryWithDictionary: record];
          [mDict removeObjectForKey:@"GWSCoderOrder"];
//          NSLog(@"record-type from object: %@", mDict);
          devName = nil;
          /* we check for the master record type, for which the code is hardcoded by SF */
          if ([[mDict objectForKey:@"recordTypeId"] isEqualToString:@"012000000000000AAA"])
            {
              devName = @"Master";
            }
          else
            {
              NSUInteger j;
              NSString *rtId;

              rtId = [mDict objectForKey:@"recordTypeId"];
              for (j = 0; j < [rtArray2 count]; j++)
                {
                  DBSObject *so;

                  so = [rtArray2 objectAtIndex: j];
                  if ([[so sfId] isEqualToString:rtId])
                    {
                      devName = [so valueForField:@"DeveloperName"];
                      NSLog(@"found: %@", devName);
                    }
                }
            }
          [rtArray addObject: mDict];

          if (devName)
            [mDict setObject:devName forKey:@"DeveloperName"];
          else
            NSLog(@"DBSoap: error, developer name for RecordTypeId %@ not found", [mDict objectForKey:@"Id"]);
        }
      [recordTypeObjs release];
      NSLog(@"Record types: %@", rtArray);
      [object setRecordTypes: [NSArray arrayWithArray: rtArray]];
    }

  return [object autorelease];
}


- (NSMutableArray *)_delete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;
{
  NSMutableDictionary   *headerDict;
  NSMutableDictionary   *sessionHeaderDict;
  NSMutableArray        *resultArray;
  NSEnumerator          *enumerator;
  unsigned              batchCounter;
  NSMutableArray        *batchObjArray;
  id                    objToDelete;
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
  
  do
    {
      NSMutableDictionary   *parmsDict;
      NSMutableDictionary   *queryParmDict;
      NSDictionary          *resultDict;
      NSDictionary          *queryResult;
      NSDictionary          *result;
      NSDictionary          *queryFault;
      NSMutableArray        *queryObjectsDict;

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
      if (batchCounter == upBatchSize || !idStr)
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

	  queryFault = [resultDict objectForKey:@"GWSCoderFault"];
	  if (queryFault != nil)
	    {
	      NSString *faultCode;
	      NSString *faultString;
	      
	      faultCode = [queryFault objectForKey:@"faultcode"];
	      faultString = [queryFault objectForKey:@"faultstring"];
	      NSLog(@"fault code: %@", faultCode);
	      NSLog(@"fault String: %@", faultString);
	      [[NSException exceptionWithName:@"DBException" reason:faultString userInfo:nil] raise];
	    }
  
	  queryResult = [resultDict objectForKey:@"GWSCoderParameters"];
	  result = [queryResult objectForKey:@"result"];
          //	  NSLog(@"result: %@", result);

	  if (result != nil)
	    {
	      id resultRow;
	      NSEnumerator   *objEnu;
	      NSDictionary   *rowDict;
	      
	      /* if only one element gets returned, GWS can't interpret it as an array */
	      if (!([result isKindOfClass: [NSArray class]]))
		result = [NSArray arrayWithObject: result];
	      
	      objEnu = [result objectEnumerator];
	      while ((resultRow = [objEnu nextObject]))
		{
		  id message;
		  id success;
		  id errors;
		  id statusCode;
		  id sfId;

		  errors = [resultRow objectForKey:@"errors"];
		  message  = [errors objectForKey:@"message"];          
		  statusCode = [errors objectForKey:@"statusCode"]; 
		  success = [resultRow objectForKey:@"success"];
		  sfId = [resultRow objectForKey:@"id"];
		  
		  //		  NSLog(@"resultRow: %@", resultRow);
		  NSLog(@"errors: %@", errors);
		  NSLog(@"success: %@", success);
		  NSLog(@"message: %@", message);
		  NSLog(@"statusCode: %@", statusCode);
		  //		  NSLog(@"id: %@", sfId);
		  
		  if ([success isEqualToString:@"true"])
		    {
		      rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
						success, @"success",
					      sfId, @"id",
					      nil];            
		    }
		  else
		    {
		      rowDict = [NSDictionary dictionaryWithObjectsAndKeys:
						success, @"success",
					      message, @"message",
					      statusCode, @"statusCode",
					      nil];
		    }
		  [resultArray addObject:rowDict];
		}
	    }
          [p incrementCurrentValue:batchCounter];
	  [batchObjArray removeAllObjects];
	  batchCounter = 0;
	} /* of batch */
    }
  while (idStr  && ![p shouldStop]);

  [batchObjArray release];
  return [resultArray autorelease];
}



- (NSString *)_identifyObjectById:(NSString *)sfId
{
  NSString *devName;
  NSEnumerator *enu;
  NSString *name;
  BOOL found;
  NSString *prefixToIdentify;
  DBSObject *tempObj;

  devName = nil;
  found = NO;
  name = nil;

  if (sfId == nil)
    return nil;

  if (!([sfId length] == 15 || [sfId length] == 18))
    {
      [logger log: LogInformative :@"[DBSoap identifyObjectById] Invalid SF Id: %@\n", sfId];
      return nil;
    }

  prefixToIdentify = [sfId substringToIndex: 3];
  [logger log: LogInformative :@"[DBSoap identifyObjectById] identify: %@\n", prefixToIdentify];
  if (sObjectList == nil)
    [self _updateObjects];

  [logger log: LogDebug :@"[DBSoap identifyObjectById] in %u objects\n", [sObjectList count]];
  enu = [sObjectList objectEnumerator];
  while (!found && (tempObj = [enu nextObject]))
    {
      [logger log: LogDebug :@"[DBSoap identifyObjectById] compare to: %@\n", [tempObj keyPrefix]];
      if ([tempObj keyPrefix] && [[tempObj keyPrefix] isEqualToString: prefixToIdentify])
	{
	  name = [tempObj name];
	  found = YES;
	}
    }

  if (found)
    {
      [logger log: LogInformative :@"[DBSoap identifyObjectById] we found: %@\n", name];
      devName = [NSString stringWithString: name];
    }
  else
    [logger log: LogStandard :@"[DBSoap identifyObjectById] not found\n"];
  return devName;
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

- (NSString *) serverUrl
{
  return serverUrl;
}

- (void) setServerUrl:(NSString *)urlStr
{
  if (serverUrl != urlStr)
    {
      [serverUrl release];
      serverUrl = urlStr;
      [serverUrl retain];
    }
}

- (BOOL) passwordExpired
{
  return passwordExpired;
}

- (NSDictionary *) userInfo
{
  return userInfo;
}

- (void)setStandardTimeout:(unsigned)sec
{
  standardTimeoutSec = sec;
}

- (void)setQueryTimeout:(unsigned)sec
{
  queryTimeoutSec = sec;
}

- (unsigned)standardTimeout
{
  return standardTimeoutSec;
}

- (unsigned)queryTimeout
{
  return queryTimeoutSec;
}

- (BOOL)isBusy
{
  return busyCount > 0;
}

- (void)setService:(GWSService *)serv
{
  if (service != serv)
    {
      [service release];
      service = serv;
      [service retain];
    }
}

- (void)dealloc
{
  [lockBusy release];

  [sessionId release];
  [userInfo release];
  [service release];
  [super dealloc];
}


/* ------- public exposed API, which test for lock and invoke internal implementations */

/**<p>executes login</p>
   <p><i>url</i> specifies the URL of the endpoint</p>
   <p><i>useHttps</i> specifies if secure connecton has to be used or not. If not, http is attempted and then enforced.
   The Salesforce.com instance must be configured to accept non-secure connections.</p>
 */
- (void)login :(NSURL *)url :(NSString *)userName :(NSString *)password :(BOOL)useHttps
{
  [lockBusy lock];
  busyCount++;
  [lockBusy unlock];

  NS_DURING
    [self _login :url :userName :password :useHttps];
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
      [logger log: LogStandard :@"[DBSoap query] called but busy\n"];
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

/** <p>Execute SOQL query <i>queryString</i> and returns the resulting DBSObjects as an array.</p>
 <p>This method will query all resulting objects of the query, repeatedly querying again if necessary depending on the batch size.</p>
 <p>Returns exception</p>
 */
- (NSMutableArray *)queryFull :(NSString *)queryString queryAll:(BOOL)all progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *result;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap queryFull] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  result = nil;
  NS_DURING
    result = [self _queryFull:queryString queryAll:all progressMonitor:p];
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
  return result;
}

/**
 <p>execute a the given query on the objects given in the fromArray.<br>
 The selection clause is automatically generated to identify the object by the field passed in the array. Only if the field is an unique identifier 
 the result is a single record, else, more records are returned.<br>
 The Where clause is either automatically generated if none is present or, if Where is already present, it is appended with an AND operator</p>
 <p>the parameter <em>withBatchSize</em> selects the querying behaviour:
 <ul>
 <li>&lgt; 0:Auto-sizing of the batch, the maximum query size is formed</li>
 <li>0, 1: A single element is queried with =, making the clause Field = 'value'</li>
 <li>&gt 1: The given batch size is used in a clause like Field in ('value1', 'value2', ... )</li>
 </ul>
 <p>A LIMIT N or GROUP BY specification is supported, but only with batch of size 1</p>
 */
- (void)queryIdentify :(NSString *)queryString with: (NSArray *)identifiers queryAll:(BOOL)all fromArray:(NSArray *)fromArray toArray:(NSMutableArray *)outArray withBatchSize:(int)batchSize progressMonitor:(id<DBProgressProtocol>)p
{
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap queryIdentify] called but busy\n"];
      [lockBusy unlock];
      return;
    }
  busyCount++;
  [lockBusy unlock];
  
  NS_DURING
    [self _queryIdentify:queryString with:identifiers queryAll:all fromArray:fromArray toArray:outArray withBatchSize:batchSize progressMonitor:p];
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
}


/** <p>Execute SOQL query more and write the resulting DBSObjectes into the <i>objects</i> array
 which must be valid and allocated, continuing from the given query locator <i>locator</i>. </p>
 <p>If the query locator is returned,  a query more has to be executed.</p>
 */
- (NSString *)queryMore :(NSString *)locator toArray:(NSMutableArray *)objects
{
  NSString *queryLocator;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap queryMore] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  queryLocator = nil;
  NS_DURING
    queryLocator = [self _queryMore:locator toArray:objects];
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

/**
 insert an array of DBSObjects.<br>
 The objects in the array shall all be of the same type.
 */
- (NSMutableArray *)create :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *resultArray;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap create] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  resultArray = nil;
  NS_DURING
    resultArray = [self _create:objectName fromArray:objects progressMonitor:p];
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
  
  return resultArray;
}


/**
 <p>Update an array of DBSObjects.<br>
 The objects in the array shall all be of the same type.
 </p>
 <p>The batch size sent is determined by the upBatchSize property of the class</p>
 */
- (NSMutableArray *)update :(NSString *)objectName fromArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *resultArray;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap update] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  resultArray = nil;
  NS_DURING
    resultArray = [self _update:objectName fromArray:objects progressMonitor:p];
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
  
  return resultArray;
}


/** Delete the contents of array, which can be either strings of IDs or DBSObjects */
- (NSMutableArray *)delete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;
{
  NSMutableArray *resArray;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap delete] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  resArray = nil;
  NS_DURING
    resArray = [self _delete:array progressMonitor:p];
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
  
  return resArray;
}

/** runs a describe global to retrieve all all the objects and returns an array of DBSobjects */
- (NSArray *)describeGlobal
{
  NSArray *objects;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap describeGlobal] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  objects = nil;
  NS_DURING
    objects = [self _describeGlobal];
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
  
  return objects;
}

- (DBSObject *)describeSObject: (NSString *)objectType
{
  DBSObject *sObj;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap describeSObject] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  sObj = nil;
  NS_DURING
    sObj = [self _describeSObject:objectType];
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
  
  return sObj;
}

/** Force an udpate to the currently stored object  list */
- (void)updateObjects
{
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap updateObjects] called but busy\n"];
      [lockBusy unlock];
      return;
    }
  busyCount++;
  [lockBusy unlock];
  
  NS_DURING
    [self _updateObjects];
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
}

/** <p>Given an ID tries to matches the keyPrefix to identify which kind of Object it is.<br>
 History objects can't be identified, they don't have a keyPrefix.</p>
 <p>Returns the Developer Name of the object</p>
 */
- (NSString *)identifyObjectById:(NSString *)sfId
{
  NSString *str;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap identifyObjectById] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }  
  busyCount++;
  [lockBusy unlock];

  str = nil;
  NS_DURING
    str = [self _identifyObjectById:sfId];
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
  
  return str;
}

@end
