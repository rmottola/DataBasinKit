/*
  Project: DataBasin

  Copyright (C) 2008-2014 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2011-11-08 22:44:45 +0100 by multix

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
#import "DBSoapCSV.h"
#import "DBProgressProtocol.h"
#import "DBLoggerProtocol.h"

@implementation DBSoapCSV

- (void)setDBSoap: (DBSoap *)dbs
{
  db = dbs;
  logger = [db logger];
}

- (void)query :(NSString *)queryString queryAll:(BOOL)all toWriter:(DBCSVWriter *)writer progressMonitor:(id<DBProgressProtocol>)p
{
  int            batchSize;

  NSString       *qLoc;
  NSMutableArray *sObjects;
  
  
  sObjects = [[NSMutableArray alloc] init];

  [p reset];
  [p setCurrentDescription:@"Retrieving"];

  qLoc = nil;
  NS_DURING
    qLoc = [db query: queryString queryAll: all toArray: sObjects progressMonitor:p];
  NS_HANDLER
    [sObjects release];
    [localException raise];
  NS_ENDHANDLER

  batchSize = [sObjects count];
  if (batchSize > 0)
    {
      [writer setFieldNames: [sObjects objectAtIndex: 0] andWriteIt:YES];
      [p setCurrentDescription:@"Writing"];
      [writer writeDataSet: sObjects];
      [p incrementCurrentValue:[sObjects count]];
    }

  while (qLoc != nil)
    {
      [p setCurrentDescription:@"Retrieving"];
      [sObjects removeAllObjects];
      qLoc = [db queryMore: qLoc toArray: sObjects];
      [p setCurrentDescription:@"Writing"];
      [writer writeDataSet: sObjects];
      [p incrementCurrentValue:[sObjects count]];
    }
  [sObjects release];
  [p setCurrentDescription:@"Done"];
  [p setEnd];
}

/**
   See DBSoap for informations about the batch size parameter.
 */
- (void)queryIdentify :(NSString *)queryString queryAll:(BOOL)all fromReader:(DBCSVReader *)reader toWriter:(DBCSVWriter *)writer withBatchSize:(int)bSize progressMonitor:(id<DBProgressProtocol>)p
{
  NSArray *inFieldNames;
  unsigned inFieldCount;
  NSArray *dataSet;
  NSMutableArray *identifierArray;
  NSMutableArray *sObjects;
  unsigned i;
  unsigned batchSize;
  NSArray *keys;

  [p reset];
  
  /* retrieve objects to create */
  
  /* first the fields */
  [p setCurrentDescription:@"Loading data"];
  inFieldNames = [reader fieldNames];
  inFieldCount = [inFieldNames count];
  dataSet = [reader readDataSet];
  [logger log: LogDebug :@"[DBSoapCSV queryIdentify] field names: %@\n", inFieldNames];
  
  if (inFieldCount == 1)
    {
      identifierArray = [[NSMutableArray arrayWithCapacity: [dataSet count]] retain];
      for (i = 0; i < [dataSet count]; i++)
        [identifierArray addObject: [[dataSet objectAtIndex: i] objectAtIndex: 0]];
    }
  else
    {
      identifierArray = (NSMutableArray *)dataSet;
      [identifierArray retain];
    }
  
  [p setMaximumValue:[identifierArray count]];
  sObjects = [[NSMutableArray alloc] init];

  [p setCurrentDescription:@"Identifying and querying."];
  [logger log: LogStandard :@"[DBSoapCSV queryIdentify] Identify through %@\n", inFieldNames];

  NS_DURING
    [db queryIdentify:queryString with:inFieldNames queryAll:all fromArray:identifierArray toArray: sObjects withBatchSize:bSize progressMonitor: p];
  NS_HANDLER
    [identifierArray release];
    [sObjects release];
    [localException raise];
  NS_ENDHANDLER
  
  [p setCurrentDescription:@"Writing data"];
  keys = nil;
  batchSize = [sObjects count];
  if (batchSize > 0)
    {
      [writer setFieldNames:[sObjects objectAtIndex: 0] andWriteIt:YES];
      [writer writeDataSet: sObjects];
    }
  
  [sObjects release];
  [identifierArray release];
  [p setEnd];
}

