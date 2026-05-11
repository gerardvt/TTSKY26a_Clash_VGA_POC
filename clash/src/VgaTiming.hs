{-# LANGUAGE RecordWildCards #-}
-- Shared VGA 640x480 @ 60 Hz timing for Tiny Tapeout.
-- Mirrors spade/src/vga.spade — any Clash effect imports this module
-- instead of duplicating the counter and sync logic.
--
-- Standard timing (all counts zero-based):
--   Horizontal: 640 active | 16 FP | 96 sync (656-751) | 48 BP = 800 total
--   Vertical:   480 active | 10 FP |  2 sync (490-491) | 33 BP = 525 total
--   HSYNC and VSYNC are active low.
module VgaTiming where

import Clash.Prelude

-- | Timing signals produced each clock cycle.
-- Equivalent of Spade's VgaTiming struct.
data VgaTiming dom = VgaTiming
  { hCount    :: Signal dom (Unsigned 10)
  , vCount    :: Signal dom (Unsigned 10)
  , frameEnd  :: Signal dom Bool  -- true on the last clock of each frame
  , hSync     :: Signal dom Bit   -- active-low, for uo_out[7]
  , vSync     :: Signal dom Bit   -- active-low, for uo_out[3]
  , displayOn :: Signal dom Bool  -- true while hcount<640 && vcount<480
  }

-- | Produces standard 640x480 @ 60 Hz VGA timing signals.
-- Equivalent of Spade's vga_timing entity.
-- Use inside a HiddenClockResetEnable context, e.g.:
--   let VgaTiming{..} = vgaTiming
vgaTiming :: HiddenClockResetEnable System => VgaTiming System
vgaTiming = VgaTiming{..}
  where
    hCount = register 0 ((\h -> if h == 799 then 0 else h + 1) <$> hCount)

    vCount = register 0
      ((\h v -> if h == 799
                then if v == 524 then 0 else v + 1
                else v)
       <$> hCount <*> vCount)

    frameEnd  = (\h v -> h == 799 && v == 524) <$> hCount <*> vCount
    hSync     = (\h -> if h >= 656 && h < 752 then 0 else 1) <$> hCount
    vSync     = (\v -> if v >= 490 && v < 492 then 0 else 1) <$> vCount
    displayOn = (\h v -> h < 640 && v < 480) <$> hCount <*> vCount
