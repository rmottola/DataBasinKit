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

- (id) initWithString:(NSString *)str
{
  NSLog(@"Subclass responsibility - initWithString");
  return nil;
}

- (NSString *)stringValue
{
  NSLog(@"Subclass responsibility - initWithString");
  return nil;
}

@end 

@implementation DBSFBoolean


+ (DBSFBoolean *)sfBooleanWithString:(NSString *)str
{
  return [[[DBSFBoolean alloc] initWithString:str] autorelease];
}

+ (DBSFBoolean *)sfBooleanWithBool:(BOOL)v
{
  return [[[DBSFBoolean alloc] initWithBool:v] autorelease];
}

- (id)initWithString:(NSString *)str
{

  BOOL v;

  v = NO;
  if ([str caseInsensitiveCompare:@"true"] == NSOrderedSame)
    v = YES;
  else if ([str caseInsensitiveCompare:@"yes"] == NSOrderedSame)
    v = YES;

  [self initWithBool:v];
  
  return self;
}

- (DBSFBoolean *) initWithBool: (BOOL)val
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

  v = [self boolValue];
  if (v)
    return @"Yes";
  return @"No";
}

@end


@implementation DBSFInteger

- (void)dealloc
{
  [value release];
  [super dealloc];
}

+ (DBSFInteger*) sfIntegerWithString: (NSString *)str
{
  NSInteger i;

  i = [str integerValue];
  return [self sfIntegerWithInteger: i];
}

+ (DBSFInteger *) sfIntegerWithInteger: (NSInteger)val
{
  return [[[DBSFInteger alloc] initWithInteger:val] autorelease];
}

- (DBSFInteger *) initWithString:(NSString *)str
{
  NSInteger i;

  i = [str integerValue];
  [self initWithInteger:i];
  return self;
}

- (DBSFInteger *) initWithInteger: (NSInteger)val
{
  if ((self = [super init]))
    {
      value = [[NSNumber alloc] initWithInteger:val];
    }
  return self;
}

- (NSInteger) integerValue
{
  return [value integerValue];
}


- (NSString *)stringValue
{
  return [value stringValue];
}

@end


@implementation DBSFDouble

+ (DBSFDouble*) sfDoubleWithDouble: (double)val
{
  return [[[DBSFDouble alloc] initWithDouble:val] autorelease];
}

- (DBSFDouble *) initWithDouble: (double)val
{
  if ((self = [super init]))
    {
      value = [[NSNumber alloc] initWithDouble:val];
    }
  return self;
}

- (double) doubleValue
{
  return [value doubleValue];
}

@end


@implementation DBSFCurrency

+ (DBSFCurrency*) sfCurrencyWithDouble: (double)val
{
  return [[[DBSFCurrency alloc] initWithDouble:val] autorelease];
}

@end


@implementation DBSFDate

@end


@implementation DBSFDateTime

@end

