/* -*- mode: objc -*-
 Project: DataBasin
 DBSobject.m
 
 Copyright (C) 2010-2021 Free Software Foundation
 
 Author: Riccardo Mottola
 
 Created by Riccardo Mottola on 20/07/10.
 

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


#import "DBSObject.h"
#import "DBSoap.h"

@implementation DBSObject

/** <p>Returns the corresponding 18-character case-insensitive
    salesforce Id given the 15-character version <em>id15</em></p>
*/
+ (NSString *)idTo18: (NSString *) id15
{
  NSMutableString *suffix;
  int i;
  int j;
  
  if ([id15 length] != 15)
    return nil;
  
  suffix = [NSMutableString stringWithCapacity: 3];
  for (i = 0; i < 3; i++)
    {
      int flags = 0;
      for (j = 0; j < 5; j++)
        {
          unichar c;
          c = [id15 characterAtIndex: i * 5 + j];
          if (c >= 'A' && c <= 'Z')
            flags += 1 << j;
        }
      if (flags <= 25)
        [suffix appendString: [@"ABCDEFGHIJKLMNOPQRSTUVWXYZ" substringWithRange: NSMakeRange(flags, 1)]];
      else
        [suffix appendString: [@"012345" substringWithRange: NSMakeRange(flags-26, 1)]];
    }
  return [id15 stringByAppendingString: suffix];  
}

- (id)init
{
  if ((self = [super init]))
    {
      fieldNames = [[NSMutableArray arrayWithCapacity: 1] retain];
      fieldProperties = [[NSMutableDictionary dictionaryWithCapacity: 1] retain];
      recordValues = [[NSMutableDictionary dictionaryWithCapacity: 1] retain];
      objectProperties = [[NSMutableDictionary dictionaryWithCapacity: 1] retain];
    }
  return self;
}

- (id)copyWithZone: (NSZone *)zone
{
  DBSObject *sobj;

  sobj = [[[self class] allocWithZone: zone] init];
  if(sobj)
    {
      sobj->dbs = dbs;
      sobj->fieldNames = [fieldNames mutableCopy];
      sobj->fieldProperties = [fieldProperties mutableCopy];
      sobj->recordValues = [recordValues mutableCopy];
      sobj->objectProperties = [objectProperties mutableCopy];
      sobj->recordTypes = [recordTypes copy];
    }
  return sobj;
}

- (void)dealloc
{
  [fieldNames release];
  [fieldProperties release];
  [recordValues release];
  [objectProperties release];
  [recordTypes release];
  [super dealloc];
}

- (NSString *)description
{
  return [NSString stringWithFormat: @"<DBSObject %@, n:%@, l:%@, t:%@>", [self sfId], [self name], [self label], [self type]];
}

/** <p>returns the current salesforce id, in whichever format it is currently stored.</p>
*/
- (NSString *)sfId
{
  return [recordValues objectForKey: @"Id"];
}

/** <p>Returns the current salesforce Id, always in the 15-character case-sensitive format,
    converting it if necessary.</p>
*/
- (NSString *)sfId15
{
  NSString *sfid;
  
  sfid = [recordValues objectForKey: @"Id"];
  if ([sfid length] == 18)
    sfid = [sfid substringToIndex: 15];
  
  if ([sfid length] != 15)
    {
      NSLog(@"Invalid ID: %@", sfid);
      return nil;
    }
  
  return sfid;
}

/** <p>Returns the current salesforce Id, always in the 18-character case-insensitive format,
converting it if necessary.</p>
*/
- (NSString *)sfId18
{
  NSString *sfid;
  
  sfid = [recordValues objectForKey: @"Id"];
  if ([sfid length] == 15)
    sfid = [DBSObject idTo18: sfid];
  
  if ([sfid length] != 18)
    {
      NSLog(@"Invalid ID: %@", sfid);
      return nil;
    }
  
  return sfid;
}

- (void)setDBSoap: (DBSoap *)db
{
  dbs = db;
}

- (DBSoap *)DBSoap
{
  return dbs;
}

- (void)setObjectProperties: (NSDictionary *)properties
{
  if (properties != objectProperties)
    [objectProperties release];
  objectProperties = [[NSMutableDictionary dictionaryWithDictionary: properties] retain];
}

- (NSDictionary *)objectProperties
{
  return [NSDictionary dictionaryWithDictionary: objectProperties];
}

- (NSString *)name
{
  return [objectProperties objectForKey: @"name"];
}

- (NSString *)type
{
  return [objectProperties objectForKey: @"type"];
}

- (NSString *)label
{
  return [objectProperties objectForKey: @"label"];
}

- (NSString *)keyPrefix
{
  return [objectProperties objectForKey: @"keyPrefix"];
}


- (void)setProperties: (NSDictionary *)properties forField: (NSString *)field
{
  // TODO should check if field is not already present
  [fieldNames addObject: field];
  [fieldProperties setObject: properties forKey: field];
}

- (void)removeField: (NSString *)field
{
  [recordValues removeObjectForKey: field];
  [fieldNames removeObject: field];
}

- (NSDictionary *)propertiesOfField: (NSString *)field
{
  return [fieldProperties objectForKey: field];
}

