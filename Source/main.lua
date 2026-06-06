-- main.lua -- Meowta Racer : an 80s-style pseudo-3D arcade racer for Playdate
-- Controls: CRANK or D-pad ◄► = steer | A = gas | B = brake | D-pad ▲▼ = HI/LO gear

import "CoreLibs/graphics"
import "CoreLibs/object"
import "audio"
import "road"

local gfx <const> = playdate.graphics
-- Road and Audio are globals defined by the imported files above

local SCREEN_W <const> = 400
local SCREEN_H <const> = 240
local HALF_W   <const> = 200
local FPS      <const> = 30
local DT       <const> = 1 / FPS

----------------------------------------------------------------------
-- Physics tunables
----------------------------------------------------------------------
local MAX_SPEED   <const> = 6000      -- = SEG_LEN(200) * FPS(30): cap so we never skip a segment
local LOW_CAP     <const> = MAX_SPEED * 0.50
local ACCEL_LOW   <const> = MAX_SPEED / 1.8
local ACCEL_HIGH  <const> = MAX_SPEED / 7.0
local BRAKING     <const> = -MAX_SPEED / 1.6
local DECEL       <const> = -MAX_SPEED / 9.0
local OFF_DECEL   <const> = -MAX_SPEED / 3.0
local OFF_CAP     <const> = MAX_SPEED * 0.35
local CENTRIFUGAL <const> = 0.0125     -- curve pulls you to the OUTSIDE; you must steer to hold a line
local STEER_K     <const> = 0.0060
local DPAD_STEER  <const> = 0.020

local CRASH_FRAMES <const> = 32        -- ~1.05s tumble after hitting a prop
local CRASH_SPIN   <const> = 900        -- total degrees of cartwheel

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local mode = "title"      -- "title" | "ready" | "play"
local position = 0
local playerX  = 0
local speed    = 0
local gear     = 1        -- 1 low, 2 high
local steerVis = 0        -- smoothed steering for sprite/lean
local shake    = 0
local distance = 0
local bestDist = 0
local steerInput = "none" -- "crank" | "dpad" | "none": what the player is steering with

local crashing  = false   -- in a crash tumble?
local crashT    = 0       -- frames left in the crash
local crashSpin = 0       -- accumulated tumble angle (degrees)
local damage    = 0       -- collisions this run

local bg, bgW, bgH
local bgX = 0
local player           -- imagetable
local titleImg         -- attract-screen background
local hudFont
local blink = 0        -- counter for the blinking prompt

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
local function setup()
  playdate.display.setRefreshRate(FPS)
  hudFont = gfx.getSystemFont()
  bg = gfx.image.new("images/bg")
  bgW, bgH = bg:getSize()
  player = gfx.imagetable.new("images/meowta")
  titleImg = gfx.image.new("images/title")
  Road.build()
  Audio.init()
  Audio.titleStart()
end

local function resetRun()
  position, playerX, speed, gear = 0, 0, 0, 1
  steerVis, shake, distance = 0, 0, 0
  crashing, crashT, crashSpin, damage = false, 0, 0, 0
  steerInput = "none"
end

