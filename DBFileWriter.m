/* -*- mode: objc -*-
 Project: DataBasin
 
 Copyright (C) 2009-2017 Free Software Foundation
 
 Author: Riccardo Mottola
 
 Created: 2017-09-20
 
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

#import "DBFileWriter.h"
#import "DBSObject.h"
#import "DBLoggerProtocol.h"

#import <WebServices/GWSConstants.h>

@implementation DBFileWriter

- (id)initWithHandle:(NSFileHandle *)fileHandle
{
  if ((self = [super init]))
    {
      file = fileHandle;
      fieldNames = nil;
    }
  return self;
}


- (void)dealloc
{
  [fieldNames release];
  [super dealloc];
}


- (void)setLogger:(id<DBLoggerProtocol>)l
{
  logger = l;
}


- (void)setStringEncoding: (NSStringEncoding) enc
{
  NSData *tempData;

  encoding = enc;
  bomLength = 0;

  /* BOM heuristics */
  tempData = [@" "dataUsingEncoding: encoding];
#if defined(__APPLE__) && (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)
  NSString *blankString;
    
  blankString = [[[NSString alloc] initWithBytes: [tempData bytes] length: [tempData length] encoding: encoding] autorelease];
  NSLog(@"blank string: %@", blankString);
  tempData = [tempData subdataWithRange: NSMakeRange(0, [tempData length] - [blankString length])];
#else
  tempData = [tempData subdataWithRange: NSMakeRange(0, [tempData length] - [@" " lengthOfBytesUsingEncoding: encoding])];
#endif
  bomLength = [tempData length];

  NSLog(@"bom length: %u", bomLength);
}

- (void)setWriteFieldsOrdered:(BOOL)flag
{
  writeOrdered = flag;
}


- (BOOL)writeFieldsOrdered
{
  return writeOrdered;
}

/*
 This methods sets the internal field names for the header when using ordered object writeout.
 */
- (void)setFieldNames:(id)obj andWriteThem:(BOOL)flag
{
  NSArray *array;
  
  [logger log: LogDebug :@"[DBHTMLWriter setFieldNames] Object: %@:\n", obj];
  
  /* if we have no data, we return */
  if (obj == nil)
    return;
  
  /* if we have just a single object, we fake an array */
  if([obj isKindOfClass: [NSArray class]])
    array = obj;
  else
    array = [NSArray arrayWithObject: obj];
  
  if ([array count] == 0)
    return;
  
  if (fieldNames != array)
    {
      [fieldNames release];
      fieldNames = array;
      [array retain];
    }
  
  [logger log: LogDebug :@"[DBHTMLWriter setFieldNames] Names: %@:\n", array];
  
  /* if we write the header, fine, else we write at least the BOM */
  if (flag == YES)
    {
      NSString *theLine;
    
      theLine = [self formatOneLine:array forHeader:YES];
      [file writeData: [theLine dataUsingEncoding: encoding]];
    }
  else
    {
      NSData *tempData;
    
      tempData = [@" "dataUsingEncoding: encoding];
      tempData = [tempData subdataWithRange: NSMakeRange(0, bomLength)];
      [file writeData: tempData];
    }
}

- (void)writeStart
{

}

- (void)writeEnd
{

}

- (void)writeDataSet:(NSArray *)array
{
  NSUInteger i;
  NSUInteger setCount;
  NSAutoreleasePool *arp;
  
  if (array == nil)
    return;
  
  arp = [[NSAutoreleasePool alloc] init];
  setCount = [array count];
  for (i = 0; i < setCount; i++)
    {
      NSString *oneLine;
      NSData *data;
      NSData *data2;
      id o;

      o = [array objectAtIndex:i];
      if ([o isKindOfClass: [DBSObject class]])
	o = [NSArray  arrayWithObject: o];
      oneLine = [self formatOneLine:o forHeader:NO];
      data = [oneLine dataUsingEncoding: encoding];
      if (bomLength > 0)
	data2 = [NSData dataWithBytesNoCopy: (void *)[data bytes] length: [data length]-bomLength freeWhenDone: NO];
      else
	data2 = data;
      [file writeData: data2];
    }
  [arp release];
}


- (void)formatComplexObject:(NSMutableDictionary *)d withRoot:(NSString *)root inDict:(NSMutableDictionary *)dict inOrder:(NSMutableArray *)order
{
  NSMutableArray  *keys;
  unsigned i;
  NSString *extendedFieldName;

  if (!d)
    return;

  keys = [NSMutableArray arrayWithArray:[d allKeys]];
  [keys removeObject:GWSOrderKey];
  
  /* remove some fields which get added automatically by salesforce even if not asked for */
  [keys removeObject:@"type"];
  
  /* remove Id only if it is null, else an array of two populated Id is returned by SF */
  if (![[d objectForKey:@"Id"] isKindOfClass: [NSArray class]])
    [keys removeObject:@"Id"];

  //[logger log: LogDebug :@"[DBCSVWriter formatComplexObject] clean dictionary %@:\n", d];
  //NSLog(@"[DBCSVWriter formatComplexObject] clean dictionary %@\n", d);

  for (i = 0; i < [keys count]; i++)
    {
      id obj;
      NSString *key;
      
      key = [keys objectAtIndex: i];
      obj = [d objectForKey: key];
      if ([key isEqualToString:@"Id"])
	obj = [obj objectAtIndex: 0];
      
      if ([obj isKindOfClass: [NSDictionary class]])
        {
          NSMutableString *s;

          if (root)
            s = [NSMutableString stringWithString:root];
          else
            s = [NSMutableString stringWithString:@""];

          if (root)
            [s appendString:@"."];
          [s appendString:key];

          //NSLog(@"formatting complex object with root: %@", s);
          [self formatComplexObject: obj withRoot:s inDict:dict inOrder:order];
        }
      else if ([obj isKindOfClass: [NSString class]] || [obj isKindOfClass: [NSNumber class]])
        {
	  NSMutableString *s;

          if (root)
            s = [NSMutableString stringWithString:root];
          else
            s = [NSMutableString stringWithString:@""];

          if (root)
            [s appendString:@"."];

          [s appendString:key];

          extendedFieldName = s;
          //NSLog(@"formatting scalar object: %@ for key: %@", obj,extendedFieldName);
          [dict setObject:obj forKey:extendedFieldName];
          [order addObject:extendedFieldName];
	}
      else
	NSLog(@"[DBFileWriter formatComplexObject] unknown class of value: %@, object: %@", [obj class], obj);
      
    }
}


- (NSString *)formatOneLine:(id)data forHeader:(BOOL) headerFlag
{
  NSLog(@"DBFileWriter - formatOneLine: forHeader: - method should be subclassed");
  return nil;
}

@end