/** <p>Returns a list of all known field names.</p>
*/
- (NSArray *)fieldNames
{
  return fieldNames;
}

/** <p>Returns the value of field <em>field</em></p>
*/
- (id)valueForField: (NSString *)field
{
  return [recordValues objectForKey: field];
}

/** <p>Sets the value of the given field of the record and adds it
    to the list if field names if it was not already present.</p>
*/
- (void)setValue: (id)value forField: (NSString*)field
{
  if (![fieldNames containsObject: field])
    [fieldNames addObject: field];
  
  [recordValues setObject: value forKey: field];
}

- (void)setRecordTypes: (NSArray *)rtInfo
{
  ASSIGN(recordTypes, rtInfo);
}

- (NSArray *)recordTypes
{
  return recordTypes;
}


- (void)loadFieldValues
{
  NSUInteger i;
  NSUInteger sizeCount;
  NSMutableArray *fieldsArray;

  if (dbs == nil)
    return;

  fieldsArray = [NSMutableArray arrayWithCapacity: 10];
  sizeCount = 0;
  for (i = 0; i < [fieldNames count]; i++)
    {
      NSString *currField;

      currField = [fieldNames objectAtIndex:i];
      if (sizeCount + [currField length] + 2 < [dbs maxSOQLLength])
	{
	  [fieldsArray addObject: currField];
	  sizeCount += [currField length] + 2;
	}
      else
	{
	  [self loadValuesForFields: fieldsArray];
	  fieldsArray = [NSMutableArray arrayWithCapacity: 10];
	  [fieldsArray addObject: currField];
	  sizeCount = [currField length] + 2;
	}
    }
  NSLog(@"we have %u fields", (unsigned int)[fieldsArray count]);
  [self loadValuesForFields: fieldsArray];
}

- (void)loadValuesForFields:(NSArray *)namesArray
{
  NSMutableString *statement;
  NSMutableArray *tempArray;
  DBSObject *tempObj;
  NSUInteger i;

  if ([namesArray count] == 0)
    return;

  if ([self sfId] == nil)
    return;

  statement = [NSMutableString stringWithString:@"Select "];
  i = 0;
  while (i < [namesArray count])
    {
      [statement appendString: [namesArray objectAtIndex: i]];
      if (i < ([namesArray count] - 1))
	[statement appendString: @", "];
      i++;
    }
  [statement appendString: @" from "];
  [statement appendString: [self name]];
  [statement appendString: @" where id = '"];
  [statement appendString: [self sfId]];
  [statement appendString: @"'"];
  NSLog(@"query: %@", statement);
  tempArray = [NSMutableArray arrayWithCapacity: [namesArray count]];
  [dbs query :statement queryAll:YES toArray: tempArray progressMonitor:nil];
  if ([tempArray count] == 0)
    {
      [[NSException exceptionWithName:@"DBException" reason:@"Object not found." userInfo:nil] raise];
      return;
    }
  tempObj = [tempArray objectAtIndex: 0];

  /* copy the field values from the query result to the object itself */
  for (i = 0; i < [namesArray count]; i++)
    {
      NSString *fieldName;

      fieldName = [namesArray objectAtIndex: i];
      [self setValue: [tempObj valueForField: fieldName] forField: fieldName];
    }
}

- (void)storeValuesForFields:(NSArray *)namesArray
{
  NSUInteger i;
  DBSObject *tObj;
  NSMutableArray *tArr;
  NSMutableArray *results;
  NSString *errorString;

  if (!namesArray || [namesArray count] == 0)
    return;

  tObj = [[DBSObject alloc] init];
  tArr = [[NSMutableArray alloc] initWithCapacity:1];
  [tArr addObject:tObj];
  [tObj release];

  [tObj setObjectProperties:[self objectProperties]];
  [tObj setValue:[self sfId] forField:@"Id"];
  for (i = 0; i < [namesArray count]; i++)
    {
      NSString *fieldName;
      NSString *fieldValue;
    
      fieldName = [namesArray objectAtIndex: i];
      fieldValue = [self valueForField:fieldName];
//      NSLog(@"%@ - %@", fieldName, fieldValue);
      if (fieldValue)
        [tObj setValue:fieldValue forField:fieldName];
      else
        NSLog(@"Error: trying to update field %@, but the field is null", fieldValue);
    }
  results = [dbs update :[tObj name] fromArray: tArr progressMonitor:nil];
  
  errorString = nil;
  if (results && [results count] > 0)
    {
      NSUInteger j;
    
      for (j = 0; j < [results count]; j++)
        {
          NSDictionary *r;

          r = [results objectAtIndex:j];
          if ([[r objectForKey:@"success"] isEqualToString:@"false"])
            {
              if (errorString == nil)
                errorString = [NSString stringWithString:[r objectForKey:@"message"]];
              else
                errorString = [[errorString stringByAppendingString:@", "] stringByAppendingString:[r objectForKey:@"message"]];
            }
        }
    }
  else
    {
      NSLog(@"Error: no valid results returned");
    }

  [tArr release];
  if (errorString)
    {
      NSLog(@"Errors: %@", errorString);
      [[NSException exceptionWithName:@"DBException" reason:errorString userInfo:nil] raise];
    }
}

@end
