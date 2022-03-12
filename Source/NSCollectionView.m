/** <title>NSCollectionView</title>
 
   Copyright (C) 2013, 2021 Free Software Foundation, Inc.
 
   Author: Doug Simons (doug.simons@testplant.com)
           Frank LeGrand (frank.legrand@testplant.com)
           Gregory Casamento (greg.casamento@gmail.com)
           (Incorporate NSCollectionViewLayout logic)

   Date: February 2013, December 2021
 
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the 
   Free Software Foundation, 51 Franklin Street, Fifth Floor, 
   Boston, MA 02110-1301, USA.
*/

#import "Foundation/NSKeyedArchiver.h"

#import <Foundation/NSGeometry.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSKeyedArchiver.h>

#import "AppKit/NSApplication.h"
#import "AppKit/NSClipView.h"
#import "AppKit/NSCollectionView.h"
#import "AppKit/NSCollectionViewItem.h"
#import "AppKit/NSCollectionViewLayout.h"
#import "AppKit/NSCollectionViewGridLayout.h"
#import "AppKit/NSEvent.h"
#import "AppKit/NSGraphics.h"
#import "AppKit/NSImage.h"
#import "AppKit/NSKeyValueBinding.h"
#import "AppKit/NSNib.h"
#import "AppKit/NSPasteboard.h"
#import "AppKit/NSWindow.h"

#import "GSGuiPrivate.h"

#include <math.h>

static NSString* NSCollectionViewMinItemSizeKey              = @"NSMinGridSize";
static NSString* NSCollectionViewMaxItemSizeKey              = @"NSMaxGridSize";
//static NSString* NSCollectionViewVerticalMarginKey           = @"NSCollectionViewVerticalMarginKey";
static NSString* NSCollectionViewMaxNumberOfRowsKey          = @"NSMaxNumberOfGridRows";
static NSString* NSCollectionViewMaxNumberOfColumnsKey       = @"NSMaxNumberOfGridColumns";
static NSString* NSCollectionViewSelectableKey               = @"NSSelectable";
static NSString* NSCollectionViewAllowsMultipleSelectionKey  = @"NSAllowsMultipleSelection";
static NSString* NSCollectionViewBackgroundColorsKey         = @"NSBackgroundColors";
static NSString* NSCollectionViewLayoutKey                   = @"NSCollectionViewLayout";

static NSCollectionViewSupplementaryElementKind GSNoSupplementaryElement  = @"GSNoSupplementaryElement"; // private

/*
 * Class variables
 */
static NSString *placeholderItem = nil;

@interface NSCollectionView (CollectionViewInternalPrivate)

- (void) _initDefaults;
- (void) _resetItemSize;
- (void) _removeItemsViews;
- (NSInteger) _indexAtPoint: (NSPoint)point;

- (NSRect) _frameForRowOfItemAtIndex: (NSUInteger)theIndex;
- (NSRect) _frameForRowsAroundItemAtIndex: (NSUInteger)theIndex;

- (void) _modifySelectionWithNewIndex: (NSUInteger)anIndex
                            direction: (int)aDirection
                               expand: (BOOL)shouldExpand;
                                                          
- (void) _moveDownAndExpandSelection: (BOOL)shouldExpand;
- (void) _moveUpAndExpandSelection: (BOOL)shouldExpand;
- (void) _moveLeftAndExpandSelection: (BOOL)shouldExpand;
- (void) _moveRightAndExpandSelection: (BOOL)shouldExpand;

- (BOOL) _writeItemsAtIndexes: (NSIndexSet *)indexes 
                 toPasteboard: (NSPasteboard *)pasteboard;

- (BOOL) _startDragOperationWithEvent: (NSEvent*)event 
                         clickedIndex: (NSUInteger)index;

- (void) _selectWithEvent: (NSEvent *)theEvent 
                    index: (NSUInteger)index;

@end


@implementation NSCollectionView

//
// Class methods
//
+ (void) initialize
{
  if (self == [NSCollectionView class])
    {
      placeholderItem = @"Placeholder";
      [self exposeBinding: NSContentBinding];
      [self setVersion: 0];
    }
}

- (id) initWithFrame: (NSRect)frame
{
  if ((self = [super initWithFrame:frame]))
    {
      [self _initDefaults];
    }
  return self;
}

-(void) _initDefaults
{
  _draggingSourceOperationMaskForLocal = NSDragOperationGeneric | NSDragOperationMove | NSDragOperationCopy;
  _draggingSourceOperationMaskForRemote = NSDragOperationGeneric | NSDragOperationMove | NSDragOperationCopy;
  [self _resetItemSize];
  _content = [[NSArray alloc] init];
  _items = [[NSMutableArray alloc] init];
  _selectionIndexes = [[NSIndexSet alloc] init];
  _draggingOnIndex = NSNotFound;

  // 10.11 variables
  
  // Managing items.
  _visibleItems = [[NSMutableArray alloc] init];
  _indexPathsForVisibleItems = [[NSMutableSet alloc] init];
  _visibleSupplementaryViews = [[NSMutableDictionary alloc] init];
  _indexPathsForSupplementaryElementsOfKind = [[NSMutableSet alloc] init];

  // Registered nib/class
  _registeredNibs = RETAIN([NSMapTable weakToStrongObjectsMapTable]);
  _registeredClasses = RETAIN([NSMapTable weakToStrongObjectsMapTable]);
}

- (void) _resetItemSize
{
  if (itemPrototype && ([itemPrototype view] != nil))
    {
      _itemSize = [[itemPrototype view] frame].size;
      _minItemSize = NSMakeSize (_itemSize.width, _itemSize.height);
      _maxItemSize = NSMakeSize (_itemSize.width, _itemSize.height);
    }
  else
    {
      // FIXME: This is just arbitrary.
      // What are we suppose to do when we don't have a prototype?
      _itemSize = NSMakeSize(120.0, 100.0);
      _minItemSize = NSMakeSize(120.0, 100.0);
      _maxItemSize = NSMakeSize(120.0, 100.0);
    }
}

