/*
  Project: DataBasin

  Copyright (C) 2009-2015 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2009-06-24 22:34:06 +0200 by multix

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

#import "DBCSVReader.h"
#import "DBLoggerProtocol.h"

@implementation DBCSVReader

- (id)initWithPath:(NSString *)filePath withLogger:(id<DBLoggerProtocol>)l
{
  if ((self = [self initWithPath:filePath byParsingHeaders:YES withLogger:l]))
    {
    }
  return self;
}

- (id)initWithPath:(NSString *)filePath byParsingHeaders:(BOOL)parseHeader withLogger:(id<DBLoggerProtocol>)l
{
  if ((self = [super init]))
    {
      NSString *fileContentString;
      NSRange firstNLRange;
      NSRange firstCRRange;

      logger = l;
      newLine = @"\n";
      currentLine = 0;
      fileContentString = [NSString stringWithContentsOfFile:filePath];
      [logger log:LogStandard :@"[DBCVSReader initWithPath] analyzing file\n"];
      if (fileContentString)
      {
	firstNLRange = [fileContentString rangeOfString:@"\n"];
	firstCRRange = [fileContentString rangeOfString:@"\r"];

	if (firstCRRange.location == NSNotFound)
	  {
	    /* it can be NL only */
	    if (firstNLRange.location > 0)
	      {
		[logger log:LogStandard :@"[DBCVSReader initWithPath] standard unix-style\n"];
		newLine = @"\n";
	      }
	    else
	      NSLog(@"could not determine line ending style");
	  }
	else
	  {
	    /* it could be CR or CR+NL */
	    if (firstNLRange.location != NSNotFound && firstNLRange.location > 0)
	      {
		if (firstNLRange.location - firstCRRange.location == 1)
		  {
		    [logger log:LogStandard :@"[DBCVSReader initWithPath] standard DOS-style\n"];
		    newLine=@"\r\n";
		  }
		else
		  [logger log:LogStandard :@"[DBCVSReader initWithPath] ambiguous, using unix-style\n"];
	      }
	    else if (firstCRRange.location > 0)
	      {
		[logger log:LogStandard :@"[DBCVSReader initWithPath] old mac-style\n"];
		newLine = @"\r";
	      }
	    else
	      [logger log:LogStandard :@"[DBCVSReader initWithPath] could not determine line ending style\n"];
	  }

	linesArray = [[fileContentString componentsSeparatedByString:newLine] retain];
        [self setQualifier:@"\""];
        [self setSeparator:@","];
        if (parseHeader)
          {
            [self parseHeaders];
            currentLine++;
          }
      }
   }
  return self;
}

- (void)dealloc
{
  [qualifier release];
  [separator release];
  [linesArray release];
  [fieldNames release];
  [super dealloc];
}


- (void)setLogger:(id<DBLoggerProtocol>)l
{
  logger = l;
}


