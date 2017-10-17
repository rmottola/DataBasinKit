/* -*- mode: objc -*-
   Project: DataBasinKit

   Copyright (C) 2017 Free Software Foundation

   Author: Riccardo Mottola

   Created: 2017-10-11

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

#import "DBSFTypeWrappers.h"

@implementation DBSFDataType
@end 

@implementation DBSFBoolean


+ (DBSFBoolean *)sfBooleanWithString:(NSString *)str
{
  return [[[DBSFBoolean alloc] initWithString:str] autorelease];
}

- (id)initWithString:(NSString *)str
{

  BOOL v;

  v = NO;
  if ([str caseInsensitiveCompare:@"true"] == NSOrderedSame)
    v = YES;
  else if ([str caseInsensitiveCompare:@"yes"] == NSOrderedSame)
    v = YES;

  NSLog(@"init Boolean %@, %d", str, v);
  [self initWithBool:v];
  
  return self;
}

- (id) initWithBool: (BOOL)val
{
  if ((self = [super init]))
    {
      value = val;
    }
  return self;
}

- (BOOL) boolValue
{
  return value;
}


- (NSString *)stringValue
{
  BOOL v;
  NSLog(@"Boolean stringValue %d", [self boolValue]);
  v = [self boolValue];
  if (v)
    return @"Yes";
  return @"No";
}

@end


@implementation DBSFInteger

@end


@implementation DBSFDouble

@end


@implementation DBSFCurrency

@end


@implementation DBSFDate

@end


@implementation DBSFDateTime

@end