- (void) drawRect: (NSRect)dirtyRect
{
  // TODO: Implement "use Alternating Colors"
  if (_backgroundColors && [_backgroundColors count] > 0)
    {
      NSColor *bgColor = [_backgroundColors objectAtIndex: 0];
      [bgColor set];
      NSRectFill(dirtyRect);
    }

  NSPoint origin = dirtyRect.origin;
  NSSize size = dirtyRect.size;
  NSPoint oppositeOrigin = NSMakePoint (origin.x + size.width, origin.y + size.height);
  
  NSInteger firstIndexInRect = MAX(0, [self _indexAtPoint: origin]);
  // I had to extract these values from the macro to get it
  // working correctly.
  NSInteger index = [self _indexAtPoint: oppositeOrigin];
  NSInteger last = [_items count] - 1;
  NSInteger lastIndexInRect = MIN(last, index);

  for (index = firstIndexInRect; index <= lastIndexInRect; index++)
    {
      // Calling itemAtIndex: will eventually instantiate the collection view item,
      // if it hasn't been done already.
      NSCollectionViewItem *collectionItem = [self itemAtIndex: index];
      NSView *view = [collectionItem view];
      [view setFrame: [self frameForItemAtIndex: index]];
    }
}

- (void) dealloc
{
  //[[NSNotificationCenter defaultCenter] removeObserver: self];

  DESTROY (_content);

  // FIXME: Not clear if we should destroy the top-level item "itemPrototype" loaded in the nib file.
  DESTROY (itemPrototype);
  
  DESTROY (_backgroundColors);
  DESTROY (_selectionIndexes);
  DESTROY (_items);

  // Managing items.
  DESTROY(_visibleItems);
  DESTROY(_indexPathsForVisibleItems);
  DESTROY(_visibleSupplementaryViews);
  DESTROY(_indexPathsForSupplementaryElementsOfKind);

  // Registered nib/class
  DESTROY(_registeredNibs);
  DESTROY(_registeredClasses); 

  //DESTROY (_mouseDownEvent);
  [super dealloc];
}

- (BOOL) isFlipped
{
  return YES;
}

- (BOOL) allowsMultipleSelection
{
  return _allowsMultipleSelection;
}

- (void) setAllowsMultipleSelection: (BOOL)flag
{
  _allowsMultipleSelection = flag;
}

- (NSArray *) backgroundColors
{
  return _backgroundColors;
}

- (void) setBackgroundColors: (NSArray *)colors
{
  _backgroundColors = [colors copy];
  [self setNeedsDisplay: YES];
}

- (NSArray *) content
{
  return _content;
}

- (void) setContent: (NSArray *)content
{
  NSInteger i;

  ASSIGN(_content, content);
  [self _removeItemsViews];
  
  RELEASE (_items);
  _items = [[NSMutableArray alloc] initWithCapacity: [_content count]];
 
  for (i = 0; i < [_content count]; i++)
    {
      [_items addObject: placeholderItem];
    }

  if (!itemPrototype)
    {
      return;
    }
  else
    {
      [self _resetItemSize];
      // Force recalculation of each item's frame
      _itemSize = _minItemSize;
      _tileWidth = -1.0;
      [self tile];
    }
}

- (id < NSCollectionViewDelegate >) delegate
{
  return _delegate;
}

- (void) setDelegate: (id < NSCollectionViewDelegate >)aDelegate
{
  _delegate = aDelegate;
}

- (NSCollectionViewItem *) itemPrototype
{
  return itemPrototype;
}

- (void) setItemPrototype: (NSCollectionViewItem *)prototype
{
  ASSIGN(itemPrototype, prototype);
  [self _resetItemSize];
}

- (CGFloat) verticalMargin
{
  return _verticalMargin;
}

- (void) setVerticalMargin: (CGFloat)margin
{
  if (_verticalMargin == margin)
    return;
    
  _verticalMargin = margin;
  [self tile];
}

- (NSSize) maxItemSize
{
  return _maxItemSize;
}

- (void) setMaxItemSize: (NSSize)size
{
  if (NSEqualSizes(_maxItemSize, size))
    return;
    
  _maxItemSize = size;
  [self tile];
}

- (NSUInteger) maxNumberOfColumns
{
  return _maxNumberOfColumns;
}

- (void) setMaxNumberOfColumns: (NSUInteger)number
{
  _maxNumberOfColumns = number;
}

- (NSUInteger) maxNumberOfRows
{
  return _maxNumberOfRows;
}

- (void) setMaxNumberOfRows: (NSUInteger)number
{
  _maxNumberOfRows = number;
}

- (NSSize) minItemSize
{
  return _minItemSize;
}

- (void) setMinItemSize: (NSSize)size
{
  if (NSEqualSizes(_minItemSize, size))
    return;
    
  _minItemSize = size;
  [self tile];
}

- (BOOL) isSelectable
{
  return _isSelectable;
}

- (void) setSelectable: (BOOL)flag
{
  _isSelectable = flag;
  if (!_isSelectable)
    {
      NSInteger index = -1;
      while ((index = [_selectionIndexes indexGreaterThanIndex: index]) != NSNotFound)
        {
          id item = [_items objectAtIndex: index];
          if ([item respondsToSelector: @selector(setSelected:)])
            {
              [item setSelected:NO];
            }
        }
    }
}

- (NSIndexSet *) selectionIndexes
{
  return _selectionIndexes;
}

