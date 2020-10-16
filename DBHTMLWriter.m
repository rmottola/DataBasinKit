/* -*- mode: objc -*-
 Project: DataBasin
 
 Copyright (C) 2016-2017 Free Software Foundation
 
 Author: Riccardo Mottola
 
 Created: 2016-10-10 Riccardo Mottola
 
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
 Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 Boston, MA 02111 USA.
 */

#import "DBHTMLWriter.h"
#import "DBSObject.h"
#import "DBLoggerProtocol.h"
#import "DBSFTypeWrappers.h"

#import <WebServices/GWSConstants.h>

NSString *DBFileFormatXLS = @"XLS";
NSString *DBFileFormatHTML = @"HTML";

@implementation DBHTMLWriter

- (id)initWithHandle:(NSFileHandle *)fileHandle
{
  if ((self = [super initWithHandle:fileHandle]))
    {
      format = DBFileFormatXLS;
      newLine = @"\n";
      [self setStringEncoding: NSUTF8StringEncoding];
    }
  return self;
}

- (void)dealloc
{
  [super dealloc];
}

- (void)setFileFormat:(NSString *)f
{
  format = f;
}

- (NSString *)format
{
  return format;
}

- (NSString *)formatScalarObject:(id)value forHeader:(BOOL) headerFlag
{
  NSString *res;
  NSString *tagBegin;
  NSString *tagEnd;
  NSString *tagBreak;

  tagBreak = nil;
  tagBegin = nil;
  tagEnd = nil;
  if (format == DBFileFormatHTML)
    {
      tagBreak = @"<br>";
    }
  else if (format == DBFileFormatXLS)
    {
      tagBreak = @"<br style=\"mso-data-placement:same-cell;\">";
    }
  
  res = nil;
  if (headerFlag)
    tagEnd = @"</th>";
  else
    tagEnd = @"</td>";
  if ([value isKindOfClass: [NSString class]])
    {
      NSMutableString *s;
      
      if (headerFlag)
        tagBegin = @"<th>";
      else
        {
          if (format == DBFileFormatXLS)
            tagBegin = @"<td style=\"vnd.ms-excel.numberformat:@\">";
          else
            tagBegin = @"<td>";
        }

      /* perform some replacements */
      {
        NSRange chRange;
        NSMutableString *mutStr;

        mutStr = [NSMutableString stringWithString:value];
        chRange = [mutStr rangeOfString:@"&"];
        while (chRange.location != NSNotFound)
          {
            [mutStr replaceCharactersInRange:chRange withString:@"&amp;"];
            if (chRange.location < [mutStr length]-1)
              chRange = [mutStr rangeOfString:@"&" options:0 range:NSMakeRange(chRange.location+1, [mutStr length]-(chRange.location+1))];
            else
              chRange.location = NSNotFound;
          }
        chRange = [mutStr rangeOfString:@"<"];
        while (chRange.location != NSNotFound)
          {
            [mutStr replaceCharactersInRange:chRange withString:@"&lt;"];
            chRange = [mutStr rangeOfString:@"<"];
          }
        chRange = [mutStr rangeOfString:@">"];
        while (chRange.location != NSNotFound)
          {
            [mutStr replaceCharactersInRange:chRange withString:@"&gt;"];
            chRange = [mutStr rangeOfString:@">"];
          }
        chRange = [mutStr rangeOfString:@"\n"];
        while (chRange.location != NSNotFound)
          {
            [mutStr replaceCharactersInRange:chRange withString:tagBreak];
            chRange = [mutStr rangeOfString:@"\n"];
          }
        value = mutStr;
      }

  
      s = [[NSMutableString alloc] initWithCapacity: [value length]];

      [s appendString: tagBegin]; 
      [s appendString: value];
      [s appendString: tagEnd];

      res = [NSString stringWithString: s];
      [s release];
    }
  else if ([value isKindOfClass: [NSNumber class]] ||
           [value isKindOfClass: [DBSFInteger class]] ||
           [value isKindOfClass: [DBSFDouble class]] ||
           [value isKindOfClass: [DBSFPercentage class]] ||
           [value isKindOfClass: [DBSFCurrency class]])
    {
      if (headerFlag)
        tagBegin = @"<th>";
      else
        {
          if (format == DBFileFormatXLS)
            tagBegin = @"<td style=\"vnd.ms-excel.numberformat:General\">";
          else
            tagBegin = @"<td>";
        }

      // FIXME: this is locale sensitive?
      // FIXME2: maybe give the option to quote also numbers
	{
	  NSMutableString *s;
	  NSString *strValue;

	  strValue = [value stringValue];
	  s = [[NSMutableString alloc] initWithCapacity: [strValue length]+2];

          [s appendString: tagBegin];
	  [s appendString: strValue];
          [s appendString: tagEnd];
          
	  res = [NSString stringWithString: s];
	  [s release];
	}
    }
  else if ([value isKindOfClass: [DBSFDataType class]])
    {
      NSMutableString *s;
      NSString *strValue;
    
      if (headerFlag)
        tagBegin = @"<th>";
      else
        {
          if (format == DBFileFormatXLS)
            tagBegin = @"<td style=\"vnd.ms-excel.numberformat:@\">";
          else
            tagBegin = @"<td>";
        }
    
      strValue = [value stringValue];
      s = [[NSMutableString alloc] initWithCapacity:5];
    
      [s appendString: tagBegin]; 
      [s appendString: strValue];
      [s appendString: tagEnd];
      
      res = [NSString stringWithString: s];
      [s release];
    }
  else
    {
      [logger log: LogStandard :@"[DBHTMLWriter formatScalarObject] %@ has unknown class %@:\n", value, [value class]];
    }
  return res;
}





