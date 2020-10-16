/* -*- mode: objc -*-
  Project: DataBasin

  Copyright (C) 2008-2019 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2011-11-08 22:44:45 +0100 by Riccardo Mottola

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
#import "DBCSVReader.h"

/* since query identify would work in a big array giving memory issues, we split it up in this batch size */
#define MAX_SIZE_OF_IDENTBATCH 20000

@implementation DBSoapCSV

- (void)setDBSoap: (DBSoap *)dbs
{
  db = dbs;
  logger = [db logger];
}

- (void)query :(NSString *)queryString queryAll:(BOOL)all toWriter:(DBFileWriter *)writer progressMonitor:(id<DBProgressProtocol>)p
{
  NSUInteger     batchSize;
  NSArray        *fields;
  NSString       *qLoc;
  NSMutableArray *sObjects;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setLogger:logger];
  [dbSoap setDownBatchSize:[db downBatchSize]];
  [dbSoap setEnableFieldTypesDescribeForQuery:[db enableFieldTypesDescribeForQuery]];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  fields = nil;
  if ([writer writeFieldsOrdered])
    {
      fields = [DBSoap fieldsByParsingQuery:queryString];
      [logger log: LogDebug :@"[DBSoapCSV query] query parsed fields: %@\n", fields];
    }

  [writer writeStart];

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
      if ([writer writeFieldsOrdered])
        [writer setFieldNames: fields andWriteThem:YES];
      else
        [writer setFieldNames: [sObjects objectAtIndex: 0] andWriteThem:YES];
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

  [qLoc retain];
  while (qLoc != nil && ![p shouldStop])
    {
      NSAutoreleasePool *arp;

      arp = [[NSAutoreleasePool alloc] init];
      [p setCurrentDescription:@"Retrieving"];
      [sObjects removeAllObjects];
      NS_DURING
        NSString *temp;
        temp = [dbSoap queryMore: qLoc toArray: sObjects];
        [qLoc release];
        qLoc = [temp retain];
      NS_HANDLER
        [qLoc release];
        qLoc = nil;
        [logger log: LogDebug :@"[DBSoapCSV query] Exception during query more: %@\n", [localException description]];
      NS_ENDHANDLER
      [p setCurrentDescription:@"Writing"];
      [writer writeDataSet: sObjects];
      [p incrementCurrentValue:[sObjects count]];
      [arp release];
    }
  [qLoc release];

  [writer writeEnd];
  [dbSoap release];
  [sObjects release];
  if ([p shouldStop])
    [p setCurrentDescription:@"Interrupted"];
  else
    [p setCurrentDescription:@"Done"];
}

/**
   See DBSoap for informations about the batch size parameter.

   The batch size parameter affects
 */
- (void)queryIdentify :(NSString *)queryString queryAll:(BOOL)all fromReader:(DBCSVReader *)reader toWriter:(DBFileWriter *)writer withBatchSize:(int)bSize progressMonitor:(id<DBProgressProtocol>)p
{
  NSArray        *inFieldNames;
  NSUInteger      inFieldCount;
  NSArray        *dataSet;
  NSMutableArray *identifierArray;
  NSUInteger     i;
  NSUInteger     batchSize;
  NSArray        *queryFields;
  DBSoap         *dbSoap;
  BOOL           firstBatchIteration;
  NSUInteger     identifyBatchSize;

  /* if we identify through fields which are not keys and return a large number of results, the DBSoap identify,
     We try to be smart and thus if Max is not selected as query batch size, then we sync the identify and the query
     batch sizes */
  identifyBatchSize = MAX_SIZE_OF_IDENTBATCH;
  if (bSize > 0)
    identifyBatchSize = bSize;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setLogger:logger];
  [dbSoap setDownBatchSize:2000];
  [dbSoap setEnableFieldTypesDescribeForQuery:[db enableFieldTypesDescribeForQuery]];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  queryFields = nil;
  if ([writer writeFieldsOrdered])
    {
      queryFields = [DBSoap fieldsByParsingQuery:queryString];
      [logger log: LogDebug :@"[DBSoapCSV queryIdentify] query parsed fields: %@\n", queryFields];
    }

  [p reset];

  [writer writeStart];
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

  [p setCurrentDescription:@"Identifying and querying."];
  [logger log: LogStandard :@"[DBSoapCSV queryIdentify] Identify through %@\n", inFieldNames];

  firstBatchIteration = YES; /* we keep track of the first batch since we need to write the header only once*/
  while ([identifierArray count] > 0 && ![p shouldStop])
    {
      NSRange subArrayRange;
      NSArray *batchOfIdentifiers;
      NSAutoreleasePool *arp;
      NSMutableArray *sObjects;

      arp = [[NSAutoreleasePool alloc] init];
      subArrayRange = NSMakeRange(0, [identifierArray count]);
      if ([identifierArray count] > identifyBatchSize)
        subArrayRange = NSMakeRange(0, identifyBatchSize);
      batchOfIdentifiers = [identifierArray subarrayWithRange:subArrayRange];
      [batchOfIdentifiers retain];
      [identifierArray removeObjectsInRange:subArrayRange];

      sObjects = [[NSMutableArray alloc] init];
      NS_DURING
        [dbSoap queryIdentify:queryString with:inFieldNames queryAll:all fromArray:batchOfIdentifiers toArray: sObjects withBatchSize:bSize progressMonitor: p];
      NS_HANDLER
        [identifierArray release];
        [sObjects release];
        [dbSoap release];
        [localException raise];
        [batchOfIdentifiers release];
        [arp release];
      NS_ENDHANDLER

      [batchOfIdentifiers release];
      [p setCurrentDescription:@"Writing data"];
      batchSize = [sObjects count];
      if (batchSize > 0 )
        {
          if (firstBatchIteration)
            {
              if ([writer writeFieldsOrdered])
                {
                  [writer setFieldNames: queryFields andWriteThem:YES];
                }
              else
                {
                  [writer setFieldNames: [sObjects objectAtIndex: 0] andWriteThem:YES];
                }
              firstBatchIteration = NO;
            }
          [writer writeDataSet: sObjects];
        }
      [sObjects release];
      [arp release];
    }
  [writer writeEnd];
  [dbSoap release];  
  [identifierArray release];
}

