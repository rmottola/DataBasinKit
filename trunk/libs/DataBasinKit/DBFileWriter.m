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


- (void)setWriteFieldsOrdered:(BOOL)flag
{
  writeOrdered = flag;
}


- (BOOL)writeFieldsOrdered
{
  return writeOrdered;
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

- (NSString *)formatOneLine:(id)data forHeader:(BOOL) headerFlag
{
  NSLog(@"DBFileWriter - formatOneLine: forHeader: - method should be subclassed");
  return nil;
}

@end
