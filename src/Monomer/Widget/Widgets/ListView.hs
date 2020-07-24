{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}

module Monomer.Widget.Widgets.ListView (
  ListViewConfig(..),
  listView,
  listView_,
  listViewConfig
) where

import Control.Applicative ((<|>))
import Control.Lens (ALens', (&), (^#), (#~))
import Control.Monad
import Data.Default
import Data.Foldable (find)
import Data.List (foldl')
import Data.Maybe (fromMaybe, maybeToList)
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
import Monomer.Widget.Widgets.Container
import Monomer.Widget.Widgets.Label
import Monomer.Widget.Widgets.Scroll
import Monomer.Widget.Widgets.Spacer
import Monomer.Widget.Widgets.Stack

data ListViewConfig s e a = ListViewConfig {
  _lvValue :: WidgetValue s a,
  _lvItems :: Seq a,
  _lvItemToText :: a -> Text,
  _lvOnChange :: [Int -> a -> e],
  _lvOnChangeReq :: [Int -> WidgetRequest s],
  _lvSelectedColor :: Color,
  _lvHighlightedColor :: Color,
  _lvHoverColor :: Color
}

newtype ListViewState = ListViewState {
  _highlighted :: Int
}

newtype ListViewMessage = OnClickMessage Int deriving Typeable

listViewConfig :: WidgetValue s a -> Seq a -> (a -> Text) -> ListViewConfig s e a
listViewConfig value items itemToText = ListViewConfig {
  _lvValue = value,
  _lvItems = items,
  _lvItemToText = itemToText,
  _lvOnChange = [],
  _lvOnChangeReq = [],
  _lvSelectedColor = gray,
  _lvHighlightedColor = darkGray,
  _lvHoverColor = lightGray
}

listView :: (Traversable t, Eq a) => ALens' s a -> t a -> (a -> Text) -> WidgetInstance s e
listView field items itemToText = listView_ config where
  config = listViewConfig (WidgetLens field) newItems itemToText
  newItems = foldl' (|>) Empty items

listView_ :: (Eq a) => ListViewConfig s e a -> WidgetInstance s e
listView_ config = makeInstance (makeListView config newState) where
  newState = ListViewState 0

makeInstance :: Widget s e -> WidgetInstance s e
makeInstance widget = (defaultWidgetInstance "listView" widget) {
  _instanceFocusable = True
}

makeListView :: (Eq a) => ListViewConfig s e a -> ListViewState -> Widget s e
makeListView config state = createContainer {
    _widgetInit = containerInit init,
    _widgetGetState = makeState state,
    _widgetMerge = containerMergeTrees merge,
    _widgetHandleEvent = containerHandleEvent handleEvent,
    _widgetHandleMessage = containerHandleMessage handleMessage,
    _widgetPreferredSize = containerPreferredSize preferredSize,
    _widgetResize = containerResize resize
  }
  where
    currentValue wenv = widgetValueGet (_weModel wenv) (_lvValue config)

    createListView wenv newState widgetInstance = newInstance where
      selected = currentValue wenv
      path = _instancePath widgetInstance
      itemsList = makeItemsList config path selected (_highlighted newState)
      newInstance = widgetInstance {
        _instanceWidget = makeListView config newState,
        _instanceChildren = Seq.singleton (scroll itemsList)
      }

    init wenv widgetInstance = resultWidget $ createListView wenv state widgetInstance

    merge wenv oldState newInstance = resultWidget $ createListView wenv newState newInstance where
      newState = fromMaybe state (useState oldState)

    handleEvent wenv target evt widgetInstance = case evt of
      KeyAction mode code status
        | isKeyDown code && status == KeyPressed -> handleHighlightNext wenv widgetInstance
        | isKeyUp code && status == KeyPressed -> handleHighlightPrev wenv widgetInstance
        | isKeyReturn code && status == KeyPressed -> Just $ selectItem wenv widgetInstance (_highlighted state)
      _ -> Nothing

    handleHighlightNext wenv widgetInstance = highlightItem wenv widgetInstance nextIdx where
      tempIdx = _highlighted state
      nextIdx = if tempIdx < length (_lvItems config) - 1 then tempIdx + 1 else tempIdx

    handleHighlightPrev wenv widgetInstance = highlightItem wenv widgetInstance nextIdx where
      tempIdx = _highlighted state
      nextIdx = if tempIdx > 0 then tempIdx - 1 else tempIdx

    handleMessage wenv target message widgetInstance = fmap handleSelect (cast message) where
      handleSelect (OnClickMessage idx) = selectItem wenv widgetInstance idx

    highlightItem wenv widgetInstance nextIdx = Just $ widgetResult { _resultRequests = requests } where
      newState = ListViewState nextIdx
      newWidget = makeListView config newState
      -- ListView's merge uses the old widget's state. Since we want the newly created state, the old widget is replaced here
      oldInstance = widgetInstance {
        _instanceWidget = newWidget
      }
      -- ListView's tree will be rebuilt in merge, before merging its children, so it does not matter what we currently have
      newInstance = oldInstance
      widgetResult = _widgetMerge newWidget wenv oldInstance newInstance
      scrollToReq = itemScrollTo widgetInstance nextIdx
      requests = Seq.fromList scrollToReq

    selectItem wenv widgetInstance idx = resultReqs requests newInstance where
      selected = currentValue wenv
      value = fromMaybe selected (Seq.lookup idx (_lvItems config))
      valueSetReq = widgetValueSet (_lvValue config) value
      scrollToReq = itemScrollTo widgetInstance idx
      changeReqs = fmap ($ idx) (_lvOnChangeReq config)
      focusReq = [SetFocus $ _instancePath widgetInstance]
      requests = valueSetReq ++ scrollToReq ++ changeReqs ++ focusReq
      newState = ListViewState idx
      newInstance = widgetInstance {
        _instanceWidget = makeListView config newState
      }

    itemScrollTo widgetInstance idx = maybeToList (fmap makeScrollReq renderArea) where
      lookup idx inst = Seq.lookup idx (_instanceChildren inst)
      renderArea = fmap _instanceRenderArea $ pure widgetInstance
        >>= lookup 0 -- scroll
        >>= lookup 0 -- vstack
        >>= lookup idx -- item
      scrollPath = firstChildPath widgetInstance
      makeScrollReq rect = SendMessage scrollPath (ScrollTo rect)

    preferredSize wenv widgetInstance children reqs = Node sizeReq reqs where
      sizeReq = nodeValue $ Seq.index reqs 0

    resize wenv viewport renderArea widgetInstance children reqs = (widgetInstance, assignedArea) where
      assignedArea = Seq.singleton (viewport, renderArea)

makeItemsList :: (Eq a) => ListViewConfig s e a -> Path -> a -> Int -> WidgetInstance s e
makeItemsList lvConfig lvPath selected highlightedIdx = makeItemsList where
  ListViewConfig{..} = lvConfig
  isSelected item = item == selected
  selectedColor item = if isSelected item then Just _lvSelectedColor else Nothing
  highlightedColor idx = if idx == highlightedIdx then Just _lvHighlightedColor else Nothing
  pairs = Seq.zip (Seq.fromList [0..length _lvItems]) _lvItems
  itemStyle idx item = def {
    _styleColor = selectedColor item <|> highlightedColor idx,
    _styleHover = Just _lvHoverColor
  }
  itemConfig idx = containerConfig {
    _ctOnClickReq = [SendMessage lvPath (OnClickMessage idx)]
  }
  makeItem idx item = container config content `style` itemStyle idx item where
    config = itemConfig idx
    content = label (_lvItemToText item)
  makeItemsList = vstack $ fmap (uncurry makeItem) pairs