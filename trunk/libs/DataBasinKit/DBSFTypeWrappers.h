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

#ifndef _DBSFTYPEWRAPPERS_H_
#define _DBSFTYPEWRAPPERS_H_

#import <Foundation/Foundation.h>

@interface DBSFDataType : NSObject
{
}

- (id) initWithString:(NSString *)str;
- (id) initWithSFString:(NSString *)str;
- (NSString *)stringValue;

@end


@interface DBSFBoolean : DBSFDataType
{
  BOOL value;
}

+ (DBSFBoolean *) sfBooleanWithBool: (BOOL)val;
- (id) initWithBool: (BOOL)val;
- (BOOL) boolValue;

@end

@interface DBSFInteger : DBSFDataType
{
  NSNumber *value;
}

+ (DBSFInteger *) sfIntegerWithInteger: (NSInteger)val;
- (id) initWithInteger: (NSInteger)val;
- (NSInteger) integerValue;

@end

@interface DBSFDouble : DBSFDataType
{
  NSNumber *value;
}

+ (DBSFDouble *) sfDoubleWithDouble: (double)val;
- (id) initWithDouble: (double)val;
- (double) doubleValue;
@end

@interface DBSFPercentage : DBSFDouble
{
  
}

+ (DBSFPercentage*) sfPercentageWithDouble: (double)val;


@end


@interface DBSFCurrency : DBSFDouble
{

}

+ (DBSFCurrency*) sfCurrencyWithDouble: (double)val;


@end

@interface DBSFDateTime : DBSFDataType
{
  NSDate *date;
}

+ (DBSFDateTime *)sfDateWithDate: (NSDate *)val;
- (id) initWithDate: (NSDate *)value;
- (NSDate *) dateValue;

@end

@interface DBSFDate : DBSFDateTime
{
}

@end



#endif // _DBSFTYPEWRAPPERS_H_

