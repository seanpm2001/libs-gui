/** <title>NSMenuView</title>

   Copyright (C) 1999 Free Software Foundation, Inc.

   Author: Fred Kiefer <FredKiefer@gmx.de>
   Date: Sep 2001
   Author: David Lazaro Saz <khelekir@encomix.es>
   Date: Oct 1999
   Author: Michael Hanni <mhanni@sprintmail.com>
   Date: 1999
   
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
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/

#include <Foundation/NSRunLoop.h>

#include <AppKit/NSApplication.h>
#include <AppKit/NSEvent.h>
#include <AppKit/NSFont.h>
#include <AppKit/NSMenuView.h>
#include <AppKit/NSMenu.h>
#include <AppKit/NSButton.h>
#include <AppKit/NSWindow.h>
#include <AppKit/PSOperators.h>

#include <Foundation/NSDebug.h>

#include <AppKit/NSImage.h>

/*
  NSMenuView contains:

  a) Title, if needed, this is a subview
  b) menu items
*/

/* A menu's title is an instance of this class */
@class NSButton;

@interface NSMenuWindowTitleView : NSView
{
  NSMenu       *menu;
  NSButton     *button;
  NSSize       imageSize;
  NSDictionary *attr;
}

- (NSSize) titleSize;
- (void) addCloseButton;
- (void) removeCloseButton;
- (void) createButton;
- (void) setMenu: (NSMenu*)menu;
- (NSMenu*) menu;

@end

@implementation NSMenuView

static NSRect
_addLeftBorderOffsetToRect(NSRect aRect)
{
  aRect.origin.x--;
  aRect.size.width++;

  return aRect;
}

/*
 * Class methods.
 */
+ (float) menuBarHeight
{
  static float height = 0.0;

  if (height == 0.0)
    {
      NSFont *font = [NSFont menuFontOfSize: 0.0];

      /* Should make up 23 for the default font */
      height = ([font boundingRectForFont].size.height) + 8;
      if (height < 23)
	height = 23;
    }

  return height;
}

/*
 * NSView overrides
 */
- (BOOL) acceptsFirstMouse: (NSEvent*)theEvent
{
  return YES;
}

// We do not want to popup menus in this menu.
- (id) menuForEvent: (NSEvent*) theEvent
{
  NSDebugLLog (@"NSMenu", @"Query for menu in view");
  return nil;
}

/*
 * Init methods.
 */
- (id) initWithFrame: (NSRect)aFrame
{
  self = [super initWithFrame: aFrame];

  [self setFont: [NSFont menuFontOfSize: 0.0]];

  _highlightedItemIndex = -1;
  _horizontalEdgePad = 4.;

  /* Set the necessary offset for the menuView. That is, how many pixels 
   * do we need for our left side border line.
   */
 _leftBorderOffset = 1;

  // Create an array to store our menu item cells.
  _itemCells = [NSMutableArray new];

  return self;
}

- (id)initAsTearOff
{
  [self initWithFrame: NSZeroRect];
	
  if (_menu)
    [_menu setTornOff: YES];
  
  return self;
}

- (void) dealloc
{
  // We must remove the menu view from the menu list of observers.
  if (_menu != nil)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self  
					    name: nil
					    object: _menu];
    }

  /* Clean the pointer to us stored into the _itemCells.  */
  [_itemCells makeObjectsPerformSelector: @selector(setMenuView:)
	      withObject: nil];

  RELEASE(_itemCells);
  RELEASE(_font);

  [super dealloc];
}

/*
 * Getting and Setting Menu View Attributes
 */
- (void) setMenu: (NSMenu*)menu
{
  NSNotificationCenter	*theCenter = [NSNotificationCenter defaultCenter];

  if (_menu != nil)
    {
      // Remove this menu view from the old menu list of observers.
      [theCenter removeObserver: self  name: nil  object: _menu];
    }

  /* menu is retaining us, so we should not be retaining menu.  */
  _menu = menu;
  _items_link = [_menu itemArray];

  if (_menu != nil)
    {
      // Add this menu view to the menu's list of observers.
      [theCenter addObserver: self
		    selector: @selector(itemChanged:)
		        name: NSMenuDidChangeItemNotification
                      object: _menu];

      [theCenter addObserver: self
		    selector: @selector(itemAdded:)
		        name: NSMenuDidAddItemNotification
                      object: _menu];

      [theCenter addObserver: self
                    selector: @selector(itemRemoved:)
                        name: NSMenuDidRemoveItemNotification
                      object: _menu];
    }

  // Force menu view's layout to be recalculated.
  [self setNeedsSizing: YES];

  [self update];
}

- (NSMenu*) menu
{
  return _menu;
}

- (void) setHorizontal: (BOOL)flag
{
  _horizontal = flag;
}

- (BOOL) isHorizontal
{
  return _horizontal;
}

- (void) setFont: (NSFont*)font
{
  ASSIGN(_font, font);
  if (_font != nil)
    {
      NSRect r;
  
      r = [_font boundingRectForFont];
      /* Should make up 110, 20 for default font */
      _cellSize = NSMakeSize (r.size.width * 10., r.size.height + 6.);

      if (_cellSize.height < 20)
	_cellSize.height = 20;

      [self setNeedsSizing: YES];
    }
}

- (NSFont*) font
{
  return _font;
}