- (void)writeStart
{
  NSData *data;
  NSString *str;

  str = @"<html>";
  data = [str dataUsingEncoding: encoding];
  [file writeData: data];

  str = @"<body>";
  data = [str dataUsingEncoding: encoding];
  [file writeData: data];
  
  str = @"<table>";
  data = [str dataUsingEncoding: encoding];
  [file writeData: data];
}

- (void)writeEnd
{
  NSData *data;
  NSString *str;

  str = @"</table>";
  data = [str dataUsingEncoding: encoding];
  [file writeData: data];

  str = @"</body>";
  data = [str dataUsingEncoding: encoding];
  [file writeData: data];
  
  str = @"</html>";
  data = [str dataUsingEncoding: encoding];
  [file writeData: data];
}



- (NSString *)formatOneLine:(id)data forHeader:(BOOL) headerFlag
{
  NSArray             *array;
  unsigned            size;
  unsigned            i;
  id                  obj;
  NSMutableArray      *keyOrder;
  NSMutableDictionary *dataDict;
  NSMutableString     *theLine;
  
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
	    
            if ([value isKindOfClass: [DBSFDataType class]])
	      {
		[dataDict setObject:value forKey:key];
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
            else if ([value isKindOfClass: [NSArray class]])
              {
                NSString *s;

                s = [NSString stringWithFormat:@"%lu subitems", (unsigned long)[(NSArray *)value count]];
                [dataDict setObject:s forKey:key];
                [keyOrder addObject:key];
              }
            else
              {
		NSLog(@"DBHTMLWriter - formatOneLine - unknown class for object %@ of class %@ inside DBSObject", value, [value class]);
              }
          }
      }
    else if ([obj isKindOfClass: [NSString class]])
      {
        //NSLog(@"formatOneLine, we have directly a scalar object, NSString: %@", obj);
        [dataDict setObject:obj forKey:obj];
        [keyOrder addObject:obj];
      }
    else if ([obj isKindOfClass: [NSNumber class]])
      {
        [logger log: LogStandard :@"[DBHTMLWriter formatOneLine] we have a NSNumber, unhandled %@:\n", obj];
      }
    else
      NSLog(@"unknown class of value: %@", [obj class]);
    }
  
  /* create the string */
  theLine = [[NSMutableString alloc] initWithCapacity:64];
  [theLine appendString:@"<tr>"];

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
              valStr = [self formatScalarObject: key forHeader:headerFlag];
            }
          else
            {
              if (originalKey)
                {
                  id val;
              
                  val = [dataDict objectForKey: originalKey];
                  if (val)
                    {
                      valStr = [self formatScalarObject: val forHeader:headerFlag];
                    }
                  else
                    {
                      /* we found the key but no corresponding value
                         we insert an empty string to keep the column sequence */
                      valStr = [self formatScalarObject: @""  forHeader:headerFlag];
                    }
                }
              else
                {
                  /* we no corresponding key, possibly referencing a null complex object
                     we insert an empty string to keep the column sequence */
                  valStr = [self formatScalarObject: @"" forHeader:headerFlag];
                }
            }
      
          [theLine appendString:valStr];
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
              valStr = [self formatScalarObject: k forHeader:headerFlag];
            }
          else
            {
              val = [dataDict objectForKey: k];
              if (val)
                {
                  valStr = [self formatScalarObject: val forHeader:headerFlag];
                }
            }
          [theLine appendString:valStr];
        }
    }
  
  [keyOrder release];
  [dataDict release];
  [theLine appendString:@"</tr>"];
  [theLine appendString:newLine];
  return [theLine autorelease];
}

@end