- (NSMutableArray *)create :(NSString *)objectName fromReader:(DBCSVReader *)reader progressMonitor:(id<DBProgressProtocol>)p
{
  NSEnumerator   *enumerator;
  NSArray        *objectsArray;
  NSArray        *fieldValues;
  NSArray        *fieldNames;
  NSUInteger     fieldCount;
  NSMutableArray *sObjectsArray;
  NSMutableArray *resultArray;

  /* retrieve objects to create */
  
  /* first the fields */
  fieldNames = [reader fieldNames];
  fieldCount = [fieldNames count];
  objectsArray = [reader readDataSet];
  

  sObjectsArray = [[NSMutableArray arrayWithCapacity: [objectsArray count]] retain];
  
  enumerator = [objectsArray objectEnumerator];
  while ((fieldValues = [enumerator nextObject]))
  {
    unsigned int i;
    DBSObject *sObj;

    sObj = [[DBSObject alloc] init];
  
    for (i = 0; i < fieldCount; i++)
      [sObj setValue: [fieldValues objectAtIndex:i] forField: [fieldNames objectAtIndex:i]];
 
    [sObjectsArray addObject: sObj];
    [sObj release];
  }

  resultArray = nil;
  NS_DURING
    resultArray = [db create:objectName fromArray:sObjectsArray progressMonitor:p];
  NS_HANDLER
    [sObjectsArray release];
    [localException raise];
  NS_ENDHANDLER
  [sObjectsArray release];
  [p setCurrentDescription:@"Done"];
  [p setEnd];
  return resultArray;
}

- (NSMutableArray *)update :(NSString *)objectName fromReader:(DBCSVReader *)reader progressMonitor:(id<DBProgressProtocol>)p
{
  NSEnumerator   *enumerator;
  NSArray        *objectsArray;
  NSArray        *fieldValues;
  NSArray        *fieldNames;
  NSUInteger     fieldCount;
  NSMutableArray *sObjectsArray;
  NSMutableArray *resultArray;

  /* retrieve objects to update */
  [p reset];
  [p setCurrentDescription:@"Retrieving"];

  /* first the fields */
  fieldNames = [reader fieldNames];
  fieldCount = [fieldNames count];
  objectsArray = [reader readDataSet];
  

  sObjectsArray = [[NSMutableArray arrayWithCapacity: [objectsArray count]] retain];
  
  enumerator = [objectsArray objectEnumerator];
  while ((fieldValues = [enumerator nextObject]))
  {
    unsigned int i;
    DBSObject *sObj;

    sObj = [[DBSObject alloc] init];
  
    for (i = 0; i < fieldCount; i++)
      [sObj setValue: [fieldValues objectAtIndex:i] forField: [fieldNames objectAtIndex:i]];
 
    [sObjectsArray addObject: sObj];
    [sObj release];
  }

  resultArray = nil;
  NS_DURING
    resultArray = [db update:objectName fromArray:sObjectsArray progressMonitor:p];
  NS_HANDLER
    [sObjectsArray release];
    [localException raise];
  NS_ENDHANDLER

  [sObjectsArray release];
  [p setCurrentDescription:@"Done"];
  [p setEnd];
  return resultArray;
}

- (void)describeSObject: (NSString *)objectType toWriter:(DBCSVWriter *)writer
{
  NSUInteger      i;
  NSUInteger     size;
  DBSObject      *object;
  NSDictionary   *properties;
  NSArray        *fields;
  NSArray        *keys;
  NSMutableArray *set;

  
  object = [db describeSObject: objectType];
  fields = [object fieldNames];
  size = [fields count];
  
  if (size < 1)
    return;
  
  keys = [[object propertiesOfField: [fields objectAtIndex: 0]] allKeys];
  [writer setFieldNames:[NSArray arrayWithArray:keys] andWriteIt:YES];
  
  set = [[NSMutableArray alloc] init];
  
  for (i = 0; i < size; i++)
    {
      NSMutableArray *values;
      NSUInteger      j;
      NSString       *field;
      
      field = [fields objectAtIndex: i];
      properties = [object propertiesOfField: field];
      values = [NSMutableArray arrayWithCapacity:[keys count]];
      for (j = 0; j < [keys count]; j++)
        {
          id       obj;
          id       value;
          NSString *key;
      
          key = [keys objectAtIndex:j];
          obj = [properties objectForKey: key];
      
          value = obj;
          [values addObject:value];
        }
      [set addObject:values];
    }
  [writer writeDataSet:set];
  [set release];
}



- (NSMutableArray *)deleteFromReader:(DBCSVReader *)reader progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *objectsArray;
  NSMutableArray *resultArray;

  /* retrieve objects to delete */
  // FIXME perhaps this copy is useless
  objectsArray = [[NSMutableArray arrayWithArray:[reader readDataSet]] retain];
  [logger log: LogDebug :@"[DBSoapCSV delete] objects to delete: %@\n", objectsArray];
  [logger log: LogStandard :@"[DBSoapCSV delete] Count of objects to delete: %d\n", [objectsArray count]];

  resultArray = nil;
  NS_DURING
    resultArray = [db delete:objectsArray progressMonitor:p];
  NS_HANDLER
    [objectsArray release];
    [localException raise];
  NS_ENDHANDLER

  [objectsArray release];
  return resultArray;
}


- (void)dealloc
{
  [super dealloc];
}

@end
