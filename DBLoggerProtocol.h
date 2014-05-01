/*
  Project: DataBasinKit

  Copyright (C) 2014 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2014-05-01 17:13:41 +0200 by multix

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

typedef enum
{
  LogStandard = 1,
  LogInformative = 2,
  LogDebug = 3
} DBLogLevel;

@protocol DBLoggerProtocol <NSObject>

-(void)setLogLevel: (DBLogLevel)l;
-(void)log: (DBLogLevel)level :(NSString* )format, ...;

@end