- (void) setSelectionIndexes: (NSIndexSet *)indexes
{
  if (!_isSelectable)
    {
      return;
    }
  
  if (![_selectionIndexes isEqual: indexes])
    {
      ASSIGN(_selectionIndexes, indexes);
    }
  
  NSUInteger index = 0;
  while (index < [_items count])
    {
      id item = [_items objectAtIndex: index];
      if ([item respondsToSelector: @selector(setSelected:)])
        {
          [item setSelected:NO];
        }
      index++;
    }
  
  index = -1;
  while ((index = [_selectionIndexes indexGreaterThanIndex: index]) != 
         NSNotFound)
    {
      id item = [_items objectAtIndex: index];
      if ([item respondsToSelector: @selector(setSelected:)])
        {
          [item setSelected: YES];
        }
    }
}

- (NSCollectionViewLayout *) collectionViewLayout
{
  return _collectionViewLayout;
}

- (void) setCollectionViewLayout: (NSCollectionViewLayout *)layout
{
  ASSIGN(_collectionViewLayout, layout);
  [self reloadData];
}

- (NSRect) frameForItemAtIndex: (NSUInteger)theIndex
{
  NSRect itemFrame = NSMakeRect (0,0,0,0);
  NSInteger index;
  NSUInteger count = [_items count];
  CGFloat x = _horizontalMargin;
  CGFloat y = -_itemSize.height;
  
  if (_maxNumberOfColumns > 0 && _maxNumberOfRows > 0)
    {
      count = MIN(count, _maxNumberOfColumns * _maxNumberOfRows);
    }

  for (index = 0; index < count; ++index)
    {
      if (index % _numberOfColumns == 0)
        {
          x = _horizontalMargin;
          y += _verticalMargin + _itemSize.height;
        }
      
      if (index == theIndex)
        {
          NSInteger draggingOffset = 0;

          if (_draggingOnIndex != NSNotFound)
            {
              NSInteger draggingOnRow = (_draggingOnIndex / _numberOfColumns);
              NSInteger currentIndexRow = (theIndex / _numberOfColumns);

              if (draggingOnRow == currentIndexRow)
                {
                  if (index < _draggingOnIndex)
                    {
                      draggingOffset = -20;
                    }
                  else
                    {
                      draggingOffset = 20;
                    }
                }
            }
          itemFrame = NSMakeRect ((x + draggingOffset), y, _itemSize.width, _itemSize.height);
          break;
        }
      
      x += _itemSize.width + _horizontalMargin;
    }
  return itemFrame;
}

- (NSRect) _frameForRowOfItemAtIndex: (NSUInteger)theIndex
{
  NSRect itemFrame = [self frameForItemAtIndex: theIndex];

  return NSMakeRect (0, itemFrame.origin.y, [self bounds].size.width, itemFrame.size.height);  
}

// Returns the frame of an item's row with the row above and the row below
- (NSRect) _frameForRowsAroundItemAtIndex: (NSUInteger)theIndex
{
  NSRect itemRowFrame = [self _frameForRowOfItemAtIndex: theIndex];
  CGFloat y = MAX (0, itemRowFrame.origin.y - itemRowFrame.size.height);
  CGFloat height = MIN (itemRowFrame.size.height * 3, [self bounds].size.height);

  return NSMakeRect(0, y, itemRowFrame.size.width, height);
}

- (NSCollectionViewItem *) itemAtIndex: (NSUInteger)index
{
  id item = [_items objectAtIndex: index];

  if (item == placeholderItem)
    {
      item = [self newItemForRepresentedObject: [_content objectAtIndex: index]];
      [_items replaceObjectAtIndex: index withObject: item];
      if ([[self selectionIndexes] containsIndex: index])
        {
          [item setSelected: YES];
        }
      [self addSubview: [item view]];
      RELEASE(item);
    }
  return item;
}

- (NSCollectionViewItem *) newItemForRepresentedObject: (id)object
{
  NSCollectionViewItem *collectionItem = nil;
  if (itemPrototype)
    {
      collectionItem = [itemPrototype copy];
      [collectionItem setRepresentedObject: object];
    }
  return collectionItem;
}

- (void) _removeItemsViews
{
  if (!_items)
    return;
  
  NSUInteger count = [_items count];
  
  while (count--)
    {
      id item = [_items objectAtIndex: count];

      if ([item respondsToSelector: @selector(view)])
        {
          [[item view] removeFromSuperview];
          [item setSelected: NO];
        }
    }
}

- (void) tile
{
  // TODO: - Animate items, Add Fade-in/Fade-out (as in Cocoa)
  //       - Put the tiling on a delay
  if (!_items)
    return;
  
  CGFloat width = [self bounds].size.width;
  
  if (width == _tileWidth)
    return;
  
  NSSize itemSize = NSMakeSize(_minItemSize.width, _minItemSize.height);
  
  _numberOfColumns = MAX(1.0, floor(width / itemSize.width));

  if (_maxNumberOfColumns > 0)
    {
      _numberOfColumns = MIN(_maxNumberOfColumns, _numberOfColumns);
    }

  if (_numberOfColumns == 0)
    {
      _numberOfColumns = 1;
    }
  
  CGFloat remaining = width - _numberOfColumns * itemSize.width;
  
  if (remaining > 0 && itemSize.width < _maxItemSize.width)
    {
      itemSize.width = MIN(_maxItemSize.width, itemSize.width + 
                           floor(remaining / _numberOfColumns));
    }

  if (_maxNumberOfColumns == 1 && itemSize.width < 
      _maxItemSize.width && itemSize.width < width)
    {
      itemSize.width = MIN(_maxItemSize.width, width);
    }

  if (!NSEqualSizes(_itemSize, itemSize))
    {
      _itemSize = itemSize;
    }
  
  NSInteger index;
  NSUInteger count = [_items count];
  
  if (_maxNumberOfColumns > 0 && _maxNumberOfRows > 0)
    {
      count = MIN(count, _maxNumberOfColumns * _maxNumberOfRows);
    }

  _horizontalMargin = floor((width - _numberOfColumns * itemSize.width) / 
                            (_numberOfColumns + 1));
  CGFloat y = -itemSize.height;
  
  for (index = 0; index < count; ++index)
    {
      if (index % _numberOfColumns == 0)
        {
          y += _verticalMargin + itemSize.height;
        }
    }
  
  id superview = [self superview];
  CGFloat proposedHeight = y + itemSize.height + _verticalMargin;
  if ([superview isKindOfClass: [NSClipView class]])
    {
      NSSize superviewSize = [superview bounds].size;
      proposedHeight = MAX(superviewSize.height, proposedHeight);
    }
  
  _tileWidth = width;
  [self setFrameSize: NSMakeSize(width, proposedHeight)];
  [self setNeedsDisplay: YES];
}