- (void) setHighlightedItemIndex: (int)index
{
  NSMenuItemCell *aCell;

  if (index == _highlightedItemIndex)
    return;

  // Unhighlight old
  if (_highlightedItemIndex != -1)
    {
      aCell  = [_itemCells objectAtIndex: _highlightedItemIndex];
      [aCell setHighlighted: NO];
      [self setNeedsDisplayForItemAtIndex: _highlightedItemIndex];
    }

  // Set ivar to new index.
  _highlightedItemIndex = index;

  // Highlight new
  if (_highlightedItemIndex != -1) 
    {
      aCell  = [_itemCells objectAtIndex: _highlightedItemIndex];
      [aCell setHighlighted: YES];
      [self setNeedsDisplayForItemAtIndex: _highlightedItemIndex];
    } 
}

- (int) highlightedItemIndex
{
  return _highlightedItemIndex;
}

- (void) setMenuItemCell: (NSMenuItemCell *)cell
	  forItemAtIndex: (int)index
{
  NSMenuItem *anItem = [_items_link objectAtIndex: index];
  
  [_itemCells replaceObjectAtIndex: index withObject: cell];

  [cell setMenuItem: anItem];
  [cell setMenuView: self];

  if ([self highlightedItemIndex] == index)
    [cell setHighlighted: YES];
  else
    [cell setHighlighted: NO];

  // Mark the new cell and the menu view as needing resizing.
  [cell setNeedsSizing: YES];
  [self setNeedsSizing: YES];
}

- (NSMenuItemCell*) menuItemCellForItemAtIndex: (int)index
{
  return [_itemCells objectAtIndex: index];
}

- (NSMenuView*) attachedMenuView
{
  return [[_menu attachedMenu] menuRepresentation];
}

- (NSMenu*) attachedMenu
{
  return [_menu attachedMenu];
}

- (BOOL) isAttached
{
  return [_menu isAttached];
}

- (BOOL) isTornOff
{
  return [_menu isTornOff];
}

- (void) setHorizontalEdgePadding: (float)pad
{
  _horizontalEdgePad = pad;
  [self setNeedsSizing: YES];
}

- (float) horizontalEdgePadding
{
  return _horizontalEdgePad;
}

/*
 * Notification Methods
 */
- (void) itemChanged: (NSNotification*)notification
{
  int index = [[[notification userInfo] objectForKey: @"NSMenuItemIndex"]
		intValue];

  // Mark the cell associated with the item as needing resizing.
  [[_itemCells objectAtIndex: index] setNeedsSizing: YES];

  // Mark the menu view as needing to be resized.
  [self setNeedsSizing: YES];
}

- (void) itemAdded: (NSNotification*)notification
{
  int         index  = [[[notification userInfo]
			  objectForKey: @"NSMenuItemIndex"] intValue];
  NSMenuItem *anItem = [_items_link objectAtIndex: index];
  id          aCell  = [NSMenuItemCell new];
  int wasHighlighted = _highlightedItemIndex;

  [aCell setMenuItem: anItem];
  [aCell setMenuView: self];
  [aCell setFont: _font];

  /* Unlight the previous highlighted cell if the index of the highlighted
   * cell will be ruined up by the insertion of the new cell.  */
  if (wasHighlighted >= index)
    {
      [self setHighlightedItemIndex: -1];
    }
  
  [_itemCells insertObject: aCell atIndex: index];
  
  /* Restore the highlighted cell, with the new index for it.  */
  if (wasHighlighted >= index)
    {
      /* Please note that if wasHighlighted == -1, it shouldn't be possible
       * to be here.  */
      [self setHighlightedItemIndex: ++wasHighlighted];
    }

  [aCell setNeedsSizing: YES];
  RELEASE(aCell);

  // Mark the menu view as needing to be resized.
  [self setNeedsSizing: YES];
}

- (void) itemRemoved: (NSNotification*)notification
{
  int wasHighlighted = [self highlightedItemIndex];
  int index = [[[notification userInfo] objectForKey: @"NSMenuItemIndex"]
		intValue];

  if (index <= wasHighlighted)
    {
      [self setHighlightedItemIndex: -1];
    }
  [_itemCells removeObjectAtIndex: index];

  if (wasHighlighted > index)
    {
      [self setHighlightedItemIndex: --wasHighlighted];
    }
  // Mark the menu view as needing to be resized.
  [self setNeedsSizing: YES];
}

/*
 * Working with Submenus.
 */

- (void) detachSubmenu
{
  NSMenu     *attachedMenu = [_menu attachedMenu];
  NSMenuView *attachedMenuView;

  if (!attachedMenu)
    return;

  attachedMenuView = [attachedMenu menuRepresentation];

  [attachedMenuView detachSubmenu];

  NSDebugLLog (@"NSMenu", @"detach submenu: %@ from: %@",
               attachedMenu, _menu);
  
  if ([attachedMenu isTransient])
    {
      [attachedMenu closeTransient];
    }
  else
    {
      [attachedMenu close];
    }
}

- (void) attachSubmenuForItemAtIndex: (int)index
{
  /*
   * Transient menus are used for torn-off menus, which are already on the
   * screen and for sons of transient menus.  As transients disappear as
   * soon as we release the mouse the user will be able to leave submenus
   * open on the screen and interact with other menus at the same time.
   */
  NSMenu *attachableMenu;

  if (index < 0)
    {
      return;
    }
  
  attachableMenu = [[_items_link objectAtIndex: index] submenu];

  if ([attachableMenu isTornOff] || [_menu isTransient])
    {
      NSDebugLLog (@"NSMenu",  @"Will open transient: %@", attachableMenu);
      [attachableMenu displayTransient];
      [[attachableMenu menuRepresentation] setHighlightedItemIndex: -1]; 
    }
  else
    {
      NSDebugLLog (@"NSMenu",  @"Will open normal: %@", attachableMenu);
      [attachableMenu display];
    }
}

