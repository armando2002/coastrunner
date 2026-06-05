-- audio.lua -- CoastRunner synth audio v2
-- Drop-in replacement for Claude's existing audio.lua.
--
-- Goals:
--   1) Do not break existing main.lua calls.
--   2) Replace the harsh/nasal engine with a softer triangle-based engine.
--   3) Add a fuller original 80s coastal arcade racing tune.
--
-- Public API preserved:
--   Audio.init()
--   Audio.engineUpdate(speedPercent, gear, offRoad)
--   Audio.engineSilence()
--   Audio.titleStart()
--   Audio.titleStop()
--   Audio.titleUpdate()
--   Audio.blip(freq, len)
--
-- This is original music. It is an homage, not a transcription/copy
-- of Splash Wave, Magical Sound Shower, Passing Breeze, or any Sega track.

local snd <const> = playdate.sound
Audio = {} -- global: Playdate import() does not return module values

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function midiToHz(m)
  return 440 * 2 ^ ((m - 69) / 12)
end

local NOTE_BASE = {
  C = 0, ["C#"] = 1, Db = 1,
  D = 2, ["D#"] = 3, Eb = 3,
  E = 4,
  F = 5, ["F#"] = 6, Gb = 6,
  G = 7, ["G#"] = 8, Ab = 8,
  A = 9, ["A#"] = 10, Bb = 10,
  B = 11
}

local function noteToHz(note)
  if type(note) == "number" then
    return midiToHz(note)
  end

  local name, octave = note:match("^([A-G][b#]?)(%-?%d+)$")
  if not name then return 440 end

  local semi = NOTE_BASE[name] or 0
  local midi = (tonumber(octave) + 1) * 12 + semi
  return midiToHz(midi)
end

local function play(synth, note, vel, len)
  if synth and note then
    synth:playNote(noteToHz(note), vel or 0.4, len or 0.12)
  end
end

local function makeSynth(waveform, a, d, s, r, vol, pw)
  local synth = snd.synth.new(waveform)
  synth:setADSR(a, d, s, r)
  synth:setVolume(vol or 0.2)

  -- On square waves, parameter 1 is pulse width on many SDK versions.
  -- Ignore safely if unsupported.
  if pw and synth.getParameterCount and synth:getParameterCount() >= 1 then
    synth:setParameter(1, pw)
  end

  return synth
end

----------------------------------------------------------------------
-- Instruments/state
----------------------------------------------------------------------

local engine, engineAir
local titleLead

local bass, bass2
local chord1, chord2, chord3
local arp
local leadA, leadB
local kick, snare, hat

local titleNotes = { 57, 64, 69, 72, 69, 64, 60, 67 }
local titleStep = 0
local titleFrame = 0
local titlePlaying = false

local musicPlaying = false
local songFrame = 0

-- Manual sequencer timing.
-- 3 frames per 16th note at 30 FPS = 150 BPM.
local STEP_FRAMES = 3
local LOOP_STEPS = 128

----------------------------------------------------------------------
-- Song data: "Coastline Catwalk" / original arcade-coast homage
----------------------------------------------------------------------

-- 8-bar loop, 16 steps/bar:
-- Fmaj7 | G6 | Em7 | Am7 | Dm9 | G13 | Cmaj7 | C6/9
local CHORDS = {
  { "F3", "A3", "E4" },
  { "G3", "B3", "E4" },
  { "E3", "G3", "D4" },
  { "A3", "C4", "G4" },
  { "D3", "F3", "E4" },
  { "G3", "B3", "E4" },
  { "C3", "E3", "B3" },
  { "C3", "G3", "D4" },
}

local BASS = {
  { "F2", "F2", "C3", "E3", "A2" },
  { "G2", "G2", "D3", "E3", "B2" },
  { "E2", "E2", "B2", "D3", "G2" },
  { "A2", "A2", "E3", "G3", "C3" },
  { "D2", "D2", "A2", "C3", "F2" },
  { "G2", "G2", "D3", "F3", "B2" },
  { "C2", "C2", "G2", "B2", "E2" },
  { "C2", "G2", "D3", "E3", "G2" },
}

local ARP_8THS = {
  "A4","C5","E5","C5",
  "B4","D5","E5","D5",
  "G4","B4","D5","B4",
  "C5","E5","G5","E5",
  "F4","A4","E5","A4",
  "B4","D5","E5","F5",
  "E4","G4","B4","G4",
  "E4","G4","D5","G4",
}

