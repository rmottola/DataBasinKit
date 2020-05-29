/*
  Project: DataBasin

  Copyright (C) 2008-2020 Free Software Foundation

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

#import "DBSFTypeWrappers.h"

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

  query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
      NSRange firstParenthesisPosition;

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
      firstParenthesisPosition = [cleansedSelectPart rangeOfString:@"("];
      if (firstParenthesisPosition.location != NSNotFound && firstParenthesisPosition.location < fromPosition.location)
         hasAggregate = YES;

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
            { /* we probably have alias */
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
	      if ([field caseInsensitiveCompare:@"count()"] == NSOrderedSame)
		{
                  NSLog(@"no spaces, but we have count, the field is: %@", field);
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
  return [NSURL URLWithString:@"https://login.salesforce.com/services/Soap/u/48.0"];
}

/** Returns the standard URL for login into sandbox, https. Use this as login: parameter */
+ (NSURL *)loginURLTest
{
  return [NSURL URLWithString:@"https://test.salesforce.com/services/Soap/u/48.0"];
}

/** returns a GWService inited usefully for DBSoap */
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
      lockBusy = [[NSRecursiveLock alloc] init];
      busyCount = 0;
      
      standardTimeoutSec = 60;
      queryTimeoutSec = 180;
      
      runAssignmentRules = YES;
      upBatchSize = 1;
      downBatchSize = 500;
      maxSOQLLength = MAX_SOQL_LENGTH;

      enableFieldTypesDescribeForQuery = NO;
      returnSuccessResults = YES;
      returnMultipleErrors = YES;

      sObjectDetailsDict = [[NSMutableDictionary alloc] init];
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

- (unsigned)upBatchSize
{
  return upBatchSize;
}

/** Sets the size of the batches in which records are inserted, updated or deleted */
- (void)setUpBatchSize:(unsigned)size
{
  upBatchSize = size;
}

- (unsigned)downBatchSize
{
  return downBatchSize;
}

/** Set the maximum suggested query size (download). Maximum effective is 2000, standard is 500. */
- (void)setDownBatchSize:(unsigned)size
{
  downBatchSize = size;
}

- (unsigned)maxSOQLLength
{
  return maxSOQLLength;
}

/** Set the maximum used lenght for a SOQL statement. Maximum is defined by MAX_SOQL_LENGTH but
  if a query returns QUERY_TOO_COMPLICATED the size must be reduced. A large value is capped to MAX_SOQL_LENGTH */
- (void)setMaxSOQLLength:(unsigned)size
{
  if (size < MAX_SOQL_LENGTH)
    maxSOQLLength = size;
  else
    maxSOQLLength = MAX_SOQL_LENGTH;
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
  GWSService            *service;
  NSURL                 *gottenURL;


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
  
  //[service setDebug:YES];

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
  [service release];
  
  [logger log: LogDebug: @"[DBSoap Login]:resultDict is %d big\n", [resultDict count]];
  
  queryFault = [resultDict objectForKey:GWSFaultKey];
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
  
  loginResult = [resultDict objectForKey:GWSParametersKey];
  [logger log: LogDebug: @"[DBSoap Login]: coder parameters is %@\n", loginResult];
  
  enumerator = [loginResult keyEnumerator];
  while ((key = [enumerator nextObject]))
    [logger log: LogDebug: @"[DBSoap Login]:%@ - %@\n", key, [loginResult objectForKey:key]]; 
  
 
  loginResult2 = [loginResult objectForKey:@"result"];
  [logger log: LogDebug: @"[DBSoap Login]: %@\n", loginResult2];
  
  enumerator = [loginResult2 keyEnumerator];
  while ((key = [enumerator nextObject]))
    [logger log: LogDebug: @"[DBSoap Login]:%@ - %@\n", key, [loginResult2 objectForKey:key]]; 
    
  [sessionId release];
  sessionId = [loginResult2 objectForKey:@"sessionId"];
  gottenURL = [NSURL URLWithString:[loginResult2 objectForKey:@"serverUrl"]];
  
  passwordExpired = NO;
  if ([[loginResult2 objectForKey:@"passwordExpired"] isEqualToString:@"true"])
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
  if ([[gottenURL scheme] isEqualToString:@"https"] && !useHttps)
    {
      [logger log: LogInformative: @"[DBSoap Login]: preferences set to http, forcing....\n"];
      gottenURL = [[NSURL alloc] initWithScheme:@"http" host:[gottenURL host] path:[gottenURL path]];
      [gottenURL autorelease];
    }
  [self setServerURL:gottenURL];

  if (sessionId == nil)
  {
    [[NSException exceptionWithName:@"DBException" reason:@"No Session information returned." userInfo:nil] raise];
  }
  else
  {
    [logger log: LogStandard: @"[DBSoap Login]: sessionId: %@\n", sessionId];
    [logger log: LogStandard: @"[DBSoap Login]: serverUrl: %@\n", serverURL];
  }
  [sessionId retain];
}