- (void) resizeSubviewsWithOldSize: (NSSize)aSize
{
  NSSize currentSize = [self frame].size;
  if (!NSEqualSizes(currentSize, aSize))
    {
      [self tile];
    }
}

- (id) initWithCoder: (NSCoder *)aCoder
{
  self = [super initWithCoder:aCoder];
  
  if (self)
    {
      _itemSize = NSMakeSize(0, 0);
      _tileWidth = -1.0;
          
      if ([aCoder allowsKeyedCoding])
        {
          if ([aCoder containsValueForKey: NSCollectionViewMinItemSizeKey])
            {
              _minItemSize = [aCoder decodeSizeForKey: NSCollectionViewMinItemSizeKey];
            }
          
          if ([aCoder containsValueForKey: NSCollectionViewMaxItemSizeKey])
            {
              _maxItemSize = [aCoder decodeSizeForKey: NSCollectionViewMaxItemSizeKey];
            }
          
          if ([aCoder containsValueForKey: NSCollectionViewMaxNumberOfRowsKey])
            {
              _maxNumberOfRows = [aCoder decodeInt64ForKey: NSCollectionViewMaxNumberOfRowsKey];
            }
          
          if ([aCoder containsValueForKey: NSCollectionViewMaxNumberOfColumnsKey])
            {
              _maxNumberOfColumns = [aCoder decodeInt64ForKey: NSCollectionViewMaxNumberOfColumnsKey];
            }
          
          //_verticalMargin = [aCoder decodeFloatForKey: NSCollectionViewVerticalMarginKey];
          
          if ([aCoder containsValueForKey: NSCollectionViewSelectableKey])
            {
              _isSelectable = [aCoder decodeBoolForKey: NSCollectionViewSelectableKey];
            }
          
          if ([aCoder containsValueForKey: NSCollectionViewAllowsMultipleSelectionKey])
            {
              _allowsMultipleSelection = [aCoder decodeBoolForKey: NSCollectionViewAllowsMultipleSelectionKey];
            }
          
          if ([aCoder containsValueForKey: NSCollectionViewBackgroundColorsKey])
            {
              [self setBackgroundColors: [aCoder decodeObjectForKey: NSCollectionViewBackgroundColorsKey]];
            }
          
          if ([aCoder containsValueForKey: NSCollectionViewLayoutKey])
            {
              [self setCollectionViewLayout: [aCoder decodeObjectForKey: NSCollectionViewLayoutKey]];
            }
        }
      else
        {
          _minItemSize = [aCoder decodeSize];
          _maxItemSize = [aCoder decodeSize];
          decode_NSUInteger(aCoder, &_maxNumberOfRows);
          decode_NSUInteger(aCoder, &_maxNumberOfColumns);
          [aCoder decodeValueOfObjCType: @encode(BOOL) at: &_isSelectable];
          [self setBackgroundColors: [aCoder decodeObject]]; // decode color...
          [self setCollectionViewLayout: [aCoder decodeObject]];
        }
    }
  [self _initDefaults];
    
  return self;
}

- (void) encodeWithCoder: (NSCoder *)aCoder
{
  [super encodeWithCoder: aCoder];
  if ([aCoder allowsKeyedCoding])
    {  
      if (!NSEqualSizes(_minItemSize, NSMakeSize(0, 0)))
        {
          [aCoder encodeSize: _minItemSize forKey: NSCollectionViewMinItemSizeKey];
        }
      
      if (!NSEqualSizes(_maxItemSize, NSMakeSize(0, 0)))
        {
          [aCoder encodeSize: _maxItemSize forKey: NSCollectionViewMaxItemSizeKey];
        }
      
      [aCoder encodeInt64: _maxNumberOfRows 
                   forKey: NSCollectionViewMaxNumberOfRowsKey];
      [aCoder encodeInt64: _maxNumberOfColumns 
                   forKey: NSCollectionViewMaxNumberOfColumnsKey];
      
      [aCoder encodeBool: _isSelectable 
                  forKey: NSCollectionViewSelectableKey];
      [aCoder encodeBool: _allowsMultipleSelection 
                  forKey: NSCollectionViewAllowsMultipleSelectionKey];
      
      //[aCoder encodeCGFloat: _verticalMargin forKey: NSCollectionViewVerticalMarginKey];
      [aCoder encodeObject: _backgroundColors 
                    forKey: NSCollectionViewBackgroundColorsKey];

      [aCoder encodeObject: _collectionViewLayout
                    forKey: NSCollectionViewLayoutKey];
    }
  else
    {
      [aCoder encodeSize: _minItemSize];
      [aCoder encodeSize: _maxItemSize];
      encode_NSUInteger(aCoder, &_maxNumberOfRows);
      encode_NSUInteger(aCoder, &_maxNumberOfColumns);
      [aCoder encodeValueOfObjCType: @encode(BOOL) at: &_isSelectable];      
      [aCoder encodeObject: [self backgroundColors]]; // encode color...
      [aCoder encodeObject: [self collectionViewLayout]];
    }
}

