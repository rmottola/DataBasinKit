/*
  Project: DataBasin

  Copyright (C) 2008-2015 Free Software Foundation

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

/* since query identify would work in a big array giving memory issues, we split it up in this batch size */
#define MAX_SIZE_OF_IDENTBATCH 20000

@implementation DBSoapCSV

- (void)setDBSoap: (DBSoap *)dbs
{
  db = dbs;
  logger = [db logger];
}

- (void)query :(NSString *)queryString queryAll:(BOOL)all toWriter:(DBCSVWriter *)writer progressMonitor:(id<DBProgressProtocol>)p
{
  int            batchSize;
  NSArray        *fields;
  NSString       *qLoc;
  NSMutableArray *sObjects;
  GWSService     *serv;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  serv = [DBSoap gwserviceForDBSoap];
  [dbSoap setSessionId:[db sessionId]];
  [serv setURL:[db serverUrl]];  
  [dbSoap setService:serv];
  [dbSoap setDownBatchSize:[db downBatchSize]];
  
  fields = nil;
  if ([writer writeFieldsOrdered])
    {
      fields = [DBSoap fieldsByParsingQuery:queryString];
      [logger log: LogDebug :@"[DBSoapCSV query] query parsed fields: %@\n", fields];
    }

  sObjects = [[NSMutableArray alloc] init];

  [p reset];
  [p setCurrentDescription:@"Retrieving"];

  qLoc = nil;
  NS_DURING
    qLoc = [dbSoap query: queryString queryAll: all toArray: sObjects progressMonitor:p];
  NS_HANDLER
    [sObjects release];
    [dbSoap release];
    [localException raise];
  NS_ENDHANDLER

  batchSize = [sObjects count];
  if (batchSize > 0)
    {
      if (fields != nil)
        {
          [writer setWriteFieldsOrdered:YES];
          [writer setFieldNames: fields andWriteThem:YES];
        }
      else
        {
          [writer setFieldNames: [sObjects objectAtIndex: 0] andWriteThem:YES];
        }
      [p setCurrentDescription:@"Writing"];
      [writer writeDataSet: sObjects];
      [p incrementCurrentValue:[sObjects count]];
      if (!qLoc && batchSize == 1)
	{
	  // Aggregate query count() without id returns the size as count but contains only one record
	  // We detect such a case and mark progress as completed
	  if ([queryString rangeOfString:@"count()" options:NSCaseInsensitiveSearch].location != NSNotFound)
	    [p setEnd];
	}	  
    }

  while (qLoc != nil && ![p shouldStop])
    {
      NSAutoreleasePool *arp;

      arp = [[NSAutoreleasePool alloc] init];
      [p setCurrentDescription:@"Retrieving"];
      [sObjects removeAllObjects];
      NS_DURING
        qLoc = [dbSoap queryMore: qLoc toArray: sObjects];
      NS_HANDLER
        qLoc = nil;
        [logger log: LogDebug :@"[DBSoapCSV query] Exception during query more: %@\n", [localException description]];
      NS_ENDHANDLER
      [p setCurrentDescription:@"Writing"];
      [writer writeDataSet: sObjects];
      [p incrementCurrentValue:[sObjects count]];
      [arp drain];
    }
  [dbSoap release];
  [sObjects release];
  if ([p shouldStop])
    [p setCurrentDescription:@"Interrupted"];
  else
    [p setCurrentDescription:@"Done"];
}

/**
   See DBSoap for informations about the batch size parameter.
 */
