-- Interactive VGA plasma for Tiny Tapeout — 640x480 @ 60 Hz, 25 MHz pixel clock.
--
-- TT VGA PMOD pin mapping on uo_out[7:0]:
--   [7] hsync  [6] B0  [5] G0  [4] R0
--   [3] vsync  [2] B1  [1] G1  [0] R1
--
-- ui_in controls:
--   [0]     pause:   freeze animation
--   [2:1]   pattern: 00=three-wave plasma  01=two-wave (h+v)  10=diagonal  11=XOR plasma
--   [4:3]   speed:   frame counter step 1/2/4/8 per frame
--   [5]     invert:  complement plasmaV before colour mapping
--   [7:6]   palette: 00=RGB 120° offsets  01=shifted hue  10=fire  11=greyscale
{-# LANGUAGE RecordWildCards #-}
module Top where

import Clash.Prelude
import Clash.Annotations.TopEntity (PortName(..))
import VgaTiming

{-# ANN topEntity (Synthesize
  { t_name   = "tt_um_gerardvt_clash_poc"
  , t_inputs = [ PortName "clk"
               , PortName "rst_n"
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
    plasmaEffect uiIn uioIn

-- Triangle wave: rises 0→254 over i=0..127, falls 254→0 over i=128..255.
triWave :: Unsigned 8 -> Unsigned 8
triWave i
  | i < 128   = i `shiftL` 1
  | otherwise = (255 - i) `shiftL` 1

plasmaEffect
  :: HiddenClockResetEnable System
  => Signal System (BitVector 8)
  -> Signal System (BitVector 8)
  -> ( Signal System (BitVector 8)
     , Signal System (BitVector 8)
     , Signal System (BitVector 8)
     )
plasmaEffect uiIn _uioIn = (uoOut, pure 0, pure 0)
  where
    VgaTiming{ hCount, vCount, frameEnd, hSync, vSync, displayOn } = vgaTiming

    -- Decode ui_in
    uiU     = unpack <$> uiIn                              :: Signal System (Unsigned 8)
    pauseSig = (\u -> testBit u 0)              <$> uiU   :: Signal System Bool
    patSig   = (\u -> truncateB (u `shiftR` 1)) <$> uiU   :: Signal System (Unsigned 2)
    spdSig   = (\u -> truncateB (u `shiftR` 3)) <$> uiU   :: Signal System (Unsigned 2)
    invSig   = (\u -> testBit u 5)              <$> uiU   :: Signal System Bool
    palSig   = (\u -> truncateB (u `shiftR` 6)) <$> uiU   :: Signal System (Unsigned 2)

    stepSig :: Signal System (Unsigned 8)
    stepSig = (\spd -> case spd of
        0 -> 1; 1 -> 2; 2 -> 4; _ -> 8) <$> spdSig

    -- Frame counter: advances by step each frame unless paused.
    t :: Signal System (Unsigned 8)
    t = register 0 ((\fe p s t' -> if fe && not p then t' + s else t')
        <$> frameEnd <*> pauseSig <*> stepSig <*> t)

    uoOut = pixel <$> hCount <*> vCount <*> t
                  <*> hSync  <*> vSync  <*> displayOn
                  <*> patSig <*> invSig <*> palSig

pixel
  :: Unsigned 10  -- hCount
  -> Unsigned 10  -- vCount
  -> Unsigned 8   -- frame counter
  -> Bit          -- hSync
  -> Bit          -- vSync
  -> Bool         -- displayOn
  -> Unsigned 2   -- pattern select
  -> Bool         -- invert
  -> Unsigned 2   -- palette select
  -> BitVector 8
pixel h v t hs vs on pat inv pal
  | not on    = pack (hs, z, z, z, vs, z, z, z)
  | otherwise = pack (hs, b0, g0, r0, vs, b1, g1, r1)
  where
    z = 0 :: Bit

    hx   :: Unsigned 8
    hx   = truncateB (h `shiftR` 1)
    vy   :: Unsigned 8
    vy   = truncateB (v `shiftR` 1)
    diag :: Unsigned 8
    diag = truncateB ((resize h + resize v :: Unsigned 11) `shiftR` 2)

    plasmaRaw :: Unsigned 8
    plasmaRaw = case pat of
        0 -> let s1 = resize (triWave (hx   + t))     :: Unsigned 10
                 s2 = resize (triWave (vy   + t))     :: Unsigned 10
                 s3 = resize (triWave (diag + t + t)) :: Unsigned 10
             in truncateB ((s1 + s2 + s3) `shiftR` 2)
        1 -> let s1 = resize (triWave (hx + t)) :: Unsigned 9
                 s2 = resize (triWave (vy + t)) :: Unsigned 9
             in truncateB ((s1 + s2) `shiftR` 1)
        2 -> let s3a = resize (triWave (diag + t))       :: Unsigned 9
                 s3b = resize (triWave (diag + t + 128)) :: Unsigned 9
             in truncateB ((s3a + s3b) `shiftR` 1)
        _ -> (hx `xor` vy) + t

    plasmaV :: Unsigned 8
    plasmaV = if inv then 255 - plasmaRaw else plasmaRaw

    rgb2 :: (Unsigned 8, Unsigned 8, Unsigned 8)
    rgb2 = case pal of
        0 -> ( triWave  plasmaV        `shiftR` 6
             , triWave (plasmaV +  85) `shiftR` 6
             , triWave (plasmaV + 171) `shiftR` 6 )
        1 -> ( triWave (plasmaV +  64) `shiftR` 6
             , triWave (plasmaV + 149) `shiftR` 6
             , triWave (plasmaV + 213) `shiftR` 6 )
        2 -> ( triWave  plasmaV        `shiftR` 6
             , triWave (plasmaV +  64) `shiftR` 6
             , 0 )
        _ -> ( plasmaV `shiftR` 6
             , plasmaV `shiftR` 6
             , plasmaV `shiftR` 6 )
    (r2, g2, b2) = rgb2

    r1 = boolToBit (testBit r2 1); r0 = boolToBit (testBit r2 0)
    g1 = boolToBit (testBit g2 1); g0 = boolToBit (testBit g2 0)
    b1 = boolToBit (testBit b2 1); b0 = boolToBit (testBit b2 0)
