/* 
   NSSpellProtocol.h

   Protocols for spell checking

   Copyright (C) 1997 Free Software Foundation, Inc.

   Author:  Simon Frankau <sgf@frankau.demon.co.uk>
   Date: 1997
   
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
*/ 

#ifndef _GNUstep_H_NSSpellProtocol
#define _GNUstep_H_NSSpellProtocol

#include <objc/objc.h>

@protocol NSChangeSpelling

- (void) changeSpelling:(id)sender;

@end

@protocol NSIgnoreMisspelledWords

- (void)ignoreSpelling:(id)sender;

@end

#endif // _GNUstep_H_NSSpellProtocol
