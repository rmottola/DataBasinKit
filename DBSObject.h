/** -*- mode: objc -*-
 Project: DataBasin
 DBSobject.h
 
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
 Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */


#import <Foundation/Foundation.h>

#if defined(__APPLE__) && (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)
#ifndef NSUInteger
#define NSUInteger unsigned int
#endif
#ifndef NSInteger
#define NSInteger int
#endif
#endif

#ifndef ASSIGN
#define ASSIGN(object,value)    ({\
  id __object = object; \
  object = [(value) retain]; \
  [__object release]; \
})
#endif


@class DBSoap;

@interface DBSObject : NSObject <NSCopying>
{
  DBSoap  *dbs; /* not retained */

  NSMutableDictionary *recordValues;
  NSMutableArray      *fieldNames;
  NSMutableDictionary *fieldProperties;
  NSMutableDictionary *objectProperties;
  NSArray             *recordTypes;
}

/** returns the 18-char version of the 15-char id */
+ (NSString *)idTo18: (NSString *) id15;

/** returns the salesforce Id of the object in whichever format it is */
- (NSString *)sfId;

/** returns the salesforce Id of the object, always in the 15-char case-sensitive version */
- (NSString *)sfId15;

/** returns the salesforce Id of the object, always in the 18-char case-insensitive version */
- (NSString *)sfId18;

/** sets the properties of the object itself */
- (void)setObjectProperties: (NSDictionary *)properties;

/** returns the properties of the object itself, like its name */
- (NSDictionary *)objectProperties;

/** Set the soap database interface (not retained) */
- (void)setDBSoap: (DBSoap *)db;

/** returns the soap database interface */
- (DBSoap *)DBSoap;

/** shortcut to return the property "name" */
- (NSString *)name;

  /** shortcut to return the property "type" */
- (NSString *)type;

/** shortcut to return the property "label" */
- (NSString *)label;

/** shortcut to return the property "keyPrefix" */
- (NSString *)keyPrefix;

- (void)setProperties: (NSDictionary *)properties forField: (NSString *)field;
- (NSDictionary *)propertiesOfField: (NSString *)field;

/** removes a field and its properties */
- (void)removeField: (NSString *)field;

- (NSArray *)fieldNames;
- (id)valueForField: (NSString *)field;
- (void)setValue: (id)value forField:(NSString *)field;

- (void)setRecordTypes: (NSArray *)rtInfo;

/** returns information about the Object RecordTypes */
- (NSArray *)recordTypes;

/** <p>Loads or refreshes the value of all known fields to the object.</p>
 *  <p>If the object is instantiated as a result of a describe, it will load all values.</p>
 *  <p>The object needs to have a valid <em>DBSoap</em> instance set </p>
 */
- (void)loadFieldValues;

/** <p>Loads or refreshes the value of the fields passed in the array.</p>
 */
- (void)loadValuesForFields:(NSArray *)namesArray;

/** <p>Stores by updating the value of the fields passed in the array.</p>
 */
- (void)storeValuesForFields:(NSArray *)namesArray;

@end