/*
 * Calculating Menu Geometry
 */
- (void) update
{
  NSDebugLLog (@"NSMenu", @"update called on menu view");

  if (![_menu _ownedByPopUp] && !_titleView)
    {
      // Add title view. If this menu not owned by popup
      _titleView = [[NSMenuWindowTitleView alloc] init];
      [self addSubview: _titleView];
      RELEASE(_titleView);
    }
  else if ([_menu _ownedByPopUp] && _titleView)
    {
      // Remove title view if this menu owned by popup
      [_titleView removeFromSuperview];
      _titleView = nil;
    }
  
  if ((_titleView != nil) && ([_titleView menu] == nil))
    {
      [_titleView setMenu: _menu];
    }

  // Resize it anyway.
  [self sizeToFit];

  // Just quit here if we are a popup.
  if ([_menu _ownedByPopUp])
    return;
  
  if ([_menu isTornOff] && ![_menu isTransient])
    {
      [_titleView addCloseButton];
    }
  else
    {
      [_titleView removeCloseButton];
    }
}

- (void) setNeedsSizing: (BOOL)flag
{
  _needsSizing = flag;
}

- (BOOL) needsSizing
{
  return _needsSizing;
}

- (void) sizeToFit
{
  unsigned i;
  unsigned howMany = [_itemCells count];
  unsigned wideTitleView = 1;
  float    neededImageAndTitleWidth = 0.0;
  float    neededKeyEquivalentWidth = 0.0;
  float    neededStateImageWidth = 0.0;
  float    accumulatedOffset = 0.0;
  float    popupImageWidth = 0.0;
  float    menuBarHeight = 0.0;

  // Popup menu doesn't need title bar
  if (![_menu _ownedByPopUp] && _titleView)
    {
      menuBarHeight = [[self class] menuBarHeight];
      neededImageAndTitleWidth = [_titleView titleSize].width;
    }
  else
    {
      menuBarHeight += _leftBorderOffset;
    }
  
  for (i = 0; i < howMany; i++)
    {
      float aStateImageWidth;
      float aTitleWidth;
      float anImageWidth;
      float anImageAndTitleWidth;
      float aKeyEquivalentWidth;
      NSMenuItemCell *aCell = [_itemCells objectAtIndex: i];
      
      // State image area.
      aStateImageWidth = [aCell stateImageWidth];
      
      // Title and Image area.
      aTitleWidth = [aCell titleWidth];
      anImageWidth = [aCell imageWidth];
      
      // Key equivalent area.
      aKeyEquivalentWidth = [aCell keyEquivalentWidth];
      
      switch ([aCell imagePosition])
        {
        case NSNoImage: 
          anImageAndTitleWidth = aTitleWidth;
          break;
          
        case NSImageOnly: 
          anImageAndTitleWidth = anImageWidth;
          break;
          
        case NSImageLeft: 
        case NSImageRight: 
          anImageAndTitleWidth = anImageWidth + aTitleWidth + xDist;
          break;
          
        case NSImageBelow: 
        case NSImageAbove: 
        case NSImageOverlaps: 
        default: 
          if (aTitleWidth > anImageWidth)
            anImageAndTitleWidth = aTitleWidth;
          else
            anImageAndTitleWidth = anImageWidth;
          break;
        }
      
      if (aStateImageWidth > neededStateImageWidth)
        neededStateImageWidth = aStateImageWidth;
      
      if (anImageAndTitleWidth > neededImageAndTitleWidth)
        neededImageAndTitleWidth = anImageAndTitleWidth;
		
      if (aKeyEquivalentWidth > neededKeyEquivalentWidth)
        neededKeyEquivalentWidth = aKeyEquivalentWidth;
      
      // Title view width less than item's left part width
      if ((anImageAndTitleWidth + aStateImageWidth) 
          > neededImageAndTitleWidth)
        wideTitleView = 0;
      
      // Popup menu has only one item with nibble or arrow image
      if (anImageWidth)
        popupImageWidth = anImageWidth;
    }
  
  // Cache the needed widths.
  _stateImageWidth = neededStateImageWidth;
  _imageAndTitleWidth = neededImageAndTitleWidth;
  _keyEqWidth = neededKeyEquivalentWidth;
  
  accumulatedOffset = _horizontalEdgePad;
  if (howMany)
    {
      // Calculate the offsets and cache them.
      if (neededStateImageWidth)
        {
          _stateImageOffset = accumulatedOffset;
          accumulatedOffset += neededStateImageWidth += _horizontalEdgePad;
        }
      
      if (neededImageAndTitleWidth)
        {
          _imageAndTitleOffset = accumulatedOffset;
          accumulatedOffset += neededImageAndTitleWidth;
        }
      
      if (wideTitleView)
        {
          _keyEqOffset = accumulatedOffset = neededImageAndTitleWidth
            + (3 * _horizontalEdgePad);
        }
      else
        {
          _keyEqOffset = accumulatedOffset += (2 * _horizontalEdgePad);
        }
      accumulatedOffset += neededKeyEquivalentWidth + _horizontalEdgePad; 
      
      if ([_menu supermenu] != nil && neededKeyEquivalentWidth < 8)
        {
          accumulatedOffset += 8 - neededKeyEquivalentWidth;
        }
    }
  else
    {
      accumulatedOffset += neededImageAndTitleWidth + 3 + 2;
      if ([_menu supermenu] != nil)
        accumulatedOffset += 15;
    }
  
  // Calculate frame size.
  if (![_menu _ownedByPopUp])
    {
      // Add the border width: 1 for left, 2 for right sides
      _cellSize.width = accumulatedOffset + 3;
    }
  else
    {
      _keyEqOffset = _cellSize.width - _keyEqWidth - popupImageWidth;
    }

  if (_horizontal == NO)
    {
      [self setFrameSize: NSMakeSize(_cellSize.width + _leftBorderOffset, 
				     (howMany * _cellSize.height) 
				     + menuBarHeight)];
      [_titleView setFrame: NSMakeRect (0, howMany * _cellSize.height,
					NSWidth (_bounds), menuBarHeight)];
    }
  else
    {
      [self setFrameSize: NSMakeSize(((howMany + 1) * _cellSize.width), 
				     _cellSize.height + _leftBorderOffset)];
      [_titleView setFrame: NSMakeRect (0, 0,
					_cellSize.width, _cellSize.height + 1)];
    }
  
  _needsSizing = NO;
}

