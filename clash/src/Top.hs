-- VGA colour bars for Tiny Tapeout — 640x480 @ 60 Hz, 25 MHz pixel clock.
--
-- TT VGA PMOD pin mapping on uo_out[7:0]:
--   [7] hsync  [6] B0  [5] G0  [4] R0
--   [3] vsync  [2] B1  [1] G1  [0] R1
--
-- 8 colour bars of 80 pixels each (L→R):
--   White Yellow Cyan Green Magenta Red Blue Black
--
-- VGA timing comes from VgaTiming.hs (mirrors vga.spade).
{-# LANGUAGE RecordWildCards #-}
module Top where

import Clash.Prelude
import Clash.Annotations.TopEntity (PortName(..))
import VgaTiming

{-# ANN topEntity (Synthesize
  { t_name   = "tt_um_gerardvt_clash_poc"
  , t_inputs = [ PortName "clk"
               , PortName "rst_n"  -- active-low; converted internally
               , PortName "ena"
               , PortName "ui_in"
               , PortName "uio_in"
               ]
  , t_output  = PortProduct "" [ PortName "uo_out"
                               , PortName "uio_out"
                               , PortName "uio_oe"
                               ]
  }) #-}
{-# NOINLINE topEntity #-}
topEntity
  :: Clock System
  -> Signal System Bool            -- rst_n (active-low)
  -> Enable System
  -> Signal System (BitVector 8)   -- ui_in
  -> Signal System (BitVector 8)   -- uio_in
  -> ( Signal System (BitVector 8)   -- uo_out
     , Signal System (BitVector 8)   -- uio_out
     , Signal System (BitVector 8)   -- uio_oe
     )
topEntity clk rstN ena uiIn uioIn =
  withClockResetEnable clk (unsafeFromLowPolarity rstN) ena $
    vgaColourBars uiIn uioIn

vgaColourBars
  :: HiddenClockResetEnable System
  => Signal System (BitVector 8)
  -> Signal System (BitVector 8)
  -> ( Signal System (BitVector 8)
     , Signal System (BitVector 8)
     , Signal System (BitVector 8)
     )
vgaColourBars _uiIn _uioIn = (uoOut, pure 0, pure 0)
  where
    -- VGA timing from shared module (mirrors `let timing = inst vga::vga_timing(...)`)
    VgaTiming{ hCount, hSync, vSync, displayOn } = vgaTiming

    -- Colour bar channels, blanked outside the active display area.
    -- Bar boundaries at every 80 pixels (640 / 8 = 80).
    --
    --  hcount range  Colour    R  G  B
    --   0 –  79      White     1  1  1
    --  80 – 159      Yellow    1  1  0
    -- 160 – 239      Cyan      0  1  1
    -- 240 – 319      Green     0  1  0
    -- 320 – 399      Magenta   1  0  1
    -- 400 – 479      Red       1  0  0
    -- 480 – 559      Blue      0  0  1
    -- 560 – 639      Black     0  0  0
    r = (\d h -> boolToBit $ d && (h < 160 || (h >= 320 && h < 480)))
        <$> displayOn <*> hCount

    g = (\d h -> boolToBit $ d && h < 320)
        <$> displayOn <*> hCount

    b = (\d h -> boolToBit $ d && (h < 80
                               || (h >= 160 && h < 240)
                               || (h >= 320 && h < 400)
                               || (h >= 480 && h < 560)))
        <$> displayOn <*> hCount

    -- Pack uo_out[7:0] = {hsync, B0, G0, R0, vsync, B1, G1, R1}
    -- Both channel bits are identical (full saturation, no half-levels).
    uoOut = fmap pack $ bundle (hSync, b, g, r, vSync, b, g, r)