- (void) mouseDown: (NSEvent *)theEvent
{
  NSPoint initialLocation = [theEvent locationInWindow];
  NSPoint location = [self convertPoint: initialLocation fromView: nil];
  NSInteger index = [self _indexAtPoint: location];
  NSEvent *lastEvent = theEvent;
  BOOL done = NO;
  NSUInteger eventMask = (NSLeftMouseUpMask 
                        | NSLeftMouseDownMask
                        | NSLeftMouseDraggedMask 
                        | NSPeriodicMask);
  NSDate *distantFuture = [NSDate distantFuture];

  while (!done)
    {
      lastEvent = [NSApp nextEventMatchingMask: eventMask 
                                     untilDate: distantFuture
                                        inMode: NSEventTrackingRunLoopMode 
                                       dequeue: YES]; 
      NSEventType eventType = [lastEvent type];
      NSPoint mouseLocationWin = [lastEvent locationInWindow];
      switch (eventType)
        {
        case NSLeftMouseDown:
          break;
        case NSLeftMouseDragged:
          if (fabs(mouseLocationWin.x - initialLocation.x) >= 2
              || fabs(mouseLocationWin.y - initialLocation.y) >= 2)
            {
              if ([self _startDragOperationWithEvent: theEvent clickedIndex: index])
                {
                  done = YES;
                }
            }
          break;
        case NSLeftMouseUp:
          [self _selectWithEvent: theEvent index: index];
          done = YES;
          break;
        default:
          done = NO;
          break;
        }
    }
}

- (void) _selectWithEvent: (NSEvent *)theEvent index: (NSUInteger)index
{
  NSMutableIndexSet *currentIndexSet = [[NSMutableIndexSet alloc] initWithIndexSet: [self selectionIndexes]];
  
  if (_isSelectable && (index < [_items count]))
    {
      if (_allowsMultipleSelection
          && (([theEvent modifierFlags] & NSControlKeyMask)
              || ([theEvent modifierFlags] & NSShiftKeyMask)))
        {
          if ([theEvent modifierFlags] & NSControlKeyMask)
            {
              if ([currentIndexSet containsIndex: index])
                {
                  [currentIndexSet removeIndex: index];
                }
              else
                {
                  [currentIndexSet addIndex: index];
                }
              [self setSelectionIndexes: currentIndexSet];
            }
          else if ([theEvent modifierFlags] & NSShiftKeyMask)
            {
              NSUInteger firstSelectedIndex = [currentIndexSet firstIndex];
              NSRange selectedRange;
              
              if (firstSelectedIndex == NSNotFound)
                {
                  selectedRange = NSMakeRange(index, index);
                }
              else if (index < firstSelectedIndex)
                {
                  selectedRange = NSMakeRange(index, (firstSelectedIndex - index + 1));
                }
              else
                {
                  selectedRange = NSMakeRange(firstSelectedIndex, (index - firstSelectedIndex + 1));
                }
              [currentIndexSet addIndexesInRange: selectedRange];
              [self setSelectionIndexes: currentIndexSet];
            }
        }
      else
        {
          [self setSelectionIndexes: [NSIndexSet indexSetWithIndex: index]];
        }
      [[self window] makeFirstResponder: self];
    }
  else
    {
      [self setSelectionIndexes: [NSIndexSet indexSet]];
    }
  RELEASE (currentIndexSet);
}

- (NSInteger) _indexAtPoint: (NSPoint)point
{
  NSInteger row = floor(point.y / (_itemSize.height + _verticalMargin));
  NSInteger column = floor(point.x / (_itemSize.width + _horizontalMargin));
  return (column + (row * _numberOfColumns));
}

- (BOOL) acceptsFirstResponder
{
  return YES;
}

/* MARK: Keyboard Interaction */

- (void) keyDown: (NSEvent *)theEvent
{
  [self interpretKeyEvents: [NSArray arrayWithObject: theEvent]];
}

-(void) moveUp: (id)sender
{
  [self _moveUpAndExpandSelection: NO];
}
 
-(void) moveUpAndModifySelection: (id)sender
{
  [self _moveUpAndExpandSelection: YES];
}

- (void) _moveUpAndExpandSelection: (BOOL)shouldExpand
{
  NSInteger index = [[self selectionIndexes] firstIndex];
  if (index != NSNotFound && index >= _numberOfColumns)
    {
      [self _modifySelectionWithNewIndex: index - _numberOfColumns
                               direction: -1 
                                  expand: shouldExpand];
    }
}

-(void) moveDown: (id)sender
{
  [self _moveDownAndExpandSelection: NO];
}

-(void) moveDownAndModifySelection: (id)sender
{
  [self _moveDownAndExpandSelection: YES];
}

-(void) _moveDownAndExpandSelection: (BOOL)shouldExpand
{
  NSInteger index = [[self selectionIndexes] lastIndex];
  if (index != NSNotFound && (index + _numberOfColumns) < [_items count])
    {
      [self _modifySelectionWithNewIndex: index + _numberOfColumns
                               direction: 1 
                                  expand: shouldExpand];
    }
}

-(void) moveLeft: (id)sender
{
  [self _moveLeftAndExpandSelection: NO];
}

-(void) moveLeftAndModifySelection: (id)sender
{
  [self _moveLeftAndExpandSelection: YES];
}

-(void) moveBackwardAndModifySelection: (id)sender
{
  [self _moveLeftAndExpandSelection: YES];
}

