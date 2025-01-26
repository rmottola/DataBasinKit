/**  -*- mode: objc -*-
  Project: DataBasin

  Copyright (C) 2012-2015 Free Software Foundation

  Author: Riccardo Mottola

  Created: 2012-10-19 09:32:13 +0000 by Riccardo Mottola

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
  Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
*/

@class DBLogger;

@protocol DBProgressProtocol <NSObject>

/** Sets the maximum value expected on which to calculate progress on.<br/>
    E.g. it could be the maximum expected number of records.
  */
-(void)setMaximumValue:(unsigned long)max;

/** Sets the current progress, e.g. the current count */
-(void)setCurrentValue:(unsigned long)current;

/** increments the current value by given amount */
-(void)incrementCurrentValue:(unsigned long)amount;

/** reinitializes internal status (current, maxmimum and percentage) */
-(void)reset;

/** Forces completion */
-(void)setEnd;

/** Sets a description of the current phase */
-(void)setCurrentDescription:(NSString *)desc;

/** if the process the progress is associated should stop */
-(BOOL)shouldStop;

/** marks if the process associated should stop */
-(void)setShouldStop:(BOOL)flag;

@end
