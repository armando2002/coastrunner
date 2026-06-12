-- road.lua -- pseudo-3D road engine for MeowtaRacer
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
local forkStartZ = 0                  -- z where the fork zone begins
local FORK_SEGS <const> = 24          -- segments of widening road at stage end

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

local function addSegment(curve, y, w1, w2)
  local n = N
  local prevY = lastY()
  N = N + 1
  segments[N] = {
    index = n,
    curve = curve,
    dark  = (math.floor(n / RUMBLE) % 2) == 1,
    sprites = nil,
    w1 = w1 or 1, w2 = w2 or 1,        -- road width multipliers (fork widening)
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

----------------------------------------------------------------------
-- Stage generation (OutRun-style branching)
-- Road.build(depth, rights): depth = stage number 1..5, rights = number of
-- "hard" (right) choices taken so far. Difficulty scales curve sharpness,
-- hills, and tree density. Each (depth, rights) pair is seeded, so every
-- route through the tree is its own consistent stage.
-- The stage ends in a FORK: the road widens around a divider -- exit on the
-- LEFT side for the easier next stage, RIGHT for the harder one.
----------------------------------------------------------------------
function Road.build(depth, rights)
  depth  = depth or 1
  rights = rights or 0
  imgPalm = imgPalm or gfx.image.new("images/palm")
  imgSign = imgSign or gfx.image.new("images/sign")

  segments = {}; N = 0
  math.randomseed(1000 + depth * 71 + rights * 137)
  local diff = rights + (depth - 1) * 0.5        -- 0 .. ~6 across the tree
  local function R(a, b) return math.random(a, b) end

  straight(12, 0)                                 -- launch
  local budget = 360 + depth * 18                 -- stage length (movement units)
  while budget > 0 do
    local pick = R(1, 10)
    local dir = (R(0, 1) == 0) and 1 or -1
    if pick <= 3 then                             -- breathing straight
      local l = R(12, 24); straight(l, R(-1, 1) * R(0, 30)); budget = budget - l
    elseif pick <= 6 then                         -- sweeper
      local l = R(26, 40)
      curve(l, dir * (2 + R(0, 1) + math.floor(diff * 0.6)), R(-1, 1) * R(20, 55))
      budget = budget - l
    elseif pick <= 8 then                         -- chicane (sharper with difficulty)
      local c = 4 + math.floor(diff)
      curve(13, dir * c, 0); curve(13, -dir * c, 0)
      budget = budget - 26
    else                                          -- crest + drop-away curve
      straight(9, 55 + diff * 12)
      curve(14, dir * (3 + math.floor(diff * 0.8)), -(30 + diff * 8))
      budget = budget - 23
    end
  end
  straight(8, 0)                                  -- settle before the fork

  -- FORK ZONE: road widens to ~2.2x around a divider of signs.
  local preFork = N
  for n = 0, FORK_SEGS - 1 do
    local wa = 1 + 1.2 * (n / FORK_SEGS)
    local wb = 1 + 1.2 * ((n + 1) / FORK_SEGS)
    addSegment(0, lastY(), wa, wb)
  end
  forkStartZ = preFork * SEG_LEN
  -- divider: a line of signs down the centre (hit it and you crash)
  for i = preFork + 8, N, 3 do
    addSprite(i, imgSign, 0, 0.20)
  end
  -- checkpoint line: darken the final band
  for i = N - RUMBLE + 1, N do segments[i].dark = true end

  trackLen = N * SEG_LEN

  -- roadside scatter: denser with difficulty; none inside the fork zone
  local spacing0 = math.max(8, 20 - math.floor(diff * 2))
  for i = 1, preFork do
    local s = segments[i]
    local dense = (i > preFork * 0.30 and i < preFork * 0.44)
               or (i > preFork * 0.72 and i < preFork * 0.86)
    local spacing = dense and math.max(6, spacing0 - 8) or spacing0
    if i % spacing == 0 then
      addSprite(i, imgPalm, -1.5 - (i % 3) * 0.10, 0.30)
    elseif i % spacing == (spacing // 2) then
      addSprite(i, imgPalm,  1.5 + (i % 3) * 0.10, 0.30)
    end
    if i < preFork and math.abs(segments[i + 1].curve - s.curve) > 2.5 and i % 9 == 0 then
      addSprite(i, imgSign, s.curve > 0 and 1.35 or -1.35, 0.26)
    end
  end
end

function Road.forkStart() return forkStartZ end

function Road.length() return trackLen end

local function segIndexAt(z)
  return math.floor(z / SEG_LEN) % N
end

-- returns the segment table the camera/player is currently over
function Road.segmentAt(z)
  return segments[segIndexAt(z) + 1]
end

-- road width multiplier at z (1 = normal, up to ~2.2 in the fork)
function Road.widthAt(z)
  local s = segments[segIndexAt(z) + 1]
  if not s then return 1 end
  local p = (z % SEG_LEN) / SEG_LEN
  return s.w1 + (s.w2 - s.w1) * p
end

-- returns (true, sprite) if the player at (z, playerX) overlaps a collidable prop.
-- Scans the current segment and the one just ahead so a fast frame can't skip a hit.
function Road.collisionAt(z, playerX)
  local base = segIndexAt(z)
  for d = 0, 1 do
    local seg = segments[((base + d) % N) + 1]
    if seg and seg.sprites then
      for _, spr in ipairs(seg.sprites) do
        if spr.hitW and math.abs(playerX - spr.offset) < spr.hitW then
          return true, spr
        end
      end
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
    s.p1.screen.w = s.p1.screen.w * s.w1   -- fork-zone widening
    s.p2.screen.w = s.p2.screen.w * s.w2
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