- (void)queryIdentify :(NSString *)queryString queryAll:(BOOL)all fromReader:(DBCSVReader *)reader toWriter:(DBCSVWriter *)writer withBatchSize:(int)bSize progressMonitor:(id<DBProgressProtocol>)p
{
  NSArray        *inFieldNames;
  NSUInteger      inFieldCount;
  NSArray        *dataSet;
  NSMutableArray *identifierArray;
  NSMutableArray *sObjects;
  NSUInteger     i;
  NSUInteger     batchSize;
  NSArray        *queryFields;
  GWSService     *serv;
  DBSoap         *dbSoap;
  BOOL           firstBatchIteration;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  serv = [DBSoap gwserviceForDBSoap];
  [dbSoap setSessionId:[db sessionId]];
  [serv setURL:[db serverUrl]];  
  [dbSoap setService:serv];
  [dbSoap setDownBatchSize:2000];
  
  queryFields = nil;
  if ([writer writeFieldsOrdered])
    {
      queryFields = [DBSoap fieldsByParsingQuery:queryString];
      [logger log: LogDebug :@"[DBSoapCSV queryIdentify] query parsed fields: %@\n", queryFields];
    }

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

  firstBatchIteration = YES; /* we keep track of the first batch since we need to writ the header only once*/
  while ([identifierArray count] > 0 && ![p shouldStop])
    {
      NSRange subArrayRange;
      NSArray *batchOfIdentifiers;
      NSAutoreleasePool *arp;

      arp = [[NSAutoreleasePool alloc] init];
      subArrayRange = NSMakeRange(0, [identifierArray count]);
      if ([identifierArray count] > MAX_SIZE_OF_IDENTBATCH)
        subArrayRange = NSMakeRange(0, MAX_SIZE_OF_IDENTBATCH);
      batchOfIdentifiers = [identifierArray subarrayWithRange:subArrayRange];
      [batchOfIdentifiers retain];
      [identifierArray removeObjectsInRange:subArrayRange];

      NS_DURING
        [db queryIdentify:queryString with:inFieldNames queryAll:all fromArray:batchOfIdentifiers toArray: sObjects withBatchSize:bSize progressMonitor: p];
      NS_HANDLER
        [identifierArray release];
        [sObjects release];
        [dbSoap release];
        [localException raise];
        [batchOfIdentifiers release];
        [arp drain];
      NS_ENDHANDLER

      [batchOfIdentifiers release];
      [p setCurrentDescription:@"Writing data"];
      batchSize = [sObjects count];
      if (batchSize > 0 )
        {
          if (firstBatchIteration)
            {
              if (queryFields != nil)
                {
                  [writer setWriteFieldsOrdered:YES];
                  [writer setFieldNames: queryFields andWriteThem:YES];
                }
              else
                {
                  [writer setFieldNames: [sObjects objectAtIndex: 0] andWriteThem:YES];
                }
              firstBatchIteration = NO;
            }
          [writer writeDataSet: sObjects];
          [sObjects removeAllObjects];
        }
      [arp drain];
    }
  [dbSoap release];  
  [sObjects release];
  [identifierArray release];
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
  GWSService     *serv;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  serv = [DBSoap gwserviceForDBSoap];
  [dbSoap setSessionId:[db sessionId]];
  [serv setURL:[db serverUrl]];  
  [dbSoap setService:serv];
  
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
    [dbSoap release];
    [localException raise];
  NS_ENDHANDLER
  
  [dbSoap release];
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
  GWSService     *serv;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  serv = [DBSoap gwserviceForDBSoap];
  [dbSoap setSessionId:[db sessionId]];
  [serv setURL:[db serverUrl]];  
  [dbSoap setService:serv];
  
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
    [dbSoap release];
    [localException raise];
  NS_ENDHANDLER

  [dbSoap release];
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
  GWSService     *serv;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  serv = [DBSoap gwserviceForDBSoap];
  [dbSoap setSessionId:[db sessionId]];
  [serv setURL:[db serverUrl]];  
  [dbSoap setService:serv];
  
  NS_DURING 
    object = [db describeSObject: objectType];
  NS_HANDLER
    [dbSoap release];
    [localException raise];
    return;
  NS_ENDHANDLER
  
  fields = [object fieldNames];
  size = [fields count];
  
  
  keys = [[object propertiesOfField: [fields objectAtIndex: 0]] allKeys];
  [writer setFieldNames:[NSArray arrayWithArray:keys] andWriteThem:YES];
  
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
  [dbSoap release];
}



- (NSMutableArray *)deleteFromReader:(DBCSVReader *)reader progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *objectsArray;
  NSMutableArray *resultArray;
  GWSService     *serv;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  serv = [DBSoap gwserviceForDBSoap];
  [dbSoap setSessionId:[db sessionId]];
  [serv setURL:[db serverUrl]];  
  [dbSoap setService:serv];
  
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
    [dbSoap release];
    [localException raise];
  NS_ENDHANDLER

  [dbSoap release];
  [objectsArray release];
  return resultArray;
}


- (void)dealloc
{
  [super dealloc];
}

@end