- (void)setQualifier: (NSString *)q
{
  if (qualifier != q)
    {
      isQualified = NO;
      [qualifier release];
      qualifier = [q retain];
      if ([[[linesArray objectAtIndex:0] substringToIndex:[qualifier length]] isEqualToString: qualifier])
        isQualified = YES;
      [logger log:LogStandard :@"[DBCVSReader setQualifier] Is file qualified? %d\n", isQualified];
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

/**
   Returns an array with the field names. parseHeaders needs to be called once before.
 */
- (NSArray *)fieldNames
{
  return fieldNames;
}

/**
   Extracts the field names from the first line. Needs to be (re)called after field separator
   and qualifier characters are set.
 */
- (void)parseHeaders
{
  [fieldNames release];
  fieldNames = [[NSArray arrayWithArray:[self decodeOneLine:[linesArray objectAtIndex:0]]] retain];
  [logger log:LogDebug :@"[DBCVSReader fieldNames]  %@\n", fieldNames];
}

- (NSArray *)readDataSet
{
  NSMutableArray *set;
  NSString       *line;
  
  set = [NSMutableArray arrayWithCapacity:1];
  while ((line = [self readLine]) != nil)
    {
      NSArray *record;
      
      currentLine++;
      record = [self decodeOneLine:line];
//      NSLog(@"record %@", record);
      if (record != nil)
        [set addObject:record];
    }
  return set;
}

- (NSArray *)decodeOneLine:(NSString *)line
{
  NSScanner      *scanner;
  NSMutableArray *record;
  NSString       *field;
  
  if ([line length] == 0)
    return nil;

  scanner = [NSScanner scannerWithString:line];
  record = [NSMutableArray arrayWithCapacity:1];

  if (isQualified)
    {
      NSString *token;
      BOOL     inField;
      BOOL     inQualifier;

      field = @"";
      //NSLog(@"loc %lu, total length: %lu", [scanner scanLocation], [line length]);
      inField = NO;
      inQualifier = NO;
      while ([scanner scanLocation] < [line length])
	{
	  NSUInteger loc;

	  token = nil;
	  [scanner scanUpToString:qualifier intoString:&token];

	  loc = [scanner scanLocation];

	  if ([token isEqualToString:separator])
	    {
              [record addObject:field];

              [scanner scanString:separator intoString:(NSString **)nil];
              
              inField = NO;
              inQualifier = NO;
              field = @"";
	    }
	  else if (loc > 0 && token == nil &&
              [line characterAtIndex:(loc-1)] == [qualifier characterAtIndex:0])
                {
                  if (!inQualifier)
                    {
                      /* it was an qualified qualifier */
                      field = [field stringByAppendingString: qualifier];
                    }
		  inField = YES;
                  inQualifier = YES;
                  [scanner scanString:qualifier intoString:(NSString **)nil];
            }
	  else if (loc > 0 && token)
	    {
	      if ([line characterAtIndex:(loc-1)] == '\\')
		{
		  /* it was an escaped qualifier */
		  inField = YES;
                  inQualifier = YES;
		  field = [field stringByAppendingString: [token substringToIndex:[token length]-1]];
		  field = [field stringByAppendingString: qualifier];
                  [scanner scanString:qualifier intoString:(NSString **)nil];
		}
	      else
		{
                  field = [field stringByAppendingString: token];

                  [scanner scanString:qualifier intoString:(NSString **)nil];

                  inField = YES;
                  inQualifier = NO;
		}
	    }
	  else
	    {
	      /* let's skip this qualifier */
	      [scanner scanString:qualifier intoString:(NSString **)nil];
	    }
	}
      if (field)
        [record addObject:field];
    }
  else
    {
      while ([scanner scanLocation] < [line length])
	{
	  NSUInteger scanLocation;
	  NSUInteger scanLocation2;
	  if ([scanner scanUpToString:separator intoString:&field] == YES)
	    {
	      if (field == nil)
		field = @"";
	    }
	  else
	    {
	      
	      field = @"";
	    }
	  //NSLog(@"adding nq field: %@", field);
	  [record addObject:field];
	  scanLocation = [scanner scanLocation];
	  [scanner scanString:separator intoString:(NSString **)nil];
	  scanLocation2 = [scanner scanLocation];
	  if ((scanLocation2 == [line length])  && (scanLocation != scanLocation2))
	    {
	      /* the last is empty and was skipped, we add it */
	      //NSLog(@"Skipped separator");
	      [record addObject:@""];
	    }
	    //NSLog(@"scan location: %lu-%lu", scanLocation2, [line length]);
	}
    }
  [logger log:LogDebug :@"[DBCVSReader getFieldNames] decoded record: %@\n", record];
  return record;
}

- (NSString *)readLine
{
  if (currentLine < [linesArray count])
    {
      return [linesArray objectAtIndex:currentLine];
    }
  return nil;
}

@end
