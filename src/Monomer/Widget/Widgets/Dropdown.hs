{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}

module Monomer.Widget.Widgets.Dropdown (
  DropdownConfig(..),
  dropdown,
  dropdownConfig
) where

import Control.Applicative ((<|>))
import Control.Lens (ALens', (&), (^#), (#~))
import Control.Monad
import Data.Default
import Data.Foldable (find)
import Data.List (foldl')
import Data.Maybe (fromJust, fromMaybe, isJust)
import Data.Sequence (Seq(..), (<|), (|>))
import Data.Text (Text)
import Data.Traversable
import Data.Typeable (Typeable, cast)

import qualified Data.Map as M
import qualified Data.Sequence as Seq

import Monomer.Common.Geometry
import Monomer.Common.Style
import Monomer.Common.Tree
import Monomer.Event.Keyboard
import Monomer.Event.Types
import Monomer.Graphics.Color
import Monomer.Graphics.Drawing
import Monomer.Graphics.Renderer
import Monomer.Graphics.Types
import Monomer.Widget.BaseContainer
import Monomer.Widget.Types
import Monomer.Widget.Util
import Monomer.Widget.Widgets.ListView

data DropdownConfig s e a = DropdownConfig {
  _ddValue :: WidgetValue s a,
  _ddItems :: Seq a,
  _ddItemToText :: a -> Text,
  _ddOnChange :: [a -> e],
  _ddOnChangeReq :: [WidgetRequest s],
  _ddSelectedColor :: Color,
  _ddHighlightedColor :: Color,
  _ddHoverColor :: Color
}

newtype DropdownState = DropdownState {
  _isOpen :: Bool
}

newtype DropdownMessage = OnChangeMessage Int deriving Typeable

dropdownConfig :: WidgetValue s a -> Seq a -> (a -> Text) -> DropdownConfig s e a
dropdownConfig value items itemToText = DropdownConfig {
  _ddValue = value,
  _ddItems = items,
  _ddItemToText = itemToText,
  _ddOnChange = [],
  _ddOnChangeReq = [],
  _ddSelectedColor = gray,
  _ddHighlightedColor = darkGray,
  _ddHoverColor = lightGray
}

dropdown :: (Traversable t, Eq a) => ALens' s a -> t a -> (a -> Text) -> WidgetInstance s e
dropdown field items itemToText = dropdown_ config where
  config = dropdownConfig (WidgetLens field) newItems itemToText
  newItems = foldl' (|>) Empty items

dropdown_ :: (Eq a) => DropdownConfig s e a -> WidgetInstance s e
dropdown_ config = makeInstance (makeDropdown config newState) where
  newState = DropdownState False

makeInstance :: Widget s e -> WidgetInstance s e
makeInstance widget = (defaultWidgetInstance "dropdown" widget) {
  _instanceFocusable = True
}

makeDropdown :: (Eq a) => DropdownConfig s e a -> DropdownState -> Widget s e
makeDropdown config state = createContainer {
    _widgetInit = containerInit init,
    _widgetGetState = makeState state,
    _widgetMerge = containerMergeTrees merge,
    _widgetHandleEvent = containerHandleEvent handleEvent,
    _widgetHandleMessage = containerHandleMessage handleMessage,
    _widgetPreferredSize = containerPreferredSize preferredSize,
    _widgetResize = containerResize resize,
    _widgetRender = render
  }
  where
    isOpen = _isOpen state
    currentValue wenv = widgetValueGet (_weModel wenv) (_ddValue config)

    createDropdown wenv newState widgetInstance = newInstance where
      selected = currentValue wenv
      path = _instancePath widgetInstance
      newInstance = widgetInstance {
        _instanceWidget = makeDropdown config newState,
        _instanceChildren = Seq.singleton $ makeListView config path selected
      }

    init wenv widgetInstance = resultWidget $ createDropdown wenv state widgetInstance

    merge wenv oldState newInstance = resultWidget $ createDropdown wenv newState newInstance where
      newState = fromMaybe state (useState oldState)

    handleEvent wenv target evt widgetInstance = case evt of
      Click point _
        | openRequired point widgetInstance -> Just $ handleOpenDropdown wenv widgetInstance
        | closeRequired point widgetInstance -> Just $ handleCloseDropdown wenv widgetInstance
      KeyAction mode code status
        | isKeyDown code && not isOpen -> Just $ handleOpenDropdown wenv widgetInstance
        | isKeyEsc code && isOpen -> Just $ handleCloseDropdown wenv widgetInstance
      _
        | not isOpen -> Just $ resultReqs [IgnoreChildrenEvents] widgetInstance
        | otherwise -> Nothing

    openRequired point widgetInstance = not isOpen && inViewport where
      inViewport = pointInRect point (_instanceViewport widgetInstance)

    closeRequired point widgetInstance = isOpen && not inOverlay where
      inOverlay = case Seq.lookup 0 (_instanceChildren widgetInstance) of
        Just inst -> pointInRect point (_instanceViewport inst)
        Nothing -> False

    handleOpenDropdown wenv widgetInstance = resultReqs requests newInstance where
      selected = currentValue wenv
      selectedIdx = fromMaybe 0 (Seq.elemIndexL selected (_ddItems config))
      newState = DropdownState True
      newInstance = widgetInstance {
        _instanceWidget = makeDropdown config newState
      }
      path = _instancePath widgetInstance
      lvPath = firstChildPath widgetInstance
      requests = [SetOverlay path, SetFocus lvPath]

    handleCloseDropdown wenv widgetInstance = resultReqs requests newInstance where
      path = _instancePath widgetInstance
      newState = DropdownState False
      newInstance = widgetInstance {
        _instanceWidget = makeDropdown config newState
      }
      requests = [ResetOverlay, SetFocus path]

    handleMessage wenv target message widgetInstance = cast message
      >>= \(OnChangeMessage idx) -> Seq.lookup idx (_ddItems config)
      >>= \value -> Just $ handleOnChange wenv idx value widgetInstance

    handleOnChange wenv idx item widgetInstance = WidgetResult (reqs <> newReqs) (events <> newEvents) newInstance where
      WidgetResult reqs events newInstance = handleCloseDropdown wenv widgetInstance
      newReqs = Seq.fromList $ widgetValueSet (_ddValue config) item
      newEvents = Seq.fromList $ fmap ($ item) (_ddOnChange config)

    preferredSize wenv widgetInstance children reqs = Node sizeReq reqs where
      Style{..} = _instanceStyle widgetInstance
      size = getTextBounds wenv _styleText (dropdownLabel wenv)
      sizeReq = SizeReq size FlexibleSize StrictSize

    resize wenv viewport renderArea widgetInstance children reqs = (widgetInstance, assignedArea) where
      childrenReqs = Seq.zip children reqs
      area = case Seq.lookup 0 childrenReqs of
        Just (child, reqChild) -> (oViewport, oRenderArea) where
          reqHeight = _h . _sizeRequested . nodeValue $ reqChild
          maxHeight = min reqHeight 150
          oViewport = viewport { _ry = _ry viewport + _rh viewport, _rh = maxHeight }
          oRenderArea = renderArea { _ry = _ry renderArea + _rh viewport }
        Nothing -> (viewport, renderArea)
      assignedArea = Seq.singleton area

    render renderer wenv WidgetInstance{..} =
      do
        drawStyledBackground renderer _instanceRenderArea _instanceStyle
        drawStyledText_ renderer _instanceRenderArea _instanceStyle (dropdownLabel wenv)

        when (isOpen && isJust listViewOverlay) $
          createOverlay renderer $ renderOverlay renderer wenv (fromJust listViewOverlay)
      where
        listViewOverlay = Seq.lookup 0 _instanceChildren

    renderOverlay renderer wenv overlayInstance = renderAction where
      renderAction = _widgetRender (_instanceWidget overlayInstance) renderer wenv overlayInstance

    dropdownLabel wenv = _ddItemToText config $ currentValue wenv

makeListView :: (Eq a) => DropdownConfig s e a -> Path -> a -> WidgetInstance s e
makeListView DropdownConfig{..} dropdownPath selected = listView_ lvConfig where
  lvConfig = ListViewConfig {
    _lvValue = WidgetValue selected,
    _lvItems = _ddItems,
    _lvItemToText = _ddItemToText,
    _lvOnChange = [],
    _lvOnChangeReq = [SendMessage dropdownPath . OnChangeMessage],
    _lvSelectedColor = _ddSelectedColor,
    _lvHighlightedColor = _ddHighlightedColor,
    _lvHoverColor = _ddHoverColor
  }