/**
 <p>The passed <i>value</i> is transformed from a String to a specific Type
 (using a DBSTypeWrapper if recognized) using information of the object <i>sObj</i>
 through an object describes.<br>
 Besides Strings the value could be complex being either a special type like an Address
 or a nested result of a query.</p>

 <p>Currently, queryMore is not performed for nested results</p>
 */
- (id)adjustFormatForField:(NSString *)key forValue:(id)value inObject:(DBSObject *)sObj
{
  id retObj;
  NSString *type;
  DBSObject *objDetails;


  type = [sObj type];
  //  NSLog(@"Object Type: %@, key: %@, value %@", type, key, value);

  /* this is not an object, we cannot describe it */
  if ([type isEqualToString:@"AggregateResult"])
    return value;

  /* check for described object cache */
  objDetails = [sObjectDetailsDict objectForKey:type];
  if (!objDetails)
    {
      NSLog(@"*** describe Start***");
      // since we are already inside the queryAll lock, we call the unlocked describe version
      objDetails = [self _describeSObject:type];
      NSLog(@"*** describe End***");
      if (objDetails)
	[sObjectDetailsDict setObject:objDetails forKey:type];
    }
  if (objDetails)
    {
      NSDictionary *fieldProps;
      NSString *fieldType;
      
      fieldProps = [objDetails propertiesOfField: key];
      fieldType = [fieldProps objectForKey:@"type"];
      if ([fieldType isEqualToString:@"double"])
	{
          retObj = [[[DBSFDouble alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"int"])
	{
          retObj = [[[DBSFInteger alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"boolean"])
	{
	  retObj = [[[DBSFBoolean alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"currency"])
	{
          retObj = [[[DBSFCurrency alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"percent"])
	{
          retObj = [[[DBSFPercentage alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"date"])
	{
          retObj = [[[DBSFDate alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"datetime"])
	{
          retObj = [[[DBSFDateTime alloc] initWithSFString:value] autorelease];
	}
      else if ([fieldType isEqualToString:@"address"])
	{
	  retObj = value;
	}
      else if ([value isKindOfClass:[NSDictionary class]])
	{
          NSArray *records;
          BOOL done;

          /* a dictionary might be a single complex object or an array of nested objects */
          records = [value objectForKey:@"records"];
          if (records)
            {
              NSString       *doneStr;
              NSString       *sizeStr;
              NSMutableArray *objArray;
              unsigned long  size;

              objArray = [[NSMutableArray alloc] init];

              NSLog(@"adjustFormatForField : we have a nested array of objects: %lu", [records count]);
              doneStr = [(NSDictionary *)value objectForKey:@"done"];
              sizeStr = [(NSDictionary *)value objectForKey:@"size"];
              if (doneStr != nil)
                {
                  [logger log: LogDebug: @"[DBSoap adjustFormatForField] done: %@\n", doneStr];
                  done = NO;
                  if ([doneStr isEqualToString:@"true"])
                    done = YES;
                  else if ([doneStr isEqualToString:@"false"])
                    done = NO;
                  else
                    [logger log: LogStandard: @"[DBSoap adjustFormatForField] done, unexpected value: %@\n", doneStr];
                  if (!done)
                    {
                      // TODO we could retrieve more objects
                      [logger log: LogStandard: @"[DBSoap adjustFormatForField] nested query contains more results. queryMore not performed"];
                    }
                }

              size = 0;
              if (sizeStr != nil)
                {
                  NSScanner *scan;
                  long long ll;
                  
                  scan = [NSScanner scannerWithString:sizeStr];
                  if ([scan scanLongLong:&ll])
                    {
                      size = (unsigned long)ll;
                      [logger log: LogInformative: @"[DBSoap adjustFormatForField] Declared size is: %lu\n", size];
                    }
                  else
                    {
                      [logger log: LogStandard : @"[DBSoap adjustFormatForField] Could not parse Size string: %@\n", sizeStr];
                      NSLog(@"Error parsing subquery size string");
                      size = 0;
                      value = nil;
                    }
                }
              
              /* if we have only one element, put it in an array */
              if (size == 1)
                {
                  records = [NSArray arrayWithObject:records];
                }
              

              [self extractQueryRecords:records toObjects:objArray];
              retObj = [objArray autorelease];
            }
          else
            {
              NSString *type2;
              DBSObject *sObj2;
              NSMutableDictionary *dict2;
              NSUInteger i;
              NSDictionary *propDict;
              NSArray *keys;
          
              sObj2 = [[DBSObject alloc] init];
              type2 = [value objectForKey:@"type"];
	  
              propDict = [NSDictionary dictionaryWithObject:type2 forKey:@"type"];
              [sObj2 setObjectProperties: propDict];
	  
              // hack until DBSObjects can be handled by writers
              dict2 = [[NSMutableDictionary alloc] init];
	  
	  
              keys = [(NSDictionary *)value allKeys];
              //      NSLog(@"we have a complex object: %@ with keys: %@", type2, keys);
              for (i = 0; i < [keys count]; i++)
                {
                  id       obj;
                  id       value2;
                  NSString *key2;
	      
                  key2 = [keys objectAtIndex:i];
	      
                  /* special GSWS field */
                  if (key2 == GWSOrderKey)
                    continue;
	      
                  obj = [value objectForKey: key2];
	      
                  if ([key2 isEqualToString:@"Id"])
                    {
                      /* when queried, Id is always in an array, else empty string */
                      if ([obj isKindOfClass: [NSArray class]])
                        value2 = [(NSArray *)obj objectAtIndex: 0];
                      else
                        continue; /* skip empty Id */
                    }
                  else if ([key2 isEqualToString:@"type"])
                    {
                      continue;
                    }
                  else
                    value2 = obj;
	      
                  if (enableFieldTypesDescribeForQuery)
                    {
                      value2 = [self adjustFormatForField:key2 forValue:value2 inObject:sObj2];
                    }
                  [sObj2 setValue: value2 forField: key2];
                  [dict2 setObject: value2 forKey: key2];
                }
	  
              [sObj2 autorelease];
              [dict2 autorelease];
              retObj = dict2;
            }
	}
      else
	{
	  retObj = value;
	}
    }
  else
    {
      [logger log: LogStandard: @"[DBSoap adjustFormatForField] Failed to get field information: %@.%@\n", type, key];
      retObj = value;
    }

  
  return retObj;
}

/* A record of the result - may contain nested objects of subqueries */
- (DBSObject *)extractQueryRecord:(NSDictionary *)record
{
  NSUInteger      j;
  DBSObject      *sObj;
  NSMutableArray *keys;
  BOOL            typePresent;

  sObj = [[DBSObject alloc] init];

  /* let's get the fields from the keys of the first record */
  keys = [NSMutableArray arrayWithArray:[record allKeys]];
  [keys removeObject:GWSOrderKey];

  /* remove some fields which get added automatically by salesforce even if not asked for */
  typePresent = [keys containsObject:@"type"];
  if (typePresent)
    [keys removeObject:@"type"];
      
  /* remove Id only if it is null, else an array of two populated Id is returned by SF */
  if (![[record objectForKey:@"Id"] isKindOfClass: [NSArray class]])
    [keys removeObject:@"Id"];

  /* we removed type, but if it is present, set it as a property
     Further, we describe the type if desired to get field types.
  */
  if (typePresent) 
    {
      NSDictionary *propDict;
      NSString *typeStr;

      typeStr = [record objectForKey: @"type"];
      propDict = [NSDictionary dictionaryWithObject:typeStr forKey:@"type"];
      [sObj setObjectProperties: propDict];
    }
        
  NSLog (@"single record: %@", record);
  for (j = 0; j < [keys count]; j++)
    {
      id       obj;
      id       value;
      NSString *key;
            
      key = [keys objectAtIndex:j];
      obj = [record objectForKey: key];
      NSLog(@"analyzing %@ : %@", key, obj);
      if ([key isEqualToString:@"Id"])
	{
	  value = [(NSArray *)obj objectAtIndex: 0];
	  [sObj setValue: value forField: key];
	}
      else if ([obj isKindOfClass:[NSDictionary class]])
	{
	  // This is recurisve, it is a sub-query result
	  NSDictionary *result = (NSDictionary *)obj;
	  id           subRecords;

	  subRecords = [obj objectForKey:@"records"];
	  NSLog(@"Records! %@", subRecords);
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
	      NSLog(@"complex field: %@", value);
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
  NSLog(@"\n\nRecords to extract: %@\n\n", records);
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



- (NSArray *)_describeGlobal
{
  GWSService            *service;
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

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  /* make the query */  
  resultDict = [service invokeMethod: @"describeGlobal"
                parameters : parmsDict
		order : nil
		timeout : standardTimeoutSec];
  [service release];

  [logger log: LogDebug: @"[DBSoap describeGlobal] Describe Global dict is %lu big\n", [resultDict count]];
  
  queryFault = [resultDict objectForKey:GWSFaultKey];
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

  queryResult = [resultDict objectForKey:GWSParametersKey];
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
      NSUInteger j;
    
      sObj = [sobjects objectAtIndex: i];
      propertiesArray = [sObj objectForKey: GWSOrderKey];
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
      NSUInteger i;

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
  NSUInteger i;
  
  [sObjectList release];
  sObjectList = [[self _describeGlobal] retain];

  [sObjectNamesList release];
  sObjectNamesList = [[NSMutableArray arrayWithCapacity:1] retain];
  for (i = 0; i < [sObjectList count]; i++)
    [sObjectNamesList addObject: [[sObjectList objectAtIndex: i] name]];
}


- (DBSObject *)_describeSObject: (NSString *)objectType
{
  GWSService            *service;
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
  NSUInteger            i;
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

  /* init our service */
  service = [[DBSoap gwserviceForDBSoap] retain];
  [service setURL:serverURL];
  
  /* make the query */  
  resultDict = [service invokeMethod: @"describeSObject"
                parameters : parmsDict
		order : nil
		timeout : standardTimeoutSec];
  [service release];

  queryFault = [resultDict objectForKey:GWSFaultKey];
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

  queryResult = [resultDict objectForKey:GWSParametersKey];
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
  [keys removeObject:GWSOrderKey];


  for (i = 0; i < [records count]; i++)
    {
      NSMutableDictionary *props;
      NSString *fieldName;
      
      record = [records objectAtIndex:i];
      props = [NSMutableDictionary dictionaryWithDictionary: record];
      [props removeObjectForKey:GWSOrderKey];
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
          [mDict removeObjectForKey:GWSOrderKey];
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

- (NSURL *) serverURL
{
  return serverURL;
}

- (void) setServerURL:(NSURL *)url
{
  if (serverURL != url)
    {
      [serverURL release];
      serverURL = url;
      [serverURL retain];
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

- (void)dealloc
{
  [lockBusy release];

  [sObjectDetailsDict release];
  [sessionId release];
  [serverURL release];
  [userInfo release];
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

/** unelete the contents of array, which can be either strings of IDs or DBSObjects */
- (NSMutableArray *)undelete :(NSArray *)array progressMonitor:(id<DBProgressProtocol>)p;
{
  NSMutableArray *resArray;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap undelete] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];

  resArray = nil;
  NS_DURING
    resArray = [self _undelete:array progressMonitor:p];
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

/** retrieves given a query from a apecific object given an array of SF ID
 actually invokes retrieveFields after having parsed the query for Fields
 */
- (NSMutableArray *)retrieveWithQuery:(NSString *)queryString andObjects:(NSArray *)objectList
{
  NSArray *fields;
  NSString *objectName;
  
  if (objectList == nil)
    return nil;

  if ([objectList count] == 0)
    return nil;

  
  fields = [DBSoap fieldsByParsingQuery:queryString];
  if (fields && [fields count] > 0)
    {
      NSRange fromPosition;
      NSString *fromSubstring = nil;

      fromPosition = [queryString rangeOfString:@"from " options:NSCaseInsensitiveSearch];
      if (fromPosition.location != NSNotFound)
        fromSubstring = [queryString substringFromIndex: fromPosition.location + 5];
    
      objectName = [fromSubstring stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
      return [self retrieveFields:fields ofObject:objectName fromArray:objectList];
    }
  return nil;
}


/** retrieves fields (fieldList) from a specific object given an array of SF IDs */
- (NSMutableArray *)retrieveFields:(NSArray *)fieldList ofObject:(NSString*)objectType fromArray:(NSArray *)objectList
{
  NSMutableArray *resArray;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap retrieveFields] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];
  
  resArray = nil;
  NS_DURING
    resArray = [self _retrieveFields:fieldList ofObject:objectType fromObjects:objectList];
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

/** retrieves IDs of updated objects given a time interval */
- (NSMutableDictionary *)getUpdated :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate;
{
  NSMutableDictionary *resDict;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap getUpdated] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];
  
  resDict = nil;
  NS_DURING
    resDict = [self _getUpdated :objectType :startDate :endDate];
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
  
  return resDict;
}

/** retrieves IDs of deleted objects given a time interval */
- (NSMutableDictionary *)getDeleted :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate;
{
  NSMutableDictionary *resDict;
  
  [lockBusy lock];
  if (busyCount)
    {
      [logger log: LogStandard :@"[DBSoap getDeleted] called but busy\n"];
      [lockBusy unlock];
      return nil;
    }
  busyCount++;
  [lockBusy unlock];
  
  resDict = nil;
  NS_DURING
    resDict = [self _getDeleted :objectType :startDate :endDate];
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
  
  return resDict;
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

  sObj = [sObjectDetailsDict objectForKey:objectType];
  if (sObj)
    return sObj;
  
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

  [sObjectDetailsDict setObject:sObj forKey:objectType];
    
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

/** clean the cache of described objects (sObjectDetailsDict) */
- (void)flushObjectDetails
{
  [sObjectDetailsDict removeAllObjects];
}

- (BOOL)enableFieldTypesDescribeForQuery
{
  return enableFieldTypesDescribeForQuery;
}

- (void)setEnableFieldTypesDescribeForQuery:(BOOL)flag
{
  enableFieldTypesDescribeForQuery = flag;
}

/** returns the cache of described objects */
- (NSMutableDictionary *)sObjectDetailsDict
{
  return sObjectDetailsDict;
}

/** sets the cache of described objects */
- (void)setSObjectDetailsDict:(NSMutableDictionary *)md
{
  if (sObjectDetailsDict != md)
    {
      [sObjectDetailsDict release];
      sObjectDetailsDict = md;
      [sObjectDetailsDict retain];
    }
}
  

@end