-(void) _moveLeftAndExpandSelection: (BOOL)shouldExpand
{
  NSUInteger index = [[self selectionIndexes] firstIndex];
  if (index != NSNotFound && index != 0)
    {
      [self _modifySelectionWithNewIndex: index - 1 direction: -1 expand: shouldExpand];
    }
}

-(void) moveRight: (id)sender
{
  [self _moveRightAndExpandSelection: NO];
}

-(void) moveRightAndModifySelection: (id)sender
{
  [self _moveRightAndExpandSelection: YES];
}

-(void) moveForwardAndModifySelection: (id)sender
{
  [self _moveRightAndExpandSelection: YES];
}

-(void) _moveRightAndExpandSelection: (BOOL)shouldExpand
{
  NSUInteger index = [[self selectionIndexes] lastIndex];
  if (index != NSNotFound && index != ([_items count] - 1))
    {
      [self _modifySelectionWithNewIndex: index + 1 direction: 1 expand: shouldExpand];
    }
}

- (void) _modifySelectionWithNewIndex: (NSUInteger)anIndex
                            direction: (int)aDirection
                               expand: (BOOL)shouldExpand
{
  anIndex = MIN(MAX(anIndex, 0), [_items count] - 1);
  
  if (_allowsMultipleSelection && shouldExpand)
    {
      NSMutableIndexSet *newIndexSet = [[NSMutableIndexSet alloc] initWithIndexSet: _selectionIndexes];
      NSUInteger firstIndex = [newIndexSet firstIndex];
      NSUInteger lastIndex = [newIndexSet lastIndex];
      if (aDirection == -1)
        {
          [newIndexSet addIndexesInRange:NSMakeRange (anIndex, firstIndex - anIndex + 1)];
        }
      else
        {
          [newIndexSet addIndexesInRange:NSMakeRange (lastIndex, anIndex - lastIndex + 1)];
        }
      [self setSelectionIndexes: newIndexSet];
      RELEASE (newIndexSet);
    }
  else
    {
      [self setSelectionIndexes: [NSIndexSet indexSetWithIndex: anIndex]];
    }
  
  [self scrollRectToVisible: [self frameForItemAtIndex: anIndex]];
}


/* MARK: Drag & Drop */

-(NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL)isLocal
{
  if (isLocal)
    {
      return _draggingSourceOperationMaskForLocal;
    }
  else
    {
      return _draggingSourceOperationMaskForRemote;
    }
}

-(void) setDraggingSourceOperationMask: (NSDragOperation)mask
                              forLocal: (BOOL)isLocal
{
  if (isLocal)
    {
      _draggingSourceOperationMaskForLocal = mask;
    }
  else
    {
      _draggingSourceOperationMaskForRemote = mask;
    }
}

- (BOOL) _startDragOperationWithEvent: (NSEvent*)event 
                         clickedIndex: (NSUInteger)index
{
  NSIndexSet *dragIndexes = _selectionIndexes;

  if (![dragIndexes containsIndex: index]
      && (index < [_items count]))
    {
      dragIndexes = [NSIndexSet indexSetWithIndex: index];
    }
  
  if (![dragIndexes count])
    return NO;
  
  if (![_delegate respondsToSelector: @selector(collectionView:writeItemsAtIndexes:toPasteboard:)])
    return NO;
  
  if ([_delegate respondsToSelector: @selector(collectionView:canDragItemsAtIndexes:withEvent:)])
    {
      if (![_delegate collectionView: self
              canDragItemsAtIndexes: dragIndexes
                          withEvent: event])
        {
          return NO;
        }
    }
  
  NSPoint downPoint = [event locationInWindow];
  NSPoint convertedDownPoint = [self convertPoint: downPoint fromView: nil];
  
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName: NSDragPboard];
  if ([self _writeItemsAtIndexes:dragIndexes toPasteboard: pasteboard])
    {
      NSImage *dragImage = [self draggingImageForItemsAtIndexes: dragIndexes
                                                      withEvent: event
                                                         offset: NULL];
      
      [self dragImage: dragImage
                   at: convertedDownPoint
               offset: NSMakeSize(0,0)
                event: event
           pasteboard: pasteboard
               source: self
            slideBack: YES];
      
      return YES;
    }
  return NO;
}

- (NSImage *) draggingImageForItemsAtIndexes: (NSIndexSet *)indexes 
                                   withEvent: (NSEvent *)event 
                                      offset: (NSPointPointer)dragImageOffset
{
  if ([_delegate respondsToSelector: @selector(collectionView:draggingImageForItemsAtIndexes:withEvent:offset:)])
    {
      return [_delegate collectionView: self
                       draggingImageForItemsAtIndexes: indexes
                            withEvent: event
                               offset: dragImageOffset];
    }
  else
    {
      return [[NSImage alloc] initWithData: [self dataWithPDFInsideRect: [self bounds]]];
    }
}

- (BOOL) _writeItemsAtIndexes: (NSIndexSet *)indexes 
                 toPasteboard: (NSPasteboard *)pasteboard
{
  if (![_delegate respondsToSelector: @selector(collectionView:writeItemsAtIndexes:toPasteboard:)])
    {
      return NO;
    }
  else
    {
      return [_delegate collectionView: self
                  writeItemsAtIndexes: indexes
                         toPasteboard: pasteboard];
    }
}

- (void) draggedImage: (NSImage *)image
              endedAt: (NSPoint)point
            operation: (NSDragOperation)operation
{
}

