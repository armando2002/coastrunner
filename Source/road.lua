-- road.lua -- pseudo-3D road engine for CoastRunner
-- Technique: classic segment projection (Lou's / jakesgordon model) adapted to
-- the Playdate's 400x240 1-bit display. Road is rendered near->far with a
-- descending clip line so hills occlude correctly.

local gfx <const> = playdate.graphics
local geo <const> = playdate.geometry

Road = {}  -- global: Playdate's import() does not return module values

----------------------------------------------------------------------
-- Tunables (safe to tweak)
----------------------------------------------------------------------
local SCREEN_W <const> = 400
local SCREEN_H <const> = 240
local SEG_LEN  <const> = 200          -- length of a single road segment (world units)
local RUMBLE   <const> = 3            -- segments per rumble stripe band
local ROAD_W   <const> = 1100         -- road half-width (world units)
local CAM_H    <const> = 1500         -- camera height above road
local CAM_DEPTH<const> = 0.84         -- 1/tan(fov/2); ~100deg fov
local DRAW_DIST<const> = 120          -- segments drawn ahead
local SPRITE_SCALE <const> = 0.30 / 72 -- 72 = player sprite cell width

-- dither "blackness": 0 = white, 1 = solid black
local A_ROAD_L <const> = 0.06
local A_ROAD_D <const> = 0.16
local A_GRASS_L<const> = 0.50
local A_GRASS_D<const> = 0.64
local DITHER   <const> = gfx.image.kDitherTypeBayer8x8

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local segments = {}
local N = 0
local trackLen = 0

local imgPalm, imgSign

-- reusable polygons (avoid per-frame allocation)
local function newQuad()
  local p = geo.polygon.new(0,0, 0,0, 0,0, 0,0)
  p:close()
  return p
end
local qRoad   = newQuad()
local qRumbleL = newQuad()
local qRumbleR = newQuad()
local qLane    = newQuad()

----------------------------------------------------------------------
-- Track construction
----------------------------------------------------------------------
local function lastY()
  if N == 0 then return 0 end
  return segments[N].p2.world.y
end

local function addSegment(curve, y)
  local n = N
  local prevY = lastY()
  N = N + 1
  segments[N] = {
    index = n,
    curve = curve,
    dark  = (math.floor(n / RUMBLE) % 2) == 1,
    sprites = nil,
    p1 = { world={x=0,y=prevY,z=n*SEG_LEN},     camera={x=0,y=0,z=0}, screen={x=0,y=0,w=0,scale=0} },
    p2 = { world={x=0,y=y,    z=(n+1)*SEG_LEN}, camera={x=0,y=0,z=0}, screen={x=0,y=0,w=0,scale=0} },
  }
end

local function easeIn(a,b,p)    return a + (b-a)*p*p end
local function easeInOut(a,b,p) return a + (b-a)*(-math.cos(p*math.pi)/2 + 0.5) end

-- enter/hold/leave measured in segments; curve magnitude; height = elevation delta
local function addRoad(enter, hold, leave, curve, height)
  local startY = lastY()
  local endY   = startY + height
  local total  = enter + hold + leave
  for n=0,enter-1 do addSegment(easeIn(0, curve, n/enter),        easeInOut(startY,endY,n/total)) end
  for n=0,hold-1  do addSegment(curve,                            easeInOut(startY,endY,(enter+n)/total)) end
  for n=0,leave-1 do addSegment(easeInOut(curve, 0, n/leave),     easeInOut(startY,endY,(enter+hold+n)/total)) end
end

local function straight(len, height) addRoad(len, len, len, 0, height or 0) end
local function curve(len, c, height)  addRoad(len, len, len, c, height or 0) end

-- hitW (optional): lateral half-width in road units; if set, the prop is collidable
local function addSprite(segIndex, img, offset, hitW)
  local s = segments[segIndex]
  if not s then return end
  s.sprites = s.sprites or {}
  s.sprites[#s.sprites+1] = { img=img, offset=offset, hitW=hitW }
end

function Road.build()
  imgPalm = gfx.image.new("images/palm")
  imgSign = gfx.image.new("images/sign")

  segments = {}; N = 0

  straight(20, 0)
  curve(30,  2,  40)     -- gentle right, slight climb
  straight(15, 0)
  curve(40, -3, -30)     -- sweeping left, descent
  curve(20,  4,  0)      -- sharp right
  straight(20, 60)       -- climb
  curve(30, -2, -40)
  curve(30,  2,  20)
  straight(15, 0)
  curve(40, -4,  50)     -- big left over a crest
  curve(25,  3, -50)
  straight(10, 0)
  curve(30,  2,  30)
  curve(30, -3, -20)
  straight(25, 0)

  -- darken last segments so the loop seam reads as a start/finish line
  for i=N-RUMBLE+1, N do segments[i].dark = true end

  N = #segments
  trackLen = N * SEG_LEN

  -- LEVEL 1: sparse roadside scatter so a new driver isn't punished.
  -- Props sit beyond a free "shoulder": you can run wide onto the grass (speed
  -- penalty only) and only crash if you actually line up with a trunk/post.
  for i=1,N do
    local s = segments[i]
    if i % 22 == 0 then
      addSprite(i, imgPalm, -1.7 - (i%3)*0.15, 0.16)   -- left, set back; trunk-width hitbox
    elseif i % 22 == 11 then
      addSprite(i, imgPalm,  1.7 + (i%3)*0.15, 0.16)    -- right
    end
    -- an occasional chevron sign ahead of a real curve change
    if i < N and math.abs(segments[i+1].curve - s.curve) > 2.0 and i % 17 == 0 then
      addSprite(i, imgSign, s.curve > 0 and 1.5 or -1.5, 0.18)
    end
  end
end

function Road.length() return trackLen end

local function segIndexAt(z)
  return math.floor(z / SEG_LEN) % N
end

-- returns the segment table the camera/player is currently over
function Road.segmentAt(z)
  return segments[segIndexAt(z) + 1]
end

-- returns (true, sprite) if the player at (z, playerX) overlaps a collidable prop
function Road.collisionAt(z, playerX)
  local seg = segments[segIndexAt(z) + 1]
  if not seg or not seg.sprites then return false end
  for _,spr in ipairs(seg.sprites) do
    if spr.hitW and math.abs(playerX - spr.offset) < spr.hitW then
      return true, spr
    end
  end
  return false
end

local function interpolate(a,b,p) return a + (b-a)*p end
Road.interpolate = interpolate

----------------------------------------------------------------------
-- Projection
----------------------------------------------------------------------
local floor <const> = math.floor
local HALF_W <const> = SCREEN_W/2
local HALF_H <const> = SCREEN_H/2

local function project(p, camX, camY, camZ)
  local pc, ps, pw = p.camera, p.screen, p.world
  pc.x = pw.x - camX
  pc.y = pw.y - camY
  pc.z = pw.z - camZ
  local z = pc.z
  if z < 1 then z = 1 end
  local scale = CAM_DEPTH / z
  ps.scale = scale
  ps.x = HALF_W + (scale * pc.x * HALF_W)
  ps.y = HALF_H - (scale * pc.y * HALF_H)
  ps.w = scale * ROAD_W * HALF_W
end

----------------------------------------------------------------------
-- Segment rendering
----------------------------------------------------------------------
local kBlack <const> = gfx.kColorBlack
local kWhite <const> = gfx.kColorWhite

local function fillQuad(q, x1,y1, x2,y2, x3,y3, x4,y4)
  q:setPointAt(1, x1, y1)
  q:setPointAt(2, x2, y2)
  q:setPointAt(3, x3, y3)
  q:setPointAt(4, x4, y4)
  gfx.fillPolygon(q)
end

local function renderSegment(s)
  local p1, p2 = s.p1.screen, s.p2.screen
  local x1,y1,w1 = p1.x, p1.y, p1.w   -- near edge (lower on screen)
  local x2,y2,w2 = p2.x, p2.y, p2.w   -- far edge  (higher on screen)
  local bandH = y1 - y2
  if bandH < 1 then return end

  -- grass band (full width)
  gfx.setColor(kBlack)
  gfx.setDitherPattern(s.dark and A_GRASS_D or A_GRASS_L, DITHER)
  gfx.fillRect(0, floor(y2), SCREEN_W, floor(bandH) + 1)

  -- road surface
  gfx.setDitherPattern(s.dark and A_ROAD_D or A_ROAD_L, DITHER)
  fillQuad(qRoad, x1-w1, y1, x1+w1, y1, x2+w2, y2, x2-w2, y2)

  -- rumble strips (solid, alternating black/white -> barber-pole motion)
  local r1, r2 = w1/6, w2/6
  if s.dark then gfx.setColor(kBlack) else gfx.setColor(kWhite) end
  fillQuad(qRumbleL, x1-w1-r1, y1, x1-w1, y1, x2-w2, y2, x2-w2-r2, y2)
  fillQuad(qRumbleR, x1+w1, y1, x1+w1+r1, y1, x2+w2+r2, y2, x2+w2, y2)

  -- centre lane dashes (black, only on light segments)
  if not s.dark then
    local l1, l2 = w1/22, w2/22
    gfx.setColor(kBlack)
    fillQuad(qLane, x1-l1, y1, x1+l1, y1, x2+l2, y2, x2-l2, y2)
  end
end

local function renderSprites(s)
  if not s.sprites then return end
  local ps = s.p1.screen
  local scale = ps.scale
  local pixelScale = scale * HALF_W * SPRITE_SCALE * ROAD_W
  if pixelScale <= 0.02 then return end
  for _,spr in ipairs(s.sprites) do
    local img = spr.img
    local sw, sh = img:getSize()
    local destW = sw * pixelScale
    local destH = sh * pixelScale
    if destW >= 1 then
      local destX = ps.x + (scale * spr.offset * ROAD_W * HALF_W)
      local drawX = destX - destW/2
      local drawY = ps.y - destH
      gfx.setColor(kBlack)
      img:drawScaled(drawX, drawY, pixelScale)
    end
  end
end

----------------------------------------------------------------------
-- Public render: draws sky-filled background must already be drawn.
-- position = camera Z along track, playerX = lateral (-1..1 = road edges)
----------------------------------------------------------------------
function Road.render(position, playerX)
  local base = segIndexAt(position)
  local baseSeg = segments[base+1]
  local basePercent = (position % SEG_LEN) / SEG_LEN
  local playerY = interpolate(baseSeg.p1.world.y, baseSeg.p2.world.y, basePercent)
  local camX = playerX * ROAD_W
  local camY = CAM_H + playerY

  local maxY = SCREEN_H
  local x  = 0
  local dx = -(baseSeg.curve * basePercent)

  local visible = {}
  local vn = 0
  for n=0,DRAW_DIST-1 do
    local idx = (base + n) % N
    local s = segments[idx+1]
    local looped = idx < base
    local camZ = position - (looped and trackLen or 0)

    project(s.p1, camX - x,        camY, camZ)
    project(s.p2, camX - x - dx,   camY, camZ)
    x  = x + dx
    dx = dx + s.curve

    if s.p1.camera.z > CAM_DEPTH and s.p2.screen.y < maxY then
      maxY = s.p2.screen.y
      vn = vn + 1
      visible[vn] = s
      renderSegment(s)
    end
  end

  -- sprites far -> near so nearer terrain/props overlap correctly
  for i=vn,1,-1 do
    renderSprites(visible[i])
  end
end

Road.SCREEN_W = SCREEN_W
Road.SCREEN_H = SCREEN_H
Road.ROAD_W   = ROAD_W

return Road