- (void)retrieve :(NSString *)queryString fromReader:(DBCSVReader *)reader toWriter:(DBFileWriter *)writer withBatchSize:(int)bSize progressMonitor:(id<DBProgressProtocol>)p
{
  NSArray        *inFieldNames;
  NSUInteger      inFieldCount;
  NSArray        *dataSet;
  NSMutableArray *identifierArray;
  NSUInteger     i;
  NSUInteger     batchSize;
  NSArray        *queryFields;
  DBSoap         *dbSoap;
  BOOL           firstBatchIteration;
  NSUInteger     retrieveBatchSize;

  retrieveBatchSize = RETRIEVE_BATCH_SIZE;
  if (bSize > 0 && bSize < RETRIEVE_BATCH_SIZE)
    retrieveBatchSize = bSize;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setLogger:logger];
  [dbSoap setEnableFieldTypesDescribeForQuery:[db enableFieldTypesDescribeForQuery]];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  queryFields = nil;
  if ([writer writeFieldsOrdered])
    {
      queryFields = [DBSoap fieldsByParsingQuery:queryString];
      [logger log: LogDebug :@"[DBSoapCSV retrieve] query parsed fields: %@\n", queryFields];
    }

  [p reset];

  [writer writeStart];
  /* retrieve objects to create */
  
  /* first the fields */
  [p setCurrentDescription:@"Loading data"];
  inFieldNames = [reader fieldNames];
  inFieldCount = [inFieldNames count];
  dataSet = [reader readDataSet];
  [logger log: LogDebug :@"[DBSoapCSV retrieve] field names: %@\n", inFieldNames];
  
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

  [p setCurrentDescription:@"Retrieving."];

  firstBatchIteration = YES; /* we keep track of the first batch since we need to write the header only once*/
  while ([identifierArray count] > 0 && ![p shouldStop])
    {
      NSRange subArrayRange;
      NSArray *batchOfIdentifiers;
      NSAutoreleasePool *arp;
      NSMutableArray *sObjects;
      
      arp = [[NSAutoreleasePool alloc] init];
      subArrayRange = NSMakeRange(0, [identifierArray count]);
      if ([identifierArray count] > retrieveBatchSize)
        subArrayRange = NSMakeRange(0, retrieveBatchSize);
      batchOfIdentifiers = [identifierArray subarrayWithRange:subArrayRange];
      [batchOfIdentifiers retain];
      NSLog(@"retrieve batch iteration, remaining count is: %lu, subarray size: %lu",  [identifierArray count], [batchOfIdentifiers count]);
      [identifierArray removeObjectsInRange:subArrayRange];

      sObjects = nil;
      NS_DURING
        sObjects = [dbSoap retrieveWithQuery:queryString andObjects:batchOfIdentifiers];
      NS_HANDLER
        [identifierArray release];
        [dbSoap release];
        [localException raise];
        [batchOfIdentifiers release];
        [arp release];
      NS_ENDHANDLER

      [sObjects retain];
      [p incrementCurrentValue: [batchOfIdentifiers count]];
      [batchOfIdentifiers release];
      [p setCurrentDescription:@"Writing data"];
      batchSize = [sObjects count];
      if (batchSize > 0 )
        {
          if (firstBatchIteration)
            {
              if ([writer writeFieldsOrdered])
                {
                  [writer setFieldNames: queryFields andWriteThem:YES];
                }
              else
                {
                  [writer setFieldNames: [sObjects objectAtIndex: 0] andWriteThem:YES];
                }
              firstBatchIteration = NO;
            }
          [writer writeDataSet: sObjects];
        }
      [sObjects release];
      [arp release];
    }
  [writer writeEnd];
  [dbSoap release];  
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
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setUpBatchSize:[db upBatchSize]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
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
    resultArray = [dbSoap create:objectName fromArray:sObjectsArray progressMonitor:p];
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
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setUpBatchSize:[db upBatchSize]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
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
    resultArray = [dbSoap update:objectName fromArray:sObjectsArray progressMonitor:p];
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

