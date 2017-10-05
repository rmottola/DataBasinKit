/* -*- mode: objc -*-
   Project: DataBasin

   Copyright (C) 2009-2017 Free Software Foundation

   Author: Riccardo Mottola

   Created: 2009-01-13 00:36:45 +0100 by multix

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

#ifndef DBCSVWRITER_H
#define DBCSVWRITER_H

#import <Foundation/Foundation.h>

#import "DBFileWriter.h"

enum DBCSVLineBreakHandling
{
  DBCSVLineBreakNoChange = 0,
  DBCSVLineBreakDelete,
  DBCSVLineBreakReplaceWithSpace
};
typedef enum DBCSVLineBreakHandling DBCSVLineBreakHandling;

extern NSString *DBFileFormatCSV;

@protocol DBLoggerProtocol;

@interface DBCSVWriter : DBFileWriter
{
  NSString     *separator;
  BOOL         isQualified;
  NSString     *qualifier;
  NSString     *newLine;
  DBCSVLineBreakHandling lineBreakHandling;
}

- (void)setQualifier: (NSString *)q;
- (void)setSeparator: (NSString *)sep;
- (void)setLineBreakHandling: (DBCSVLineBreakHandling)handling;

@end


#endif /* DBCSVWRITER_H */