- (float) stateImageOffset
{
  if (_needsSizing)
    [self sizeToFit];

  return _stateImageOffset;
}

- (float) stateImageWidth
{
  if (_needsSizing)
    [self sizeToFit];

  return _stateImageWidth;
}

- (float) imageAndTitleOffset
{
  if (_needsSizing)
    [self sizeToFit];

  return _imageAndTitleOffset;
}

- (float) imageAndTitleWidth
{
  if (_needsSizing)
    [self sizeToFit];

  return _imageAndTitleWidth;
}

- (float) keyEquivalentOffset
{
  if (_needsSizing)
    [self sizeToFit];

  return _keyEqOffset;
}

- (float) keyEquivalentWidth
{
  if (_needsSizing)
    [self sizeToFit];

  return _keyEqWidth;
}

- (NSRect) innerRect
{
  if (_horizontal == NO)
    {
      return NSMakeRect (_bounds.origin.x + _leftBorderOffset, 
			 _bounds.origin.y,
			 _bounds.size.width - _leftBorderOffset, 
			 _bounds.size.height);
    }
  else
    {
      return NSMakeRect (_bounds.origin.x, 
			 _bounds.origin.y + _leftBorderOffset,
			 _bounds.size.width, 
			 _bounds.size.height - _leftBorderOffset);
    }
}

- (NSRect) rectOfItemAtIndex: (int)index
{
  NSRect theRect;

  if (_needsSizing == YES)
    {
      [self sizeToFit];
    }

  /* Fiddle with the origin so that the item rect is shifted 1 pixel over 
   * so we do not draw on the heavy line at origin.x = 0.
   */
  if (_horizontal == NO)
    {
      theRect.origin.y = _cellSize.height * ([_itemCells count] - index - 1);
      theRect.origin.x = _leftBorderOffset;
    }
  else
    {
      theRect.origin.x = _cellSize.width * (index + 1);
      theRect.origin.y = 0;
    }
  theRect.size = _cellSize;

  /* NOTE: This returns the correct NSRect for drawing cells, but nothing 
   * else (unless we are a popup). This rect will have to be modified for 
   * event calculation, etc..
   */
  return theRect;
}

- (int) indexOfItemAtPoint: (NSPoint)point
{
  unsigned howMany = [_itemCells count];
  unsigned i;

  for (i = 0; i < howMany; i++)
    {
      NSRect aRect = [self rectOfItemAtIndex: i];
      
      aRect = _addLeftBorderOffsetToRect(aRect);

      if (NSMouseInRect(point, aRect, NO))
        return (int)i;
    }

  return -1;
}

- (void) setNeedsDisplayForItemAtIndex: (int)index
{
  NSRect aRect;

  aRect = [self rectOfItemAtIndex: index];
  aRect = _addLeftBorderOffsetToRect(aRect);
  [self setNeedsDisplayInRect: aRect];
}

- (NSPoint) locationForSubmenu: (NSMenu *)aSubmenu
{
  NSRect frame = [_window frame];
  NSRect submenuFrame;

  if (_needsSizing)
    [self sizeToFit];

  if (aSubmenu)
    submenuFrame = [[[aSubmenu menuRepresentation] window] frame];
  else
    submenuFrame = NSZeroRect;

  if (_horizontal == NO)
    {
      if (NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", 
				 [aSubmenu menuRepresentation])
	  == GSWindowMakerInterfaceStyle)
	{
	  NSRect aRect = [self rectOfItemAtIndex: 
	    [_menu indexOfItemWithSubmenu: aSubmenu]];
	  NSPoint subOrigin = [_window convertBaseToScreen: 
	    NSMakePoint(aRect.origin.x, aRect.origin.y)];

	  return NSMakePoint (NSMaxX(frame),
			      subOrigin.y - NSHeight(submenuFrame) - 3 +
			      2*[NSMenuView menuBarHeight]);
	}
      else
	{
	  return NSMakePoint(NSMaxX(frame),
			     NSMaxY(frame) - NSHeight(submenuFrame));
	}
    }
  else
    {
      NSRect aRect = [self rectOfItemAtIndex: 
                       [_menu indexOfItemWithSubmenu: aSubmenu]];
      NSPoint subOrigin = [_window convertBaseToScreen: 
	                            NSMakePoint(NSMinX(aRect),
		                    NSMinY(aRect))];

      return NSMakePoint(subOrigin.x, subOrigin.y - NSHeight(submenuFrame));
    }
}

- (void) resizeWindowWithMaxHeight: (float)maxHeight
{
  // FIXME set the menuview's window to max height in order to keep on screen?
}

