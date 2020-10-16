/* -*- mode: objc -*-
   Project: DataBasinKit

   Copyright (C) 2017 Free Software Foundation

   Author: Riccardo Mottola

   Created: 2017-10-11 Riccardo Mottola

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

- (id) initWithSFString:(NSString *)str
{
  NSLog(@"Subclass responsibility - initWithSFString");
  return nil;
}

- (NSString *)stringValue
{
  NSLog(@"Subclass responsibility - stringValue");
  return nil;
}

@end 

@implementation DBSFBoolean


+ (DBSFBoolean *)sfBooleanWithBool:(BOOL)val
{
  return [[[DBSFBoolean alloc] initWithBool:val] autorelease];
}

- (id)initWithString:(NSString *)str
{

  BOOL v;

  v = NO;
  if ([str caseInsensitiveCompare:@"true"] == NSOrderedSame)
    v = YES;
  else if ([str caseInsensitiveCompare:@"yes"] == NSOrderedSame)
    v = YES;

  self = [self initWithBool:v];
  
  return self;
}

- (id)initWithSFString:(NSString *)str
{
  return [self initWithString:str];
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


+ (DBSFInteger *) sfIntegerWithInteger: (NSInteger)val
{
  return [[[DBSFInteger alloc] initWithInteger:val] autorelease];
}

- (DBSFInteger *) initWithString:(NSString *)str
{
  NSInteger i;

  i = [str integerValue];
  self = [self initWithInteger:i];
  return self;
}

- (id)initWithSFString:(NSString *)str
{
  return [self initWithString:str];
}

- (id) initWithInteger: (NSInteger)val
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

+ (DBSFDouble*) sfDoubleWithString: (NSString *)str
{
  double d;
  
  d = [str doubleValue];
  return [self sfDoubleWithDouble: d];
}

+ (DBSFDouble*) sfDoubleWithDouble: (double)val
{
  return [[[DBSFDouble alloc] initWithDouble:val] autorelease];
}

- (DBSFDouble *) initWithString:(NSString *)str
{
  double d;
  
  d = [str doubleValue];
  self = [self initWithDouble:d];
  return self;
}

- (DBSFDouble *) initWithSFString:(NSString *)str
{
  double d;
  
  d = [str doubleValue];
  self = [self initWithDouble:d];
  return self;
}


- (id) initWithDouble: (double)val
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

- (NSString *)stringValue
{
  return [value stringValue];
}

@end

@implementation DBSFPercentage



+ (DBSFPercentage*) sfPercentageWithDouble: (double)val
{
  return [[[DBSFPercentage alloc] initWithDouble:val] autorelease];
}

- (id) initWithString: (NSString *)str
{
  if (str && [str length])
    {
      double d;
      NSRange rangeOfPercent;

      rangeOfPercent = [str rangeOfString:@"%"];
      if (rangeOfPercent.location != NSNotFound)
        str = [str substringToIndex:rangeOfPercent.location];
      d = [str doubleValue];
      self =  [self initWithDouble: d];
    }
  return self;
}

- (id) initWithSFString: (NSString *)str
{
  if (str && [str length])
    {
      double d;
      
      d = [str doubleValue];
      self =  [self initWithDouble: d];
    }
  return self;
}


- (NSString *)stringValue
{
  NSString *s;

  s = [value stringValue];
  s = [s stringByAppendingString:@" %"];
  return s;
}

@end

@implementation DBSFCurrency

+ (DBSFCurrency*) sfCurrencyWithString: (NSString *)str
{
  double d;
  
  d = [str doubleValue];
  return [self sfCurrencyWithDouble: d];
}


+ (DBSFCurrency*) sfCurrencyWithDouble: (double)val
{
  return [[[DBSFCurrency alloc] initWithDouble:val] autorelease];
}

@end


@implementation DBSFDateTime


- (void)dealloc
{
  [date release];
  [super dealloc];
}



+ (DBSFDateTime *)sfDateWithDate: (NSDate *)val
{
  return [[[DBSFDate alloc] initWithDate:val] autorelease];
}

- (id)initWithString:(NSString *)str
{
  NSDate *d;

  d = nil;
  if (str)
    {
      d = [NSDate dateWithString:str];
      self = [self initWithDate:d];
    }

  return self;
}

- (id)initWithSFString:(NSString *)str
{
  NSDate *d;
  NSRange rangeOfT;

  d = nil;
  rangeOfT = [str rangeOfString:@"T"];
  if (rangeOfT.location != NSNotFound)
    {
      NSString *sD, *sT;
      NSString *s;
    
      sD = [str substringToIndex:rangeOfT.location];
      sT = [str substringFromIndex:rangeOfT.location + 1];
      sT = [sT substringToIndex:8];
      //      NSLog(@"|%@| |%@|", sD, sT);
      s = [NSString stringWithFormat:@"%@ %@ +0000", sD, sT];
      d = [NSDate dateWithString:s];
      self = [self initWithDate:d];
    }

  return self;
}


- (id) initWithDate: (NSDate *)value
{
  if ((self = [super init]))
    {
      date = value;
      [date retain];
    }
  return self;
}

- (NSDate *) dateValue
{
  return date;
}

- (NSString *)stringValue
{
  NSString *s;

  s = nil;
  if (date)
    {
      s = [date description];
    }
  return s;
}


@end


@implementation DBSFDate

- (id)initWithString:(NSString *)str
{
  NSDate *d;

  d = [NSDate dateWithString:str];
  self = [self initWithDate:d];
  return self;
}

- (id)initWithSFString:(NSString *)str
{
  NSDate *d;
  NSString *s;

  s = [str stringByAppendingString:@" 00:00:00 +0000"];
  d = [NSDate dateWithString:s];
  self = [self initWithDate:d];
  return self;
}

- (NSString *)stringValue
{
  NSString *s;
  NSCalendarDate *cd;

  s = nil;
  if (date)
    {
      cd = [NSCalendarDate dateWithTimeIntervalSince1970:[date timeIntervalSince1970]];
      s = [cd descriptionWithCalendarFormat:@"%Y-%m-%d"];
    }
  return s;
}



@end

