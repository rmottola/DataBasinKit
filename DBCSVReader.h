/* -*- mode: objc -*-
  Project: DataBasin

  Copyright (C) 2009-2014 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2009-06-24 22:34:06 +0200 by Riccardo Mottola

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


#import <Foundation/Foundation.h>

#if defined(__APPLE__) && (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)
#ifndef NSUInteger
#define NSUInteger unsigned int
#endif
#ifndef NSInteger
#define NSInteger int
#endif
#endif

@protocol DBLoggerProtocol;

@interface DBCSVReader : NSObject
{
  id<DBLoggerProtocol> logger;
  NSArray      *fieldNames;
  NSArray      *fieldTypes;
  NSString     *separator;
  BOOL         isQualified;
  NSString     *qualifier;
  NSString     *newLine;
  NSArray      *linesArray;
  int          currentLine;
}

- (void)setLogger:(id<DBLoggerProtocol>)l;
- (id)initWithPath:(NSString *)filePath withLogger:(id<DBLoggerProtocol>)l;
- (id)initWithPath:(NSString *)filePath byParsingHeaders:(BOOL)parseHeader withLogger:(id<DBLoggerProtocol>)l;
- (void)parseHeaders;
- (void)setQualifier: (NSString *)q;
- (void)setSeparator: (NSString *)sep;
- (NSArray *)fieldNames;
- (NSArray *)readDataSet;
- (NSArray *)decodeOneLine:(NSString *)line;
- (NSString *)readLine;

@end