- (void) setWindowFrameForAttachingToRect: (NSRect)screenRect 
				 onScreen: (NSScreen*)screen
			    preferredEdge: (NSRectEdge)edge
			popUpSelectedItem: (int)selectedItemIndex
{
  NSRect r;
  NSRect cellFrame;
  NSRect screenFrame;
  int items = [_itemCells count];
  
  // Convert the screen rect to our view
  cellFrame.size = screenRect.size;
  cellFrame.origin = [_window convertScreenToBase: screenRect.origin];
  cellFrame = [self convertRect: cellFrame fromView: nil];
 
  // Only call update if needed.
  if ((NSEqualSizes(_cellSize, cellFrame.size) == NO) || _needsSizing)
    {
      _cellSize = cellFrame.size;
      [self update];
    }
  
  /*
   * Compute the frame
   */
  screenFrame = screenRect;
  if (items > 0)
    {
      float f;

      if (_horizontal == NO)
	{
	  f = screenRect.size.height * (items - 1);
	  screenFrame.size.height += f + _leftBorderOffset;
	  screenFrame.origin.y -= f;
	  screenFrame.size.width += _leftBorderOffset;
	  screenFrame.origin.x -= _leftBorderOffset;
	  // Compute position for popups, if needed
	  if (selectedItemIndex != -1) 
	    {
	      screenFrame.origin.y += screenRect.size.height * selectedItemIndex;
	    }
	}
      else
	{
 	  f = screenRect.size.width * (items - 1);
 	  screenFrame.size.width += f;
	  // Compute position for popups, if needed
	  if (selectedItemIndex != -1) 
	    {
	      screenFrame.origin.x -= screenRect.size.width * selectedItemIndex;
	    }
	}
    }  
  
  // Get the frameRect
  r = [NSWindow frameRectForContentRect: screenFrame
		styleMask: [_window styleMask]];
  
  // Update position,if needed, using the preferredEdge;
  // TODO
  
  // Set the window frame
  [_window setFrame: r display: NO]; 
}

/*
 * Drawing.
 */
- (BOOL) isOpaque
{
  return YES;
}

- (void) drawRect: (NSRect)rect
{
  int        i;
  int        howMany = [_itemCells count];
  NSRectEdge sides[] = {NSMinXEdge, NSMaxYEdge};
  float      grays[] = {NSDarkGray, NSDarkGray};

  // Draw the dark gray upper left lines.
  NSDrawTiledRects(rect, rect, sides, grays, 2);
  
  // Draw the menu cells.
  for (i = 0; i < howMany; i++)
    {
      NSRect		aRect;
      NSMenuItemCell	*aCell;
      
      aRect = [self rectOfItemAtIndex: i];
      if (NSIntersectsRect(rect, aRect) == YES)
        {
          aCell = [_itemCells objectAtIndex: i];
          [aCell drawWithFrame: aRect inView: self];
        }
    }
}

/*
 * Event Handling
 */
