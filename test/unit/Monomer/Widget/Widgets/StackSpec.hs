{-# LANGUAGE RecordWildCards #-}
{- HLINT ignore "Reduce duplication" -}

module Monomer.Widget.Widgets.StackSpec (spec) where

import Data.Text (Text)
import Test.Hspec

import qualified Data.Sequence as Seq

import Monomer.Common.Geometry
import Monomer.Event.Types
import Monomer.Widget.Types
import Monomer.Widget.TestUtil
import Monomer.Widget.Util
import Monomer.Widget.Widgets.Label
import Monomer.Widget.Widgets.Stack

spec :: Spec
spec = describe "Stack" $ do
  preferredSize
  resize

preferredSize :: Spec
preferredSize = describe "preferredSize" $ do
  preferredSizeEmpty
  preferredSizeItems

preferredSizeEmpty :: Spec
preferredSizeEmpty = describe "empty" $ do
  it "should return size (0, 0)" $
    _srSize `shouldBe` Size 0 0

  it "should return Flexible width policy" $
    _srPolicyWidth `shouldBe` FlexibleSize

  it "should return Strict height policy" $
    _srPolicyHeight `shouldBe` FlexibleSize

  where
    wenv = mockWenv ()
    vstackInst = vstack []
    SizeReq{..} = instancePreferredSize wenv vstackInst

preferredSizeItems :: Spec
preferredSizeItems = describe "several items" $ do
  it "should return size (80, 60)" $
    _srSize `shouldBe` Size 80 60

  it "should return Flexible width policy" $
    _srPolicyWidth `shouldBe` FlexibleSize

  it "should return Strict height policy" $
    _srPolicyHeight `shouldBe` FlexibleSize

  where
    wenv = mockWenv ()
    vstackInst = vstack [
        label "Hello",
        label "how",
        label "are you?"
      ]
    SizeReq{..} = instancePreferredSize wenv vstackInst

resize :: Spec
resize = describe "resize" $ do
  resizeEmpty
  resizeItemsH
  resizeItemsV

resizeEmpty :: Spec
resizeEmpty = describe "empty" $ do
  it "should have the provided viewport size" $
    viewport `shouldBe` vp

  it "should not have children" $
    children `shouldSatisfy` Seq.null

  where
    wenv = mockWenv ()
    vp = Rect 0 0 640 480
    vstackInst = vstack []
    newInst = instanceResize wenv vp vstackInst
    viewport = _wiViewport newInst
    children = _wiChildren newInst

resizeItemsH :: Spec
resizeItemsH = describe "several items" $ do
  it "should have the provided viewport size" $
    viewport `shouldBe` vp

  it "should assign the same viewport size to each children" $
    childrenVp `shouldBe` Seq.fromList [cvp1, cvp2, cvp3]

  it "should assign the same renderArea size to each children" $
    childrenRa `shouldBe` Seq.fromList [cvp1, cvp2, cvp3]

  where
    wenv = mockWenv ()
    vp = Rect 0 0 480 640
    cvp1 = Rect   0 0 112 640
    cvp2 = Rect 112 0 256 640
    cvp3 = Rect 368 0 112 640
    hstackInst = hstack [
        label "Label 1",
        label "Label Number Two",
        label "Label 3"
      ]
    newInst = instanceResize wenv vp hstackInst
    viewport = _wiViewport newInst
    childrenVp = _wiViewport <$> _wiChildren newInst
    childrenRa = _wiRenderArea <$> _wiChildren newInst

resizeItemsV :: Spec
resizeItemsV = describe "several items" $ do
  it "should have the provided viewport size" $
    viewport `shouldBe` vp

  it "should assign the same viewport size to each children" $
    childrenVp `shouldBe` Seq.fromList [cvp1, cvp2, cvp3]

  it "should assign the same renderArea size to each children" $
    childrenRa `shouldBe` Seq.fromList [cvp1, cvp2, cvp3]

  where
    wenv = mockWenv ()
    vp = Rect 0 0 640 480
    cvp1 = Rect 0  0 640 20
    cvp2 = Rect 0 20 640 20
    cvp3 = Rect 0 40 640 20
    vstackInst = vstack [
        label "Label 1",
        label "Label Number Two",
        label "Label 3"
      ]
    newInst = instanceResize wenv vp vstackInst
    viewport = _wiViewport newInst
    childrenVp = _wiViewport <$> _wiChildren newInst
    childrenRa = _wiRenderArea <$> _wiChildren newInst