----------------------------------------------------------------------
-- Background (parallax sky + mountains)
----------------------------------------------------------------------
local function drawBackground()
  gfx.clear(gfx.kColorWhite)
  local horizon = SCREEN_H / 2
  local y = horizon - bgH + 24
  local ox = (bgX % bgW)
  bg:draw(-ox, y)
  bg:draw(-ox + bgW, y)
  if -ox + bgW * 2 < SCREEN_W then bg:draw(-ox + bgW * 2, y) end
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local function drawHud()
  local mph = math.floor((speed / MAX_SPEED) * 180)
  -- speed readout box (top-left)
  gfx.setColor(gfx.kColorWhite); gfx.fillRect(2, 2, 96, 30)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(2, 2, 96, 30)
  gfx.drawText("*" .. mph .. "*", 8, 4)
  gfx.drawText("MPH  " .. (gear == 2 and "HI" or "LO"), 8, 18)

  -- speed bar (top-right)
  gfx.setColor(gfx.kColorWhite); gfx.fillRect(SCREEN_W-102, 2, 100, 12)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(SCREEN_W-102, 2, 100, 12)
  local w = math.floor((speed / MAX_SPEED) * 96)
  gfx.fillRect(SCREEN_W-100, 4, w, 8)

  -- damage tally (top centre)
  gfx.setColor(gfx.kColorWhite); gfx.fillRect(HALF_W-34, 2, 68, 16)
  gfx.setColor(gfx.kColorBlack); gfx.drawRect(HALF_W-34, 2, 68, 16)
  gfx.drawTextAligned("DMG " .. damage, HALF_W, 4, kTextAlignment.center)

  -- crank-docked warning: only when the player isn't already steering with the d-pad
  if playdate.isCrankDocked() and steerInput ~= "dpad" then
    gfx.setColor(gfx.kColorWhite); gfx.fillRect(SCREEN_W-150, SCREEN_H-18, 148, 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText("undock crank to steer", SCREEN_W-146, SCREEN_H-17)
  end
end

----------------------------------------------------------------------
-- Player car
----------------------------------------------------------------------
local function drawPlayer()
  local frame = 1
  if not crashing then
    if steerVis > 0.25 then frame = 3
    elseif steerVis < -0.25 then frame = 2 end
  end
  local img = player:getImage(frame)
  local w, h = img:getSize()

  -- crash tumble: cartwheel spin + a hop arc + a scale pulse + sideways skid
  if crashing then
    local p    = 1 - (crashT / CRASH_FRAMES)              -- 0..1 through the crash
    local rise = math.sin(math.min(1, p * 1.7) * math.pi) -- peaks early (~p=0.29) then settles
    local hop   = rise * 30                                -- lifts then drops
    local scale = 1.7 * (1.0 - 0.4 * rise)
    local cxp   = HALF_W + math.sin(p * math.pi * 2) * 26
    local cyp   = SCREEN_H - (h * 1.7) / 2 + 6 - hop
    gfx.setColor(gfx.kColorBlack)
    img:drawRotated(cxp, cyp, crashSpin, scale)
    return
  end

  local scale = 1.7
  local dw, dh = w * scale, h * scale

  local bob = (speed > MAX_SPEED*0.15) and ((math.floor(position/20) % 2) * 2) or 0
  local sx = (shake > 0) and (math.random(-3,3)) or 0
  local lean = steerVis * 14

  local x = HALF_W + lean + sx - dw/2
  local y = SCREEN_H - dh + 6 + bob

  gfx.setColor(gfx.kColorBlack)
  img:drawScaled(x, y, scale)
end

----------------------------------------------------------------------
-- Update : driving
----------------------------------------------------------------------
local function updateDriving()
  local seg = Road.segmentAt(position + 1500)   -- look slightly ahead for curve feel
  local speedPercent = speed / MAX_SPEED

  -- gears
  if playdate.buttonJustPressed(playdate.kButtonUp) then
    if gear ~= 2 then gear = 2; Audio.blip(660, 0.05) end
  elseif playdate.buttonJustPressed(playdate.kButtonDown) then
    if gear ~= 1 then gear = 1; Audio.blip(440, 0.05) end
  end

  -- throttle / brake
  if playdate.buttonIsPressed(playdate.kButtonA) then
    if gear == 1 then
      speed = speed + ACCEL_LOW * DT
    else
      speed = speed + ACCEL_HIGH * (0.3 + 0.7*speedPercent) * DT  -- bogs at low rpm
    end
  elseif playdate.buttonIsPressed(playdate.kButtonB) then
    speed = speed + BRAKING * DT
  else
    speed = speed + DECEL * DT
  end

  -- gear speed ceiling
  local cap = (gear == 1) and LOW_CAP or MAX_SPEED
  if speed > cap then speed = speed - (speed - cap) * 0.15 end  -- soft limiter
  if speed < 0 then speed = 0 end

  -- steering: crank primary, d-pad fallback
  local crankChange = playdate.getCrankChange()
  local steerGain = 0.4 + 0.6 * speedPercent
  local steer = crankChange * STEER_K * steerGain
  local leftHeld  = playdate.buttonIsPressed(playdate.kButtonLeft)
  local rightHeld = playdate.buttonIsPressed(playdate.kButtonRight)
  if leftHeld  then steer = steer - DPAD_STEER * steerGain end
  if rightHeld then steer = steer + DPAD_STEER * steerGain end
  if leftHeld or rightHeld then
    steerInput = "dpad"
  elseif crankChange ~= 0 and not playdate.isCrankDocked() then
    steerInput = "crank"
  end
  playerX = playerX + steer

  -- centrifugal force on curves
  playerX = playerX - (seg.curve * speedPercent * CENTRIFUGAL)

  -- off-road penalty
  local offRoad = math.abs(playerX) > 0.98
  if offRoad and speed > OFF_CAP then
    speed = speed + OFF_DECEL * DT
    shake = 4
  else
    if shake > 0 then shake = shake - 1 end
  end
  if playerX < -1.9 then playerX = -1.9 end
  if playerX >  1.9 then playerX =  1.9 end

  -- collision with a roadside prop -> enter crash tumble
  if Road.collisionAt(position, playerX) then
    crashing  = true
    crashT    = CRASH_FRAMES
    crashSpin = 90          -- instant quarter-turn kick so contact reads immediately
    damage    = damage + 1
    speed     = MAX_SPEED * 0.05
    shake     = 6
    Audio.blip(110, 0.18)
    return
  end

  -- advance
  position = (position + speed * DT) % Road.length()
  distance = distance + speed * DT
  if distance > bestDist then bestDist = distance end

  -- background parallax follows curve + speed
  bgX = bgX + seg.curve * speed * 0.005 * DT
  steerVis = steerVis + (math.max(-1, math.min(1, crankChange*0.04 + steer*20)) - steerVis) * 0.4

  Audio.engineUpdate(speedPercent, gear, offRoad)
end

----------------------------------------------------------------------
-- Update : crash tumble (no driving input while spinning)
----------------------------------------------------------------------
local function updateCrash()
  crashT = crashT - 1
  crashSpin = crashSpin + (CRASH_SPIN / CRASH_FRAMES)

  -- bleed to a crawl but keep inching forward so we clear the prop
  speed = speed + (DECEL * 2) * DT
  if speed < MAX_SPEED * 0.05 then speed = MAX_SPEED * 0.05 end
  position = (position + speed * DT) % Road.length()
  shake = 5

  Audio.engineUpdate(speed / MAX_SPEED, 1, true)

  if crashT <= 0 then
    crashing = false
    shake = 0
    -- nudge back onto the road so we don't immediately re-hit something
    if playerX < -0.6 then playerX = -0.6
    elseif playerX > 0.6 then playerX = 0.6 end
  end
end

----------------------------------------------------------------------
-- Title screen (attract) -- no control text here
----------------------------------------------------------------------
local function drawTitle()
  titleImg:draw(0, 0)

  -- hero car cruising on the grid
  local img = player:getImage(1)
  local w, h = img:getSize()
  local s = 1.35
  img:drawScaled(HALF_W - (w * s) / 2, SCREEN_H - h * s - 22, s)

  -- blinking prompt (dark pill so it reads on the misty foreground)
  blink = (blink + 1) % 60
  if blink < 42 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(HALF_W - 80, SCREEN_H - 20, 160, 16)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned("PRESS Ⓐ TO START", HALF_W, SCREEN_H - 18, kTextAlignment.center)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
  end

end

----------------------------------------------------------------------
-- Controls screen (shown after START, before driving)
----------------------------------------------------------------------
local function drawReady()
  gfx.clear(gfx.kColorBlack)
  local cx = HALF_W

  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  gfx.drawTextAligned("- HOW TO DRIVE -", cx, 34, kTextAlignment.center)
  gfx.drawTextAligned("CRANK  or  ◄ ►    steer", cx, 74, kTextAlignment.center)
  gfx.drawTextAligned("Ⓐ  gas        Ⓑ  brake", cx, 96, kTextAlignment.center)
  gfx.drawTextAligned("▲ / ▼    shift  HI / LO  gear", cx, 118, kTextAlignment.center)
  gfx.drawTextAligned("dodge the trees & signs", cx, 140, kTextAlignment.center)

  blink = (blink + 1) % 60
  if blink < 42 then
    gfx.drawTextAligned("PRESS Ⓐ TO START", cx, 186, kTextAlignment.center)
  end
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------
function playdate.update()
  if mode == "title" then
    drawTitle()
    Audio.titleUpdate()
    if playdate.buttonJustPressed(playdate.kButtonA) then
      mode = "ready"
    end
    return
  end

  if mode == "ready" then
    drawReady()
    Audio.titleUpdate()
    if playdate.buttonJustPressed(playdate.kButtonA) then
      mode = "play"
      resetRun()
      Audio.titleStop()
    end
    return
  end

  -- play
  if crashing then updateCrash() else updateDriving() end
  drawBackground()
  Road.render(position, playerX)
  drawPlayer()
  drawHud()

  if playdate.buttonJustPressed(playdate.kButtonB) and playdate.buttonIsPressed(playdate.kButtonUp) then
    -- B + Up : bail to title (quick reset gesture)
    mode = "title"; Audio.titleStart()
  end
end

setup()