- (void)getUpdated :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate toWriter:(DBFileWriter *)writer progressMonitor:(id<DBProgressProtocol>)p
{
  NSDictionary   *updatedDict;
  NSArray        *updatedArray;
  NSArray        *keys;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  NS_DURING 
    updatedDict = [dbSoap getUpdated: objectType :startDate :endDate];
  NS_HANDLER
    [dbSoap release];
    [localException raise];
    return;
  NS_ENDHANDLER

  updatedArray = [updatedDict objectForKey:@"updatedRecords"];

  [writer writeStart];
  
  keys = [[updatedArray objectAtIndex: 0] allKeys];
  [writer setFieldNames:[NSArray arrayWithArray:keys] andWriteThem:YES];
    
  [writer writeDataSet:updatedArray];
  [writer writeEnd];
  [dbSoap release];
}


- (void)getDeleted :(NSString *)objectType :(NSDate *)startDate :(NSDate *)endDate toWriter:(DBFileWriter *)writer progressMonitor:(id<DBProgressProtocol>)p
{
  NSDictionary   *deletedDict;
  NSArray        *deletedArray;
  NSArray        *keys;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  NS_DURING 
    deletedDict = [dbSoap getDeleted: objectType :startDate :endDate];
  NS_HANDLER
    [dbSoap release];
    [localException raise];
    return;
  NS_ENDHANDLER
  
  deletedArray = [deletedDict objectForKey:@"deletedRecords"];

  [writer writeStart];
  
  keys = [[deletedArray objectAtIndex: 0] allKeys];
  [writer setFieldNames:[NSArray arrayWithArray:keys] andWriteThem:YES];
    
  [writer writeDataSet:deletedArray];
  [writer writeEnd];
  [dbSoap release];
}

- (void)describeSObject: (NSString *)objectType toWriter:(DBFileWriter *)writer
{
  NSUInteger      i;
  NSUInteger     size;
  DBSObject      *object;
  NSDictionary   *properties;
  NSArray        *fields;
  NSArray        *keys;
  NSMutableArray *set;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  NS_DURING 
    object = [dbSoap describeSObject: objectType];
  NS_HANDLER
    [dbSoap release];
    [localException raise];
    return;
  NS_ENDHANDLER
  
  fields = [object fieldNames];
  size = [fields count];

  [writer writeStart];
  
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
  [writer writeEnd];
  [set release];
  [dbSoap release];
}



- (NSMutableArray *)deleteFromReader:(DBCSVReader *)reader progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *objectsArray;
  NSMutableArray *resultArray;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setUpBatchSize:[db upBatchSize]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  /* retrieve objects to delete */
  // FIXME perhaps this copy is useless
  objectsArray = [[NSMutableArray arrayWithArray:[reader readDataSet]] retain];
  [logger log: LogDebug :@"[DBSoapCSV delete] objects to delete: %@\n", objectsArray];
  [logger log: LogStandard :@"[DBSoapCSV delete] Count of objects to delete: %d\n", [objectsArray count]];

  resultArray = nil;
  NS_DURING
    resultArray = [dbSoap delete:objectsArray progressMonitor:p];
  NS_HANDLER
    [objectsArray release];
    [dbSoap release];
    [localException raise];
  NS_ENDHANDLER

  [dbSoap release];
  [objectsArray release];
  return resultArray;
}

- (NSMutableArray *)undeleteFromReader:(DBCSVReader *)reader progressMonitor:(id<DBProgressProtocol>)p
{
  NSMutableArray *objectsArray;
  NSMutableArray *resultArray;
  DBSoap         *dbSoap;
  
  /* we clone the soap instance and pass the session, so that the method can run in a separate thread */
  dbSoap = [[DBSoap alloc] init];
  [dbSoap setSessionId:[db sessionId]];
  [dbSoap setServerURL:[db serverURL]];
  [dbSoap setUpBatchSize:[db upBatchSize]];
  [dbSoap setLogger:logger];
  [dbSoap setSObjectDetailsDict:[db sObjectDetailsDict]];
  
  /* retrieve objects to undelete */
  // FIXME perhaps this copy is useless
  objectsArray = [[NSMutableArray arrayWithArray:[reader readDataSet]] retain];
  [logger log: LogDebug :@"[DBSoapCSV undelete] objects to undelete: %@\n", objectsArray];
  [logger log: LogStandard :@"[DBSoapCSV undelete] Count of objects to undelete: %d\n", [objectsArray count]];

  resultArray = nil;
  NS_DURING
    resultArray = [dbSoap undelete:objectsArray progressMonitor:p];
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
