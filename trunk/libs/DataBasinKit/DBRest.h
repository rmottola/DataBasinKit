/*
   Project: DataBasinKit

   Copyright (C) 2019 Free Software Foundation

   Author: Riccardo Mottola

   Created: 2019-05-13 14:40:47 +0000 by multix

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
  NSString     *serverUrl;
}

+ (NSString *)encodeQueryString:(NSString *)query;

- (void)setLogger: (id<DBLoggerProtocol>)l;
- (id<DBLoggerProtocol>)logger;

- (NSString *)query :(NSString *)queryString queryAll:(BOOL)all toArray:(NSMutableArray *)objects progressMonitor:(id<DBProgressProtocol>)p;

- (NSString *) sessionId;
- (void) setSessionId:(NSString *)session;
- (NSString *) serverUrl;
- (void) setServerUrl:(NSString *)urlStr;
- (void)setService:(GWSService *)serv;

@end

#endif // _DBREST_H_

