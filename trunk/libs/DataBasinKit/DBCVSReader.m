/*
  Project: DataBasin

  Copyright (C) 2009-2014 Free Software Foundation

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

#import "DBCVSReader.h"
#import "DBLogger.h"


@implementation DBCVSReader

- (id)initWithPath:(NSString *)filePath withLogger:(DBLogger *)l
{
  if ((self = [super init]))
    {
      [self initWithPath:filePath byParsingHeaders:YES withLogger:l];
    }
  return self;
}

- (void)setLogger:(DBLogger *)l
{
  logger = l;
}

- (id)initWithPath:(NSString *)filePath byParsingHeaders:(BOOL)parseHeader withLogger:(DBLogger *)l
{
  if ((self = [super init]))
    {
      NSString *fileContentString;
      NSRange firstNLRange;
      NSRange firstCRRange;

      logger = l;
      isQualified = NO;
      qualifier = @"\"";
      separator = @",";
      newLine = @"\n";
      currentLine = 0;
      fileContentString = [NSString stringWithContentsOfFile:filePath];
      [logger log:LogStandard :@"[DBCVSReader initWithPath] analyzing file\n"];
      if (fileContentString)
      {
	if ([[fileContentString substringToIndex:[qualifier length]] isEqualToString: qualifier])
	  isQualified = YES;
	[logger log:LogStandard :@"[DBCVSReader initWithPath] Is file qualified? %d\n", isQualified];

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
	if(parseHeader)
	  fieldNames = [[NSArray arrayWithArray:[self getFieldNames:[self readLine]]] retain];
      }
   }
  return self;
}

- (void)dealloc
{
  [linesArray release];
  [fieldNames release];
  [super dealloc];
}

- (NSArray *)fieldNames
{
  return fieldNames;
}

- (NSArray *)getFieldNames:(NSString *)firstLine
{
  NSArray *record;

  record = [self decodeOneLine:firstLine];
    
  [logger log:LogDebug :@"[DBCVSReader getFieldNames] header %@\n", record];
  return record;
}

- (NSArray *)readDataSet
{
  NSMutableArray *set;
  NSString       *line;
  
  set = [NSMutableArray arrayWithCapacity:1];
  while ((line = [self readLine]) != nil)
    {
      NSArray *record;
      
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
  BOOL           inField;
  
  if ([line length] == 0)
    return nil;
  
  scanner = [NSScanner scannerWithString:line];
  record = [NSMutableArray arrayWithCapacity:1];

  if (isQualified)
    {
      NSString *token;

      field = @"";
      //NSLog(@"loc %lu, total length: %lu", [scanner scanLocation], [line length]);
      inField = false;
      while ([scanner scanLocation] < [line length])
	{
	  NSUInteger loc;

	  token = nil;
	  [scanner scanUpToString:qualifier intoString:&token];
	  //NSLog(@"token %@", token);

	  loc = [scanner scanLocation];

	  /* we reach the end, but the field was empty, thus we artifically insert an empty string */
	  if (loc == [line length]-1 && token == nil)
	    {
	      token = @"";
              //	      NSLog(@"we reached the end... token is %@", token);
	    }
	  //NSLog(@"loc %lu", loc);
	  if (loc > 0 && token)
	    {
	      if ([line characterAtIndex:(loc-1)] == '\\')
		{
		  /* it was an escaped qualifier */
		  //NSLog(@"Escaped qualifier");
		  inField = YES;
		  field = [field stringByAppendingString: [token substringToIndex:[token length]-1]];
		  field = [field stringByAppendingString: @"\""];
		  [scanner scanString:qualifier intoString:(NSString **)nil];
		}
	      else
		{
		  /* we might have skipped qualifiers up to a separator, thus an empty field. We check for that */
		  if (![token isEqualToString:separator])
		    {
		      if (inField)
			field = [field stringByAppendingString: token];
		      else
			field = [NSString stringWithString: token];
		      if (field == nil)
			field = @"";
		      [scanner scanString:qualifier intoString:(NSString **)nil];
		    }

		  [record addObject:field];

		  [scanner scanString:separator intoString:(NSString **)nil];

		  inField = NO;
		  field = @"";
		}
	    }
	  else
	    {
	      /* let's skip this qualifier */
	      [scanner scanString:qualifier intoString:(NSString **)nil];
	    }
	}
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
      return [linesArray objectAtIndex:currentLine++];
    }
  return nil;
}

@end
