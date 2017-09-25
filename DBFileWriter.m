/* -*- mode: objc -*-
 Project: DataBasin
 
 Copyright (C) 2009-2014 Free Software Foundation
 
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


@end
