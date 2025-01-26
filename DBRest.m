/* -*- mode: objc -*-
   Project: DataBasinKit

   Copyright (C) 2019 Free Software Foundation

   Author: Riccardo Mottola

   Created: 2019-05-13 14:40:47 +0000 by Riccardo Mottola

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

#import "DBRest.h"

#import "DBProgressProtocol.h"
#import "DBLoggerProtocol.h"

@implementation DBRest

+ (NSString *)encodeQueryString:(NSString *)query
{
  NSMutableString *eq;

  eq = [NSMutableString stringWithString:query];
  [eq replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [eq length])];

  return [NSString stringWithString:eq];
}

- (id)init
{
  if ((self = [super init]))
    {
    }
  return self;
}

- (void)setLogger: (id<DBLoggerProtocol>)l
{
  if (logger)
    [logger release];
  logger = [l retain];
}

- (id<DBLoggerProtocol>)logger
{
  return logger;
}

- (NSString *)query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p
{
  NSURL *url;
  NSString *queryCommand;
  NSDictionary *headers;
  NSDictionary *response;
  id result;
  GWSService *gsrv;
  GWSJSONCoder *coder;
  NSString *bearerStr;

  bearerStr = [@"Bearer " stringByAppendingString:sessionId];
  headers = [NSDictionary dictionaryWithObjectsAndKeys:
			    @"application/json; charset=utf-8", @"Content-Type",
			  bearerStr, @"Authorization",
			  nil];

  queryCommand = [@"query/?=" stringByAppendingString:[DBRest encodeQueryString:queryString]];
  url = [serverURL URLByAppendingPathComponent:queryCommand];
  NSLog(@"URL: %@", url);
  gsrv = [[GWSService alloc] init];

  [gsrv setHeaders:headers];
  [gsrv setDebug:YES];
  [gsrv setURL:url];
  [gsrv setHTTPMethod:@"GET"];
  
  coder = [GWSJSONCoder new];
  [gsrv setCoder:coder];
  [coder release];
  [gsrv setDelegate:self];
  response = [gsrv invokeMethod:@"query"
		   parameters: nil
			order: nil
		      timeout: 30];
  [gsrv setDelegate:nil];
  NSLog(@"response: %@", response);

  if ((result = [response objectForKey: GWSErrorKey]) != nil)
    {
      NSLog(@"Error!");
    }
  else if ((result = [response objectForKey: GWSFaultKey]) != nil)
    {
      NSLog(@"Fault!");
    }
  else
    {
      NSArray *order;
      NSDictionary *values;
      NSUInteger count;
      NSUInteger i;

      order = [response objectForKey: GWSOrderKey];
      values = [response objectForKey: GWSParametersKey];
      count = [order count];
      result = [NSMutableArray arrayWithCapacity: count];
      for (i = 0; i < count; i++)
	{
	  NSString *key;

	  key = [order objectAtIndex: i];
	  [result addObject: [values objectForKey: key]];
	}
      
      NSLog(@"real stuff: %@", result);
    }
  
  
  [gsrv release];
}


/* accessors*/
- (NSString *) sessionId
{
  return sessionId;
}

- (void) setSessionId:(NSString *)session
{
  if (sessionId != session)
    {
      [sessionId release];
      sessionId = session;
      [sessionId retain];
    }
}

- (NSURL *) serverURL
{
  return serverURL;
}

- (void) setServerURL:(NSURL *)url
{
  if (serverURL != url)
    {
      [serverURL release];
      serverURL = url;
      [serverURL retain];
    }
}


- (void)dealloc
{
  [sessionId release];
  [service release];
  [super dealloc];
}

@end