- (NSDragOperation) _draggingEnteredOrUpdated: (id<NSDraggingInfo>)sender
{
  NSDragOperation result = NSDragOperationNone;
  
  if ([_delegate respondsToSelector: @selector(collectionView:validateDrop:proposedIndex:dropOperation:)])
    {
      NSPoint location = [self convertPoint: [sender draggingLocation] fromView: nil];
      NSInteger index = [self _indexAtPoint: location];
      index = (index > [_items count] - 1) ? [_items count] - 1 : index;
      _draggingOnIndex = index;
      
      NSInteger *proposedIndex = &index;
      NSInteger dropOperationInt = NSCollectionViewDropOn;
      NSCollectionViewDropOperation *dropOperation = &dropOperationInt;
      
      // TODO: We currently don't do anything with the proposedIndex & dropOperation that
      // may get altered by the delegate.
      result = [_delegate collectionView: self
                           validateDrop: sender
                          proposedIndex: proposedIndex
                          dropOperation: dropOperation];
      
      if (result == NSDragOperationNone)
        {
          _draggingOnIndex = NSNotFound;
        }
      [self setNeedsDisplayInRect: [self _frameForRowsAroundItemAtIndex: index]];
    }
  
  return result;
}

- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>)sender
{
  return [self _draggingEnteredOrUpdated: sender];
}

- (void) draggingExited: (id<NSDraggingInfo>)sender
{
  [self setNeedsDisplayInRect: [self _frameForRowsAroundItemAtIndex: _draggingOnIndex]];
  _draggingOnIndex = NSNotFound;
}

- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>)sender
{
  return [self _draggingEnteredOrUpdated: sender];
}

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint: [sender draggingLocation] fromView: nil];
  NSInteger index = [self _indexAtPoint: location];

  _draggingOnIndex = NSNotFound;
  [self setNeedsDisplayInRect: [self _frameForRowsAroundItemAtIndex: index]];
  return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>)sender
{
  NSPoint location = [self convertPoint: [sender draggingLocation] fromView: nil];
  NSInteger index = [self _indexAtPoint: location];
  index = (index > [_items count] - 1) ? [_items count] - 1 : index;
  
  BOOL result = NO;
  if ([_delegate respondsToSelector: @selector(collectionView:acceptDrop:index:dropOperation:)])
    {
      // TODO: dropOperation should be retrieved from the validateDrop delegate method.
      result = [_delegate collectionView: self
                             acceptDrop: sender
                                  index: index
                          dropOperation: NSCollectionViewDropOn];
    }
  return result;
}

- (BOOL) wantsPeriodicDraggingUpdates
{
  return YES;
}

/* New methods for later versions of macOS */

// 10.11 methods...

/* Locating Items and Views */

- (NSArray *) visibleItems
{
  return _visibleItems;
}

- (NSSet *) indexPathsForVisibleItems
{
  return _indexPathsForVisibleItems;
}

- (NSArray *) visibleSupplementaryViewsOfKind: (NSCollectionViewSupplementaryElementKind)elementKind
{
  return [_visibleSupplementaryViews objectForKey: elementKind];
}

- (NSSet *) indexPathsForVisibleSupplementaryElementsOfKind: (NSCollectionViewSupplementaryElementKind)elementKind
{
  return nil;
}

- (NSIndexPath *) indexPathForItem: (NSCollectionViewItem *)item
{
  return nil;
}

- (NSIndexPath *) indexPathForItemAtPoint: (NSPoint)point
{
  return nil;
}

- (NSCollectionViewItem *) itemAtIndexPath: (NSIndexPath *)indexPath
{
  return nil;
}

- (NSView *)supplementaryViewForElementKind: (NSCollectionViewSupplementaryElementKind)elementKind 
                                atIndexPath: (NSIndexPath *)indexPath
{
  return nil;
}

- (void) scrollToItemsAtIndexPaths: (NSSet *)indexPaths 
                    scrollPosition: (NSCollectionViewScrollPosition)scrollPosition
{
}

/* Creating Collection view Items */

- (NSCollectionViewItem *) makeItemWithIdentifier: (NSUserInterfaceItemIdentifier)identifier 
                                     forIndexPath: (NSIndexPath *)indexPath
{
  return nil;
}

- (void) registerClass: (Class)itemClass 
 forItemWithIdentifier: (NSUserInterfaceItemIdentifier)identifier
{
  [self registerClass: itemClass
        forSupplementaryViewOfKind: GSNoSupplementaryElement
       withIdentifier: identifier];
}

- (void) registerNib: (NSNib *)nib 
         forItemWithIdentifier: (NSUserInterfaceItemIdentifier)identifier
{
  [self registerNib: nib
        forSupplementaryViewOfKind: GSNoSupplementaryElement
     withIdentifier: identifier];
}

- (NSView *) makeSupplementaryViewOfKind: (NSCollectionViewSupplementaryElementKind)elementKind 
                          withIdentifier: (NSUserInterfaceItemIdentifier)identifier 
                            forIndexPath: (NSIndexPath *)indexPath
{
  return nil;
}

- (void) registerClass: (Class)viewClass 
         forSupplementaryViewOfKind: (NSCollectionViewSupplementaryElementKind)kind 
        withIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
  NSMapTable *t = nil;

  t = [_registeredClasses objectForKey: kind];
  if (t == nil)
    {
      t = [NSMapTable weakToWeakObjectsMapTable];
      [_registeredClasses setObject: t
                             forKey: kind];
    }

  [t setObject: viewClass forKey: identifier];
}

- (void) registerNib: (NSNib *)nib 
         forSupplementaryViewOfKind: (NSCollectionViewSupplementaryElementKind)kind 
      withIdentifier: (NSUserInterfaceItemIdentifier)identifier
{
  NSMapTable *t = nil;
  
  t = [_registeredNibs objectForKey: kind];
  if (t == nil)
    {
      t = [NSMapTable weakToWeakObjectsMapTable];
      [_registeredNibs setObject: t
                          forKey: kind];
    }

  [t setObject: nib forKey: identifier];
}

