/* -*- mode: objc -*-
   Project: DataBasinKit

   Copyright (C) 2019-2025 Free Software Foundation

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

#ifndef _DBREST_H_
#define _DBREST_H_

#import <Foundation/Foundation.h>
#import <WebServices/WebServices.h>

@class DBSObject;
@protocol DBProgressProtocol;
@protocol DBLoggerProtocol;

@interface DBRest : NSObject
{
  GWSService *service;
  id<DBLoggerProtocol> logger;

  /* salesforce.com session variables */
  NSString     *sessionId;
  NSURL        *serverURL;

  /** is executing */
  NSUInteger *busyCount;
  NSRecursiveLock *lockBusy;

  /** describe each object in a query to get field types */
  BOOL enableFieldTypesDescribeForQuery;
}

+ (NSString *)encodeQueryString:(NSString *)query;

- (void)setLogger: (id<DBLoggerProtocol>)l;
- (id<DBLoggerProtocol>)logger;

- (NSString *)query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;
- (NSString *)queryMore :(NSString *)locator toArray:(NSMutableArray *)objects;


- (NSString *) sessionId;
- (void) setSessionId:(NSString *)session;
- (NSURL *) serverURL;
- (void) setServerURL:(NSURL *)url;


- (NSString *)_query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects declaredSize:(NSUInteger *)ds progressMonitor:(id<DBProgressProtocol>)p;

@end

#endif // _DBREST_H_