-- Hook: intentionally not close to the OutRun melodies.
local MELODY = {
  [4]   = { "C5", 2, 0.52 }, [6]   = { "D5", 2, 0.48 },
  [8]   = { "E5", 3, 0.56 }, [12]  = { "A4", 2, 0.42 },
  [16]  = { "G4", 2, 0.36 }, [20]  = { "B4", 2, 0.46 },
  [22]  = { "D5", 2, 0.50 }, [24]  = { "E5", 4, 0.56 },

  [34]  = { "G4", 2, 0.42 }, [36]  = { "B4", 2, 0.46 },
  [38]  = { "D5", 3, 0.50 }, [42]  = { "E5", 2, 0.54 },
  [48]  = { "A4", 2, 0.38 }, [52]  = { "C5", 2, 0.48 },
  [54]  = { "E5", 2, 0.52 }, [56]  = { "G5", 5, 0.58 },

  [68]  = { "F5", 2, 0.56 }, [70]  = { "E5", 2, 0.48 },
  [72]  = { "D5", 3, 0.50 }, [76]  = { "C5", 2, 0.46 },
  [80]  = { "A4", 2, 0.38 }, [84]  = { "B4", 2, 0.48 },
  [86]  = { "D5", 2, 0.52 }, [88]  = { "F5", 3, 0.54 },
  [92]  = { "E5", 2, 0.52 },

  [100] = { "G4", 2, 0.42 }, [102] = { "B4", 2, 0.48 },
  [104] = { "E5", 4, 0.56 }, [112] = { "G5", 2, 0.50 },
  [116] = { "D5", 2, 0.48 }, [118] = { "E5", 2, 0.50 },
  [120] = { "C5", 6, 0.58 },
}