- (void) performActionWithHighlightingForItemAtIndex: (int)index
{
  NSMenu     *candidateMenu = _menu;
  NSMenuView *targetMenuView;
  int        indexToHighlight = index;
  int        oldHighlightedIndex;

  for (;;)
    {
      NSMenu *superMenu = [candidateMenu supermenu];

      if (superMenu == nil
          || [candidateMenu isAttached]
          || [candidateMenu isTornOff])
        {
          targetMenuView = [candidateMenu menuRepresentation];

          break;
        }
      else
        {
          indexToHighlight = [superMenu indexOfItemWithSubmenu: candidateMenu];
          candidateMenu = superMenu;
        }
    }
	
  oldHighlightedIndex = [targetMenuView highlightedItemIndex];
  [targetMenuView setHighlightedItemIndex: indexToHighlight];

  /* We need to let the run loop run a little so that the fact that
   * the item is highlighted gets displayed on screen.
   */
  [[NSRunLoop currentRunLoop] 
    runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

  [_menu performActionForItemAtIndex: index];

  if (![_menu _ownedByPopUp])
    {
      [targetMenuView setHighlightedItemIndex: oldHighlightedIndex];
    }
}

#define MOVE_THRESHOLD_DELTA 2.0
#define DELAY_MULTIPLIER     10

- (BOOL) trackWithEvent: (NSEvent*)event
{
  unsigned	eventMask = NSPeriodicMask;
  NSDate        *theDistantFuture = [NSDate distantFuture];
  NSPoint	lastLocation = {0,0};
  BOOL		justAttachedNewSubmenu = NO;
  BOOL          subMenusNeedRemoving = YES;
  int		delayCount = 0;
  int           indexOfActionToExecute = -1;
  NSEvent	*original;
  NSEventType	type;
  NSEventType	end;

  /*
   * The original event is unused except to determine whether the method
   * was invoked in response to a right or left mouse down.
   * We pass the same event on when we want tracking to move into a
   * submenu.
   */
  original = AUTORELEASE(RETAIN(event));

  type = [event type];

  if (type == NSRightMouseDown || type == NSRightMouseDragged)
    {
      end = NSRightMouseUp;
      eventMask |= NSRightMouseUpMask | NSRightMouseDraggedMask;
    }
  else if (type == NSOtherMouseDown || type == NSOtherMouseDragged)
    {
      end = NSOtherMouseUp;
      eventMask |= NSOtherMouseUpMask | NSOtherMouseDraggedMask;
    }
  else if (type == NSLeftMouseDown || type == NSLeftMouseDragged)
    {
      end = NSLeftMouseUp;
      eventMask |= NSLeftMouseUpMask | NSLeftMouseDraggedMask;
    }
  else
    {
      NSLog (@"Unexpected event: %d during event tracking in NSMenuView", type);
      end = NSLeftMouseUp;
      eventMask |= NSLeftMouseUpMask | NSLeftMouseDraggedMask;
    }

  do
    {
      if (type == NSPeriodic || event == original)
        {
          NSPoint	location;
          int           index;

          location     = [_window mouseLocationOutsideOfEventStream];
          index        = [self indexOfItemAtPoint: location];

          /*
           * 1 - if menus is only partly visible and the mouse is at the
           *     edge of the screen we move the menu so it will be visible.
           */ 
          if ([_menu isPartlyOffScreen])
            {
              NSPoint pointerLoc = [_window convertBaseToScreen: location];
              /*
               * The +/-1 in the y - direction is because the flipping
               * between X-coordinates and GNUstep coordinates let the
               * GNUstep screen coordinates start with 1.
               */
              if (pointerLoc.x == 0 || pointerLoc.y == 1
                  || pointerLoc.x == [[_window screen] frame].size.width - 1
                  || pointerLoc.y == [[_window screen] frame].size.height)
                [_menu shiftOnScreen];
            }


          /*
           * 2 - Check if we have to reset the justAttachedNewSubmenu
           * flag to NO.
           */
          if (justAttachedNewSubmenu && index != -1
              && index != _highlightedItemIndex)
            { 
              if (location.x - lastLocation.x > MOVE_THRESHOLD_DELTA)
                {
                  delayCount ++;
                  if (delayCount >= DELAY_MULTIPLIER)
                    {
                      justAttachedNewSubmenu = NO;
                    }
                }
              else
                {
                  justAttachedNewSubmenu = NO;
                }
            }


          // 3 - If we have moved outside this menu, take appropriate action
          if (index == -1)
            {
              NSPoint   locationInScreenCoordinates;
              NSWindow *windowUnderMouse;
              NSMenu   *candidateMenu;

              subMenusNeedRemoving = NO;

              locationInScreenCoordinates
                = [_window convertBaseToScreen: location];

              /*
               * 3a - Check if moved into one of the ancester menus.
               *      This is tricky, there are a few possibilities:
               *          We are a transient attached menu of a
               *          non-transient menu
               *          We are a non-transient attached menu
               *          We are a root: isTornOff of AppMenu
               */
              candidateMenu = [_menu supermenu];
              while (candidateMenu  
                     && !NSMouseInRect (locationInScreenCoordinates, 
                                        [[candidateMenu window] frame], 
                                        NO) // not found yet
                     && (! ([candidateMenu isTornOff] 
                            && ![candidateMenu isTransient]))  // no root of display tree
                     && [candidateMenu isAttached]) // has displayed parent
                {
                  candidateMenu = [candidateMenu supermenu];
                }

              if (candidateMenu != nil
                  && NSMouseInRect (locationInScreenCoordinates,
                                    [[candidateMenu window] frame], NO))
                {
                  // The call to fetch attachedMenu is not needed. But putting
                  // it here avoids flicker when we go back to an ancestor 
		  // menu and the attached menu is already correct.
                  [[[candidateMenu attachedMenu] menuRepresentation]
                    detachSubmenu];
                  
                  // Reset highlighted index for this menu.
                  // This way if we return to this submenu later there 
                  // won't be a highlighted item.
                  [[[candidateMenu attachedMenu] menuRepresentation]
                    setHighlightedItemIndex: -1];
                  
                  return [[candidateMenu menuRepresentation]
                           trackWithEvent: original];
                }

              // 3b - Check if we enter the attached submenu
              windowUnderMouse = [[_menu attachedMenu] window];
              if (windowUnderMouse != nil
                  && NSMouseInRect (locationInScreenCoordinates,
                                    [windowUnderMouse frame], NO))
                {
                  BOOL wasTransient = [_menu isTransient];
                  BOOL subMenuResult;

                  subMenuResult
                    = [[self attachedMenuView] trackWithEvent: original];
                  if (subMenuResult && wasTransient == [_menu isTransient])
                    {
                      [self detachSubmenu];
                    }
                  return subMenuResult;
                }
            }

          // 4 - We changed the selected item and should update.
          if (!justAttachedNewSubmenu && index != _highlightedItemIndex)
            {
              subMenusNeedRemoving = NO;
              [self detachSubmenu];
              [self setHighlightedItemIndex: index];

              // WO: Question?  Why the ivar _items_link
              if (index >= 0 && [[_items_link objectAtIndex: index] submenu])
                {
                  [self attachSubmenuForItemAtIndex: index];
                  justAttachedNewSubmenu = YES;
                  delayCount = 0;
                }
            }

          // Update last seen location for the justAttachedNewSubmenu logic.
          lastLocation = location;
        }

      event = [NSApp nextEventMatchingMask: eventMask
        untilDate: theDistantFuture
        inMode: NSEventTrackingRunLoopMode
        dequeue: YES];
      type = [event type];
    }
  while (type != end);

  /*
   * Ok, we released the mouse
   * There are now a few possibilities:
   * A - We released the mouse outside the menu.
   *     Then we want the situation as it was before
   *     we entered everything.
   * B - We released the mouse on a submenu item
   *     (i) - this was highlighted before we started clicking:
   *           Remove attached menus
   *     (ii) - this was not highlighted before pressed the mouse button;
   *            Keep attached menus.
   * C - We released the mouse above an ordinary action:
   *     Execute the action.
   *
   *  In case A, B and C we want the transient menus to be removed
   *  In case A and C we want to remove the menus that were created
   *  during the dragging.
   *
   *  So we should do the following things:
   * 
   * 1 - Stop periodic events,
   * 2 - Determine the action.
   * 3 - Remove the Transient menus from the screen.
   * 4 - Perform the action if there is one.
   */

  [NSEvent stopPeriodicEvents];

  /*
   * We need to store this, because _highlightedItemIndex
   * will not be valid after we removed this menu from the screen.
   */
  indexOfActionToExecute = _highlightedItemIndex;

  // remove transient menus. --------------------------------------------
    {
      NSMenu *currentMenu = _menu;

      while (currentMenu && ![currentMenu isTransient])
        {
          currentMenu = [currentMenu attachedMenu];
        }

      while ([currentMenu isTransient] &&
             [currentMenu supermenu])
        {
          currentMenu = [currentMenu supermenu];
        }

      [[currentMenu menuRepresentation] detachSubmenu];

      if ([currentMenu isTransient])
        {
          [currentMenu closeTransient];
        }
    }

  // ---------------------------------------------------------------------
  if (indexOfActionToExecute == -1)
    {
      return YES;
    }

  if (indexOfActionToExecute >= 0
      && [_menu attachedMenu] != nil && [_menu attachedMenu] ==
      [[_items_link objectAtIndex: indexOfActionToExecute] submenu])
    {
      if (subMenusNeedRemoving)
        {
          [self detachSubmenu];
        }
      // Clicked on a submenu.
      return NO;
    }

  [_menu performActionForItemAtIndex: indexOfActionToExecute];

  /*
   * Remove highlighting.
   * We first check if it still highlighted because it could be the
   * case that we choose an action in a transient window which
   * has already dissappeared.  
   */
  if (indexOfActionToExecute == _highlightedItemIndex)
    {
      [self setHighlightedItemIndex: -1];
    }
  return YES;
}

/**
   This method is called when the user clicks on a button in the menu.
	 Or, if a right click happens and the app menu is brought up.

   The original position is stored, so we can restore the position of menu.
	 The position of the menu can change during the event tracking because
   the menu will automatillay move when parts are outside the screen and 
	 the user move the mouse pointer to the edge of the screen.
*/
- (void) mouseDown: (NSEvent*)theEvent
{
  NSRect	currentFrame;
  NSRect	originalFrame;
  NSPoint	currentTopLeft;
  NSPoint	originalTopLeft;
  BOOL          restorePosition;
  /*
   * Only for non transient menus do we want
   * to remember the position.
   */ 
  restorePosition = ![_menu isTransient];

  if (restorePosition)
    { // store old position;
      originalFrame = [_window frame];
      originalTopLeft = originalFrame.origin;
      originalTopLeft.y += originalFrame.size.height;
    }
  
  [NSEvent startPeriodicEventsAfterDelay: 0.1 withPeriod: 0.01];
  [self trackWithEvent: theEvent];
  [NSEvent stopPeriodicEvents];

  if (restorePosition)
    {
      currentFrame = [_window frame];
      currentTopLeft = currentFrame.origin;
      currentTopLeft.y += currentFrame.size.height;

      if (NSEqualPoints(currentTopLeft, originalTopLeft) == NO)
        {
          NSPoint	origin = currentFrame.origin;
          
          origin.x += (originalTopLeft.x - currentTopLeft.x);
          origin.y += (originalTopLeft.y - currentTopLeft.y);
          [_menu nestedSetFrameOrigin: origin];
        }
    }
}

- (void) rightMouseDown: (NSEvent*) theEvent
{
  [self mouseDown: theEvent];
}

- (BOOL) performKeyEquivalent: (NSEvent *)theEvent
{
  return [_menu performKeyEquivalent: theEvent];
}


/*
 * NSCoding Protocol
 *
 * Normally unused because NSMenu does not encode its NSMenuView since
 * NSMenuView is considered a platform specific way of rendering the menu.
 */
- (void) encodeWithCoder: (NSCoder*)encoder
{
  [super encodeWithCoder: encoder];

  [encoder encodeObject: _itemCells];
  [encoder encodeObject: _font];
  [encoder encodeValueOfObjCType: @encode(BOOL) at: &_horizontal];
  [encoder encodeValueOfObjCType: @encode(float) at: &_horizontalEdgePad];
  [encoder encodeValueOfObjCType: @encode(NSSize) at: &_cellSize];
}

- (id) initWithCoder: (NSCoder*)decoder
{
  self = [super initWithCoder: decoder];

  [decoder decodeValueOfObjCType: @encode(id) at: &_itemCells];
  
  [_itemCells makeObjectsPerformSelector: @selector(setMenuView:)
	      withObject: self];

  [decoder decodeValueOfObjCType: @encode(id) at: &_font];
  [decoder decodeValueOfObjCType: @encode(BOOL) at: &_horizontal];
  [decoder decodeValueOfObjCType: @encode(float) at: &_horizontalEdgePad];
  [decoder decodeValueOfObjCType: @encode(NSSize) at: &_cellSize];

  _highlightedItemIndex = -1;
  _needsSizing = YES;

  return self;
}

@end

@implementation NSMenuView (GNUstepPrivate)

- (NSArray *)_itemCells
{
  return _itemCells;
}

@end

@implementation NSMenuWindowTitleView

- (id) init
{
  self = [super init];
  
  attr = nil;
  
  return self;
}

- (void) dealloc
{
  RELEASE (button);
  [super dealloc];
}

- (BOOL) acceptsFirstMouse: (NSEvent *)theEvent
{
  return YES;
} 
 
- (void) setMenu: (NSMenu*)aMenu
{
  menu = aMenu;
}

- (NSMenu*) menu
{
  return menu;
}
  
- (NSSize) titleSize
{
  if (attr == nil)
    {
      attr = [[NSDictionary alloc] initWithObjectsAndKeys: 
                                     [NSFont boldSystemFontOfSize: 0], 
                                     NSFontAttributeName,
                                     [NSColor windowFrameTextColor], 
                                     NSForegroundColorAttributeName,
                                     nil];
    }
  
  return [[menu title] sizeWithAttributes: attr];
}

- (void) drawRect: (NSRect)rect
{
  NSRect     workRect = [self bounds];
  NSSize     titleSize;
  NSRectEdge sides[] = {NSMinXEdge, NSMaxYEdge};
  float      grays[] = {NSDarkGray, NSDarkGray};

  // Draw the dark gray upper left lines.
  workRect = NSDrawTiledRects(workRect, workRect, sides, grays, 2);
  
  // Draw the title box's button.
  NSDrawButton(workRect, workRect);
  
  // Paint it Black!
  workRect.origin.x += 1;
  workRect.origin.y += 2;
  workRect.size.height -= 3;
  workRect.size.width -= 3;
  [[NSColor windowFrameColor] set];
  NSRectFill(workRect);
  
  // Draw the title
  titleSize = [self titleSize];
  workRect.origin.x += 4;
  workRect.origin.y = NSMidY (workRect) - titleSize.height / 2;
  workRect.size.height = titleSize.height;
  [[menu title] drawInRect: workRect  withAttributes: attr];
}

- (void) mouseDown: (NSEvent*)theEvent
{
  NSPoint  lastLocation;
  NSPoint  location;
  NSPoint  oldOrigin;
  NSPoint  newOrigin;
  unsigned eventMask = NSLeftMouseUpMask | NSLeftMouseDraggedMask 
                       | NSMouseMovedMask;

  NSDebugLLog (@"NSMenu", @"Mouse down in title!");

  lastLocation = [theEvent locationInWindow];

  if (![menu isTornOff] && [menu supermenu])
    {
      [menu setTornOff: YES];
    }

  oldOrigin = [_window frame].origin;

  while ([theEvent type] != NSLeftMouseUp)
    {
      /* Inner loop that gets and (quickly) handles all events that have
       * already arrived.*/
      while (theEvent && [theEvent type] != NSLeftMouseUp)
	{
	  location = [_window convertBaseToScreen:
	    [theEvent locationInWindow]];
	  //	  location = [_window convertBaseToScreen: location];
	  /* Note the event here. Don't do any expensive handling. 
	   * Only get events that have already a$. */
	  theEvent = [NSApp nextEventMatchingMask: eventMask
	                                untilDate: [NSDate distantPast]
	                                   inMode: NSEventTrackingRunLoopMode
	                                  dequeue: YES];
	} 

      if ([theEvent type] == NSLeftMouseUp)
	break;

      /* Location is position of the cursor in screen coordinate system.
	 lastLocation is the position of the cursor in the window. Thus, 
	 we want the origin to satisfy origin+lastLocation=location: */
      newOrigin.x = location.x - lastLocation.x;
      newOrigin.y = location.y - lastLocation.y;

      /* No more events right now. Do expensive handling, 
	 like drawing, here. */
      if (NSEqualPoints(oldOrigin, newOrigin) == NO)
	{
	  oldOrigin = newOrigin;
	  [menu nestedSetFrameOrigin: newOrigin];
	}

      /* Get the next event, blocking if necessary.
       * No limit, block until we get an event. */
      theEvent = [NSApp nextEventMatchingMask: eventMask
	                            untilDate: nil
	                               inMode: NSEventTrackingRunLoopMode
	                              dequeue: YES];
    }
}

- (void) createButton
{
  // create the menu's close button
  NSImage *closeImage = [NSImage imageNamed: @"common_Close"];
  NSImage *closeHImage = [NSImage imageNamed: @"common_CloseH"];
  NSRect  rect;
        
  imageSize = [closeImage size];
  rect = NSMakeRect (_frame.size.width - imageSize.width - 4,
                     (_frame.size.height - imageSize.height) / 2 ,
                     imageSize.width, imageSize.height );
  
  button = [[NSButton alloc] initWithFrame: rect];
  [button setRefusesFirstResponder: YES];
  [button setButtonType: NSMomentaryChangeButton];
  [button setImagePosition: NSImageOnly];
  [button setBordered: NO];
  [button setAutoresizingMask: NSViewMinXMargin];
  [button setImage: closeImage];
  [button setAlternateImage: closeHImage];
  [button setTarget: menu];
  [button setAction: @selector(_performMenuClose:)];
  
  [self setAutoresizingMask:
          NSViewMinXMargin | NSViewMinYMargin | NSViewMaxYMargin];
}
            
- (void) removeCloseButton
{
  [button removeFromSuperview];
}
  
- (void) addCloseButton
{
  if (button == nil)
    [self createButton];

  // Update location
  [button setFrameOrigin: 
            NSMakePoint (_frame.size.width - imageSize.width - 4,
                         (_frame.size.height - imageSize.height) / 2)];

  [self addSubview: button];
  [self setNeedsDisplay: YES];
}

// We do not need app menu over menu
- (void) rightMouseDown: (NSEvent*)theEvent
{
}

// We do not want to popup menus in this menu.
- (id) menuForEvent: (NSEvent*) theEvent
{
  return nil;
}

@end /* NSMenuWindowTitleView */

