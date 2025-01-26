/* -*- mode: objc -*-
  Project: DataBasin

  Copyright (C) 2009-2023 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2009-01-13 00:36:45 +0100 by Riccardo Mottola

  This application is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public
  License as published by the Free Software Foundation; either
  version 2 of the License, or (at your option) any later version.

  This application is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Library General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free
  Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
*/

#import "DBCSVWriter.h"
#import "DBSObject.h"
#import "DBLoggerProtocol.h"
#import "DBSFTypeWrappers.h"

#import <WebServices/GWSConstants.h>

NSString *DBFileFormatCSV = @"CSV";

@implementation DBCSVWriter

- (id)initWithHandle:(NSFileHandle *)fileHandle
{
  if ((self = [super initWithHandle:fileHandle]))
    {
      isQualified = YES;
      qualifier = @"\"";
      separator = @",";
      newLine = @"\n";
      lineBreakHandling = DBCSVLineBreakNoChange;
      [self setStringEncoding: NSUTF8StringEncoding];
   }
  return self;
}

- (void)dealloc
{
  [qualifier release];
  [separator release];
  [super dealloc];
}

- (void)setFileFormat:(NSString *)f
{
}

- (void)setIsQualified: (BOOL)flag
{
  isQualified = flag;
}

- (BOOL)isQualified
{
  return isQualified;
}

- (void)setQualifier: (NSString *)q
{
  if (qualifier != q)
    {
      [qualifier release];
      qualifier = [q retain];
    }
}

- (void)setSeparator: (NSString *)sep
{
  if (separator != sep)
    {
      [separator release];
      separator = [sep retain];
    }
}

- (void)setLineBreakHandling: (DBCSVLineBreakHandling)handling
{
  lineBreakHandling = handling;
}


- (NSString *)formatScalarObject:(id)value
{
  NSString *res;
  NSString *escapedQualifier;

  escapedQualifier = [qualifier stringByAppendingString: qualifier];
  res = nil;
  if ([value isKindOfClass: [NSString class]])
    {
      if (lineBreakHandling != DBCSVLineBreakNoChange)
        {
          NSRange lbRange;
          NSMutableString *mutStr;

          mutStr = [NSMutableString stringWithString:value];
          lbRange = [mutStr rangeOfString:@"\n"];
          while (lbRange.location != NSNotFound)
            {
              if (lineBreakHandling == DBCSVLineBreakDelete)
                [mutStr deleteCharactersInRange:lbRange];
              else if (lineBreakHandling == DBCSVLineBreakReplaceWithSpace)
                [mutStr replaceCharactersInRange:lbRange withString:@" "];
              lbRange = [mutStr rangeOfString:@"\n"];
            }
          value = mutStr;
        }

      if (isQualified)
	{
	  NSMutableString *s;
	      
	  s = [[NSMutableString alloc] initWithCapacity: [value length]+2];

	  [s appendString: qualifier]; 

	  [s appendString: value];

	  [s replaceOccurrencesOfString: qualifier withString: escapedQualifier options:NSLiteralSearch range: NSMakeRange(1, [s length]-1)];
	  [s appendString: qualifier];

	  res = [NSString stringWithString: s];
	  [s release];
	}
      else
	{
	  res = value;
	}
    }
  else if ([value isKindOfClass: [DBSFDataType class]])
    {
      NSLog(@"SF DataTYpe class: %@", [value class]);

      if (isQualified)
	{
	  NSMutableString *s;
	  NSString *strValue;

	  strValue = [value stringValue];
	  s = [[NSMutableString alloc] initWithCapacity: [strValue length]+2];
	  [s appendString: qualifier];
	  [s appendString: strValue];
	  [s appendString: qualifier];
	  res = [NSString stringWithString: s];
	  [s release];
	}
      else
	{
	  res = [value stringValue];
	}
    }
  else if ([value isKindOfClass: [NSNumber class]])
    {
      NSLog(@"number class: %@", [value class]);
      // FIXME: this is locale sensitive?
      // FIXME2: maybe give the option to quote also numbers
      if (isQualified)
	{
	  NSMutableString *s;
	  NSString *strValue;

	  strValue = [value stringValue];
	  s = [[NSMutableString alloc] initWithCapacity: [strValue length]+2];
	  [s appendString: qualifier];
	  [s appendString: strValue];
	  [s appendString: qualifier];
	  res = [NSString stringWithString: s];
	  [s release];
	}
      else
	{
	  res = [value stringValue];
	}
    }
  else
    {
      [logger log: LogStandard :@"[DBCSVWriter formatScalarObject] %@ has unknown class %@:\n", value, [value class]];
    }
  return res;
}