local function updateMusic()
  if not musicPlaying then return end

  songFrame = songFrame + 1
  if songFrame % STEP_FRAMES ~= 0 then return end

  local step = math.floor(songFrame / STEP_FRAMES) % LOOP_STEPS
  local bar = math.floor(step / 16) + 1
  local inbar = step % 16

  local b = BASS[bar]
  local c = CHORDS[bar]

  -- Bass groove: step-based syncopation.
  if inbar == 0 then
    play(bass, b[1], 0.58, 0.26)
    play(bass2, b[1], 0.16, 0.30)
  elseif inbar == 3 then
    play(bass, b[5], 0.30, 0.12)
  elseif inbar == 6 then
    play(bass, b[2], 0.42, 0.14)
  elseif inbar == 9 then
    play(bass, b[3], 0.42, 0.16)
  elseif inbar == 12 then
    play(bass, b[2], 0.46, 0.14)
  elseif inbar == 14 then
    play(bass, b[4], 0.46, 0.14)
  end

  -- Chord stabs/pads. Three separate synths give a fuller arcade-radio feel.
  if inbar == 0 or inbar == 8 then
    local chordLen = (inbar == 0) and 0.45 or 0.28
    play(chord1, c[1], 0.26, chordLen)
    play(chord2, c[2], 0.22, chordLen)
    play(chord3, c[3], 0.18, chordLen)
  elseif inbar == 5 or inbar == 13 then
    play(chord2, c[2], 0.13, 0.11)
    play(chord3, c[3], 0.12, 0.11)
  end

  -- Arp sparkle on every other step.
  if step % 2 == 0 then
    local arpIndex = (math.floor(step / 2) % #ARP_8THS) + 1
    play(arp, ARP_8THS[arpIndex], 0.22, 0.08)
  end

  -- Lead hook with a very light double for body.
  local m = MELODY[step]
  if m then
    play(leadA, m[1], m[3], m[2] * 0.10)
    play(leadB, m[1], m[3] * 0.16, m[2] * 0.11)
  end

  -- Drums. These are synthesized clicks/noise, not samples.
  if inbar == 0 or inbar == 10 then
    play(kick, "C2", 0.55, 0.055)
  elseif inbar == 6 then
    play(kick, "C2", 0.30, 0.045)
  end

  if inbar == 4 or inbar == 12 then
    play(snare, "C4", 0.38, 0.055)
  elseif inbar == 15 then
    play(snare, "C4", 0.16, 0.030)
  end

  if inbar % 2 == 0 then
    play(hat, "C6", 0.10, 0.025)
  end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function Audio.init()
  -- Softer engine:
  -- The original saw + square was bright/nasal at full throttle.
  -- Triangle + very quiet square "air" is less piercing and leaves room for music.
  engine = snd.synth.new(snd.kWaveTriangle)
  engine:setADSR(0.02, 0.0, 1.0, 0.08)
  engine:setLegato(true)
  engine:setVolume(0.0)
  engine:playNote(60)

  engineAir = snd.synth.new(snd.kWaveSquare)
  engineAir:setADSR(0.02, 0.0, 1.0, 0.08)
  engineAir:setLegato(true)
  engineAir:setVolume(0.0)
  if engineAir.getParameterCount and engineAir:getParameterCount() >= 1 then
    engineAir:setParameter(1, 0.38)
  end
  engineAir:playNote(60)

  titleLead = makeSynth(snd.kWaveSquare, 0.005, 0.08, 0.0, 0.05, 0.25, 0.44)

  bass   = makeSynth(snd.kWaveSquare,   0.004, 0.05, 0.42, 0.04, 0.22, 0.42)
  bass2  = makeSynth(snd.kWaveTriangle, 0.006, 0.04, 0.35, 0.05, 0.09)

  chord1 = makeSynth(snd.kWaveTriangle, 0.020, 0.10, 0.30, 0.18, 0.10)
  chord2 = makeSynth(snd.kWaveTriangle, 0.020, 0.10, 0.28, 0.18, 0.09)
  chord3 = makeSynth(snd.kWaveTriangle, 0.020, 0.10, 0.26, 0.18, 0.08)

  arp    = makeSynth(snd.kWaveSquare,   0.002, 0.035, 0.15, 0.04, 0.09, 0.30)
  leadA  = makeSynth(snd.kWaveSquare,   0.003, 0.07, 0.25, 0.07, 0.18, 0.46)
  leadB  = makeSynth(snd.kWaveTriangle, 0.004, 0.08, 0.20, 0.08, 0.07)

  kick   = makeSynth(snd.kWaveTriangle, 0.001, 0.035, 0.00, 0.02, 0.20)
  snare  = makeSynth(snd.kWaveNoise,    0.001, 0.035, 0.00, 0.04, 0.11)
  hat    = makeSynth(snd.kWaveNoise,    0.001, 0.010, 0.00, 0.012, 0.05)
end

function Audio.raceMusicStart()
  musicPlaying = true
  songFrame = 0
end

function Audio.raceMusicStop()
  musicPlaying = false
end

-- speedPercent 0..1, gear 1=low 2=high, offRoad bool
function Audio.engineUpdate(speedPercent, gear, offRoad)
  updateMusic()

  local rpm = speedPercent
  if gear == 1 then
    rpm = math.min(1.0, speedPercent / 0.5)
  end

  -- Less nasal range than the old 46..296 Hz saw. This is lower and softer.
  local hz = 34 + rpm * rpm * 170
  if gear == 1 then hz = hz + 14 end

  -- Much quieter full-throttle engine.
  -- Old max was about 0.42 + 0.30 sub. This caps around 0.16 + 0.035.
  local vol = 0.025 + speedPercent * 0.13

  if offRoad and speedPercent > 0.05 then
    hz = hz * (0.94 + math.random() * 0.12)
    vol = vol * 0.70
  end

  engine:setVolume(clamp(vol, 0.0, 0.16))
  engine:playNote(hz)

  -- Quiet high component, only enough to imply revs.
  engineAir:setVolume(clamp(speedPercent * 0.035, 0.0, 0.035))
  engineAir:playNote(hz * 1.5)
end

function Audio.engineSilence()
  if engine then engine:setVolume(0.0) end
  if engineAir then engineAir:setVolume(0.0) end
end

function Audio.titleStart()
  titlePlaying = true
  titleStep = 0
  titleFrame = 0
  Audio.raceMusicStop()
  Audio.engineSilence()
end

function Audio.titleStop()
  titlePlaying = false
  Audio.raceMusicStart()
end

-- call once per frame while on the title screen
function Audio.titleUpdate()
  if not titlePlaying then return end

  titleFrame = titleFrame + 1

  -- Keep title simple but less harsh.
  if titleFrame % 11 == 0 then
    local note = titleNotes[(titleStep % #titleNotes) + 1]
    play(titleLead, note, 0.20, 0.12)
    titleStep = titleStep + 1
  end
end

function Audio.blip(freq, len)
  if titleLead then
    titleLead:playNote(freq or 880, 0.28, len or 0.08)
  end
end

return Audio
