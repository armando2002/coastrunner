-- audio.lua -- original synth audio for CoastRunner (no sampled assets)

local snd <const> = playdate.sound
Audio = {}  -- global: Playdate's import() does not return module values

local engine, engineSub, lead
local titleNotes = { 57, 64, 69, 72, 69, 64, 60, 67 } -- original A-minor-ish arp (MIDI)
local titleStep = 0
local titleFrame = 0
local titlePlaying = false

function Audio.init()
  -- main engine: sawtooth, sustained, legato so pitch glides without re-attack
  engine = snd.synth.new(snd.kWaveSawtooth)
  engine:setADSR(0.01, 0.0, 1.0, 0.06)
  engine:setLegato(true)
  engine:setVolume(0.0)
  engine:playNote(60)

  -- sub layer: square an octave down for body
  engineSub = snd.synth.new(snd.kWaveSquare)
  engineSub:setADSR(0.01, 0.0, 1.0, 0.06)
  engineSub:setLegato(true)
  engineSub:setVolume(0.0)
  engineSub:playNote(40)

  -- title lead
  lead = snd.synth.new(snd.kWaveSquare)
  lead:setADSR(0.005, 0.08, 0.0, 0.05)
  lead:setVolume(0.30)
end

-- speedPercent 0..1, gear 1=low 2=high, offRoad bool
function Audio.engineUpdate(speedPercent, gear, offRoad)
  -- low gear hits redline at half speed, so it sounds revvier for the same speed
  local rpm = speedPercent
  if gear == 1 then rpm = math.min(1.0, speedPercent / 0.5) end

  local hz = 46 + rpm * rpm * 250
  if gear == 1 then hz = hz + 26 end

  local vol = 0.10 + speedPercent * 0.30
  if offRoad and speedPercent > 0.05 then
    -- gravel: jitter pitch and dip volume
    hz = hz * (0.85 + math.random() * 0.3)
    vol = vol * 0.7
  end

  engine:setVolume(math.min(0.42, vol))
  engine:playNote(hz)
  engineSub:setVolume(math.min(0.30, vol * 0.7))
  engineSub:playNote(hz * 0.5)
end

function Audio.engineSilence()
  engine:setVolume(0.0)
  engineSub:setVolume(0.0)
end

function Audio.titleStart()
  titlePlaying = true
  titleStep = 0
  titleFrame = 0
  Audio.engineSilence()
end

function Audio.titleStop()
  titlePlaying = false
end

-- call once per frame while on the title screen
function Audio.titleUpdate()
  if not titlePlaying then return end
  titleFrame = titleFrame + 1
  if titleFrame % 11 == 0 then
    local note = titleNotes[(titleStep % #titleNotes) + 1]
    lead:playNote(440 * 2 ^ ((note - 69) / 12), 0.28, 0.18)
    titleStep = titleStep + 1
  end
end

function Audio.blip(freq, len)
  lead:playNote(freq or 880, 0.4, len or 0.08)
end

return Audio
