/* -*- mode: objc -*-
 Project: DataBasin
 
 Copyright (C) 2016 Free Software Foundation
 
 Author: Riccardo Mottola
 
 Created: 2016-10-10
 
 This application is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.
 
 This application is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Library General Public License for more details.
 
 You should have received a copy of the GNU General Public
 License along with this library; if not, write to the Free
 Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
 */

#import <Foundation/Foundation.h>

@protocol DBLoggerProtocol;

@interface DBHTMLWriter : NSObject
{
  id<DBLoggerProtocol> logger;
  NSArray      *fieldNames;
  NSArray      *fieldTypes;
  NSFileHandle *file;
  NSStringEncoding encoding;
  unsigned     bomLength;
}

- (id)initWithHandle:(NSFileHandle *)fileHandle;
- (void)setLogger:(id<DBLoggerProtocol>)l;
- (void)setFieldNames: (id)obj andWriteThem: (BOOL)flag;
- (void)writeDataSet:(NSArray *)array;
- (NSString *)formatOneLine:(id)data forHeader:(BOOL) headerFlag;
- (void)setStringEncoding: (NSStringEncoding) enc;


@end