/* Providing the collection view's data */

- (id<NSCollectionViewDataSource>) dataSource
{
  return _dataSource;
}

- (void) setDataSource: (id<NSCollectionViewDataSource>)dataSource
{
  NSLog(@"Adding data source %@", dataSource);
  _dataSource = dataSource;
  [self reloadData];
}

/* Configuring the Collection view */

- (NSNib *) _nibForClass: (Class)cls
{
  NSString *clsName = NSStringFromClass(cls);
  NSNib *nib = [[NSNib alloc] initWithNibNamed: clsName
                                        bundle: [NSBundle bundleForClass: cls]];
  return nib;
}

- (NSView *) backgroundView
{
  return _backgroundView;
}

- (void) setBackgroundView: (NSView *)backgroundView
{
  _backgroundView = backgroundView; // weak since view retains this
}

- (BOOL) backgroundViewScrollsWithContent
{
  return _backgroundViewScrollsWithContent;
}

- (void) setBackgroundViewScrollsWithContent: (BOOL)f
{
  _backgroundViewScrollsWithContent = f;
}

/* Reloading Content */

- (void) reloadData
{
  NSInteger ns = [self numberOfSections];
  NSInteger cs = 0;
  
  NSLog(@"reloading data... number of sections = %ld, %@", ns, _collectionViewLayout);
  for (cs = 0; cs < ns; cs++)
    {
      NSInteger ni = [self numberOfItemsInSection: cs];
      NSInteger ci = 0;

      NSLog(@"current section = %ld", cs);
      
      for (ci = 0; ci < ni; ci++)
        {
          NSIndexPath *p = [NSIndexPath indexPathForItem: ci inSection: cs];
          NSCollectionViewItem *item =
            [_dataSource collectionView: self itemForRepresentedObjectAtIndexPath: p];
          NSNib *nib = [self _nibForClass: [item class]];
          BOOL loaded = [nib instantiateWithOwner: item
                                  topLevelObjects: NULL];
          
          if (!loaded)
            {
              NSLog(@"Could not load model %@", nib);
            }
          else
            {
              NSView *v = [item view];
              NSCollectionViewLayoutAttributes *attrs =
                [_collectionViewLayout layoutAttributesForItemAtIndexPath: p];
              NSRect f = [attrs frame];

              // set position of item based on currently selected layout...
              [v setFrame: f];
            }
        }
    }
}

- (void) reloadSections: (NSIndexSet *)sections
{
}

- (void) reloadItemsAtIndexPaths: (NSSet *)indexPaths
{
}

/* Prefetching Collection View Cells and Data */

- (id<NSCollectionViewPrefetching>) prefetchDataSource
{
  return _prefetchDataSource;
}

- (void) setPrefetchDataSource: (id<NSCollectionViewPrefetching>)prefetchDataSource
{
  _prefetchDataSource = prefetchDataSource;
}

/* Getting the State of the Collection View */

- (NSInteger) numberOfSections
{
  NSInteger n = 0;

  if ([_dataSource respondsToSelector: @selector(numberOfSectionsInCollectionView:)])
    {
      n = [_dataSource numberOfSectionsInCollectionView: self];
    }
  
  return n;
}

- (NSInteger) numberOfItemsInSection: (NSInteger)section
{
  NSInteger n = 0;

  // Since this is a required method by the delegate we can assume it's presence
  // if it is not there, tests on macOS indicate that an unrecognized selector
  // exception is thrown.
  n = [_dataSource collectionView: self numberOfItemsInSection: section];
  
  return n;
}

/* Inserting, Moving and Deleting Items */

- (void) insertItemsAtIndexPaths: (NSSet *)indexPaths
{
}

- (void) moveItemAtIndexPath: (NSIndexPath *)indexPath 
                 toIndexPath: (NSIndexPath *)newIndexPath
{
}

- (void) deleteItemsAtIndexPaths: (NSSet *)indexPaths
{
}

/* Inserting, Moving, Deleting and Collapsing Sections */

- (void) insertSections: (NSIndexSet *)sections
{
}

- (void) moveSection: (NSInteger)section 
           toSection: (NSInteger)newSection
{
}

- (void) deleteSections: (NSIndexSet *)sections
{
}

// 10.12 method...

- (IBAction) toggleSectionCollapse: (id)sender
{
}

// 10.11 methods...

- (BOOL) allowsEmptySelection
{
  return _allowsEmptySelection;
}

- (void) setAllowsEmptySelection: (BOOL)flag;
{
  _allowsEmptySelection = flag;
}

- (NSSet *) selectionIndexPaths // copy
{
  return nil;
}

- (IBAction) selectAll: (id)sender
{
}

- (IBAction) deselectAll: (id)sender
{
}

- (void) selectItemsAtIndexPaths: (NSSet *)indexPaths 
                  scrollPosition: (NSCollectionViewScrollPosition)scrollPosition
{
}

- (void) deselectItemsAtIndexPaths: (NSSet *)indexPaths
{
}

/* Getting Layout Information */

- (NSCollectionViewLayoutAttributes *) layoutAttributesForItemAtIndexPath: (NSIndexPath *)indexPath
{
  return nil;
}

- (NSCollectionViewLayoutAttributes *) layoutAttributesForSupplementaryElementOfKind: (NSCollectionViewSupplementaryElementKind)kind 
                                                                         atIndexPath: (NSIndexPath *)indexPath
{
  return nil;
}

/* Animating Multiple Changes */

- (void) performBatchUpdates: (GSCollectionViewPerformBatchUpdatesBlock) updates 
           completionHandler: (GSCollectionViewCompletionHandlerBlock) completionHandler
{
}

@end
