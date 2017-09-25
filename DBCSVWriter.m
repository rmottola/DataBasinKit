/*
   Project: DataBasin

   Copyright (C) 2009-2016 Free Software Foundation

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

#import "DBCSVWriter.h"
#import "DBSObject.h"
#import "DBLoggerProtocol.h"

#import <WebServices/GWSConstants.h>

@implementation DBCSVWriter

- (id)initWithHandle:(NSFileHandle *)fileHandle
{
  if ((self = [super init]))
    {
      file = fileHandle;
      isQualified = YES;
      qualifier = @"\"";
      separator = @",";
      newLine = @"\n";
      fieldNames = nil;
      writeOrdered = NO;
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
  else if ([value isKindOfClass: [NSNumber class]])
    {
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

- (void)formatComplexObject:(NSMutableDictionary *)d withRoot:(NSString *)root inDict:(NSMutableDictionary *)dict inOrder:(NSMutableArray *)order
{
  NSMutableArray  *keys;
  unsigned i;
  NSString *extendedFieldName;

  if (!d)
    return;

  keys = [NSMutableArray arrayWithArray:[d allKeys]];
  [keys removeObject:GWSOrderKey];
  
  /* remove some fields which get added automatically by salesforce even if not asked for */
  [keys removeObject:@"type"];
  
  /* remove Id only if it is null, else an array of two populated Id is returned by SF */
  if (![[d objectForKey:@"Id"] isKindOfClass: [NSArray class]])
    [keys removeObject:@"Id"];

  //[logger log: LogDebug :@"[DBCSVWriter formatComplexObject] clean dictionary %@:\n", d];
  //NSLog(@"[DBCSVWriter formatComplexObject] clean dictionary %@\n", d);

  for (i = 0; i < [keys count]; i++)
    {
      id obj;
      NSString *key;
      
      key = [keys objectAtIndex: i];
      obj = [d objectForKey: key];
      if ([key isEqualToString:@"Id"])
	obj = [obj objectAtIndex: 0];
      
      if ([obj isKindOfClass: [NSDictionary class]])
        {
          NSMutableString *s;

          if (root)
            s = [NSMutableString stringWithString:root];
          else
            s = [NSMutableString stringWithString:@""];

          if (root)
            [s appendString:@"."];
          [s appendString:key];

          //NSLog(@"formatting complex object with root: %@", s);
          [self formatComplexObject: obj withRoot:s inDict:dict inOrder:order];
        }
      else if ([obj isKindOfClass: [NSString class]] || [obj isKindOfClass: [NSNumber class]])
        {
	  NSMutableString *s;

          if (root)
            s = [NSMutableString stringWithString:root];
          else
            s = [NSMutableString stringWithString:@""];

          if (root)
            [s appendString:@"."];

          [s appendString:key];

          extendedFieldName = s;
          //NSLog(@"formatting scalar object: %@ for key: %@", obj,extendedFieldName);
          [dict setObject:obj forKey:extendedFieldName];
          [order addObject:extendedFieldName];
	}
      else
	NSLog(@"[DBCSVWriter formatComplexObject] unknown class of value: %@, object: %@", [obj class], obj);
      
    }
}

/*
  This methods sets the internal field names for the header when using ordered object writeout.
*/
- (void)setFieldNames:(id)obj andWriteThem:(BOOL)flag
{
  NSArray *array;

  [logger log: LogDebug :@"[DBCSVWriter setFieldNames] Object: %@:\n", obj];

  /* if we have no data, we return */
  if (obj == nil)
    return;

  /* if we have just a single object, we fake an array */
  if([obj isKindOfClass: [NSArray class]])
    array = obj;
  else
    array = [NSArray arrayWithObject: obj];

  if ([array count] == 0)
    return;
 
  if (fieldNames != array)
    {
      [fieldNames release];
      fieldNames = array;
      [array retain];
    }

  [logger log: LogDebug :@"[DBCSVWriter setFieldNames] Names: %@:\n", array];

  /* if we write the header, fine, else we write at least the BOM */
  if (flag == YES)
    {
      NSString *theLine;

      theLine = [self formatOneLine:array forHeader:YES];
      [file writeData: [theLine dataUsingEncoding: encoding]];
    }
  else
    {
      NSData *tempData;

      tempData = [@" "dataUsingEncoding: encoding];
      tempData = [tempData subdataWithRange: NSMakeRange(0, bomLength)];
      [file writeData: tempData];
    }
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
	      
	      if ([value isKindOfClass: [NSString class]] ||[value isKindOfClass: [NSNumber class]] )
		{
                  [dataDict setObject:value forKey:key];
                  [keyOrder addObject:key];
		}
	      else if ([value isKindOfClass: [NSCalendarDate class]])
		{
		  // FIXME Date Handling could allow more options
                  [dataDict setObject:[value description] forKey:key];
                  [keyOrder addObject:key];
		}
	      else if ([value isKindOfClass: [NSDictionary class]])
		{
		  // NSLog(@"Dictionary");
		  [self formatComplexObject:value withRoot:key inDict:dataDict inOrder:keyOrder];
		}
	      else
		{
		  NSLog(@"unknown class for object %@ of class %@", value, [value class]);
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
          NSLog(@"formatOneLine, we have directly a scalar object, NSNumber: %@", obj);
          [logger log: LogStandard :@"[DBCSVWriter formatOneLine] we have a NSNumber, unhandled %@:\n", obj];
	}
      else
        NSLog(@"unknown class of value: %@", [obj class]);
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