- (NSString *)formatOneLine:(id)data forHeader:(BOOL) headerFlag
{
  NSArray             *array;
  NSMutableString     *theLine;
  unsigned            size;
  unsigned            i;
  id                  obj;
  NSMutableArray      *keyOrder;
  NSMutableDictionary *dataDict;

  if (data == nil)
    return nil;

  /* if we have just a single object, we fake an array */
  if([data isKindOfClass: [NSArray class]])
    array = data;
  else
    array = [NSArray arrayWithObject: data];

  //NSLog(@"Data array: %@", data);
  //NSLog(@"field names array: %@", fieldNames);
  size = [array count];

  if (size == 0)
    return nil;


  keyOrder = [[NSMutableArray alloc] initWithCapacity:[array count]];
  dataDict = [[NSMutableDictionary alloc] initWithCapacity:[array count]];

  for (i = 0; i < size; i++)
    {
      obj = [array objectAtIndex:i];
      if ([obj isKindOfClass: [NSDictionary class]])
        {
          [self formatComplexObject:obj withRoot:nil inDict:dataDict inOrder:keyOrder];
        }
      else if ([obj isKindOfClass: [DBSObject class]])
        {
	  NSArray *keys;
	  unsigned j;

	  keys = [obj fieldNames];

          for (j = 0; j < [keys count]; j++)
            {
	      NSString *key;
	      id value;

	      key = [keys objectAtIndex: j];
	      value = [obj valueForField: key];
	      //NSLog(@"key ---> %@ object %@", key, value);

	      // If we have a subitem array of one we can attempt to explode it
	      // write ordered will have issues though
	      if ([value isKindOfClass: [NSArray class]])
		{
		  NSArray *a;

		  a = (NSArray *)value;
		  if ([a count] == 1)
		    {
		      value = [a objectAtIndex:0];
		    }
		}

	      
	      if ([value isKindOfClass: [DBSFDataType class]])
		{
                  NSString *s;

                  s = [value stringValue];
                  if (nil == s)
                    s = @"";
                  [dataDict setObject:s forKey:key];
                  [keyOrder addObject:key];
		}
	      else if ([value isKindOfClass: [NSString class]] ||[value isKindOfClass: [NSNumber class]] )
		{
                  [dataDict setObject:value forKey:key];
                  [keyOrder addObject:key];
		}
	      else if ([value isKindOfClass: [NSDictionary class]])
		{
		  [self formatComplexObject:value withRoot:key inDict:dataDict inOrder:keyOrder];
		}
	      else if ([value isKindOfClass: [DBSObject class]])
		{
		  [self formatSObject:value withRoot:key inDict:dataDict inOrder:keyOrder];
		}
              else if ([value isKindOfClass: [NSArray class]])
		{
		  NSString *s;

		  s = [NSString stringWithFormat:@"%lu subitems", (unsigned long)[(NSArray *)value count]];
		  [dataDict setObject:s forKey:key];
                  [keyOrder addObject:key];
		}
	      else
		{
		  NSLog(@"DBCSVWriter - formatOneLine - unknown class for object %@ of class %@ inside DBSObject", value, [value class]);
		}
	    }
	}
      else if ([obj isKindOfClass: [DBSFDataType class]])
        {
	  //NSLog(@"formatOneLine, we have directly a scalar object, DBSFDataType: %@", obj);
          [dataDict setObject:obj forKey:obj];
          [keyOrder addObject:obj];
        }
      else if ([obj isKindOfClass: [NSString class]])
        {
	  //NSLog(@"formatOneLine, we have directly a scalar object, NSString: %@", obj);
          [dataDict setObject:obj forKey:obj];
          [keyOrder addObject:obj];
        }
      else if ([obj isKindOfClass: [NSNumber class]])
	{
          NSLog(@"formatOneLine, we have directly a scalar object, NSNumber: %@", obj);
          [logger log: LogStandard :@"[DBCSVWriter formatOneLine] we have a NSNumber, unhandled %@:\n", obj];
	}
      else
	{
	  [logger log: LogStandard :@"[DBCSVWriter formatOneLine] unknown class of value %@:\n", [obj class]];
	  NSLog(@"[DBCSVWriter formatOneLine] unknown class of value: %@", [obj class]);
	}
    }

  /* create the string */
  theLine = [[NSMutableString alloc] initWithCapacity:64];

  if (writeOrdered)
    {
      for (i = 0; i < [fieldNames count]; i++)
        {
          unsigned j;
          NSString *key;
          NSString *originalKey;
          NSString *valStr;

          /* look for original key name for correct capitalization */
          key = [fieldNames objectAtIndex:i];
          originalKey = nil;
          j = 0;
	  //NSLog(@"lookingfor -> %@", key);
          while (j < [keyOrder count] && originalKey == nil)
            {
              originalKey = [keyOrder objectAtIndex:j];
              if ([originalKey compare:key options:NSCaseInsensitiveSearch] != NSOrderedSame)
                originalKey = nil;
              j++;
            }
	  //NSLog(@"original key: %@", originalKey);
	  valStr = nil;
          if (headerFlag)
            {
              valStr = [self formatScalarObject: key];
            }
          else
            {
	      if (originalKey)
		{
		  id val;

		  val = [dataDict objectForKey: originalKey];
		  if (val)
		    {
		      valStr = [self formatScalarObject: val];
		    }
		  else
		    {
		      /* we found the key but no corresponding value
			 we insert an empty string to keep the column sequence */
		      valStr = [self formatScalarObject: @""];
		    }
		}
	      else
		{
		  /* we no corresponding key, possibly referencing a null complex object
		     we insert an empty string to keep the column sequence */
		  valStr = [self formatScalarObject: @""];
		}
            }

          [theLine appendString:valStr];
          if (i < [fieldNames count]-1)
            [theLine appendString: separator];
        }
    }
  else
    {
      for (i = 0; i < [keyOrder count]; i++)
        {
          NSString *k;
          id        val;
          NSString *valStr;
          
          valStr = nil;
          k = [keyOrder objectAtIndex: i];
          if (headerFlag)
            {
              valStr = [self formatScalarObject: k];
            }
          else
            {
              val = [dataDict objectForKey: k];
              if (val)
                {
                  valStr = [self formatScalarObject: val];
                }
            }
          [theLine appendString:valStr];
          if (i < [keyOrder count]-1)
            [theLine appendString: separator];
        }
    }

  [keyOrder release];
  [dataDict release];
  [theLine appendString:newLine];
  return [theLine autorelease];
}

@end
