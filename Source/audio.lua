-- audio.lua -- CoastRunner synth audio v3: radio tracks + smoother Miata-ish engine
-- Drop-in replacement for Claude's existing audio.lua.
--
-- Keeps existing public API used by main.lua:
--   Audio.init()
--   Audio.engineUpdate(speedPercent, gear, offRoad)
--   Audio.engineSilence()
--   Audio.titleStart()
--   Audio.titleStop()
--   Audio.titleUpdate()
--   Audio.blip(freq, len)
--
-- Adds optional radio helpers Claude can wire later:
--   Audio.setTrack(index)
--   Audio.nextTrack()
--   Audio.prevTrack()
--   Audio.getTrackName()
--
-- All music here is original. It aims for breezy 80s coastal arcade energy
-- without copying OutRun melodies, titles, logos, or assets.

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
  if type(note) == "number" then return midiToHz(note) end

  local name, octave = note:match("^([A-G][b#]?)(%-?%d+)$")
  if not name then return 440 end

  return midiToHz((tonumber(octave) + 1) * 12 + (NOTE_BASE[name] or 0))
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

  -- For square waves, parameter 1 is pulse width on many SDK versions.
  if pw and synth.getParameterCount and synth:getParameterCount() >= 1 then
    synth:setParameter(1, pw)
  end

  return synth
end

----------------------------------------------------------------------
-- Synth instruments/state
----------------------------------------------------------------------

local engineFund, engineRasp, engineAir
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
local songStep = -1
local currentTrack = 1

-- Manual sequencer. At 30 FPS:
-- stepFrames = 3 => 150 BPM if each step is a 16th note.
local LOOP_STEPS = 128

----------------------------------------------------------------------
-- Original radio tracks
----------------------------------------------------------------------

local TRACKS = {
  {
    name = "Seafoam GT",
    stepFrames = 3, -- 150 BPM
    arpRate = 2,
    drum = "busy",
    chords = {
      { "F3", "A3", "E4" }, { "G3", "B3", "E4" },
      { "E3", "G3", "D4" }, { "A3", "C4", "G4" },
      { "D3", "F3", "E4" }, { "G3", "B3", "E4" },
      { "C3", "E3", "B3" }, { "C3", "G3", "D4" },
    },
    bass = {
      { "F2", "F2", "C3", "E3", "A2" },
      { "G2", "G2", "D3", "E3", "B2" },
      { "E2", "E2", "B2", "D3", "G2" },
      { "A2", "A2", "E3", "G3", "C3" },
      { "D2", "D2", "A2", "C3", "F2" },
      { "G2", "G2", "D3", "F3", "B2" },
      { "C2", "C2", "G2", "B2", "E2" },
      { "C2", "G2", "D3", "E3", "G2" },
    },
    arp = {
      "A4","C5","E5","C5", "B4","D5","E5","D5",
      "G4","B4","D5","B4", "C5","E5","G5","E5",
      "F4","A4","E5","A4", "B4","D5","E5","F5",
      "E4","G4","B4","G4", "E4","G4","D5","G4",
    },
    melody = {
      [4]={"C5",2,.52}, [6]={"D5",2,.48}, [8]={"E5",3,.56}, [12]={"A4",2,.42},
      [16]={"G4",2,.36}, [20]={"B4",2,.46}, [22]={"D5",2,.50}, [24]={"E5",4,.56},
      [34]={"G4",2,.42}, [36]={"B4",2,.46}, [38]={"D5",3,.50}, [42]={"E5",2,.54},
      [48]={"A4",2,.38}, [52]={"C5",2,.48}, [54]={"E5",2,.52}, [56]={"G5",5,.58},
      [68]={"F5",2,.56}, [70]={"E5",2,.48}, [72]={"D5",3,.50}, [76]={"C5",2,.46},
      [80]={"A4",2,.38}, [84]={"B4",2,.48}, [86]={"D5",2,.52}, [88]={"F5",3,.54}, [92]={"E5",2,.52},
      [100]={"G4",2,.42}, [102]={"B4",2,.48}, [104]={"E5",4,.56}, [112]={"G5",2,.50},
      [116]={"D5",2,.48}, [118]={"E5",2,.50}, [120]={"C5",6,.58},
    }
  },

  {
    name = "Vista Run",
    stepFrames = 4, -- 112.5 BPM, breezier
    arpRate = 4,
    drum = "light",
    chords = {
      { "C3", "E3", "B3" }, { "F3", "A3", "E4" },
      { "D3", "F3", "C4" }, { "G3", "B3", "D4" },
      { "C3", "G3", "E4" }, { "A2", "C3", "G3" },
      { "F3", "A3", "C4" }, { "G3", "D4", "F4" },
    },
    bass = {
      { "C2", "C2", "G2", "B2", "E2" },
      { "F2", "F2", "C3", "E3", "A2" },
      { "D2", "D2", "A2", "C3", "F2" },
      { "G2", "G2", "D3", "F3", "B2" },
      { "C2", "C2", "G2", "E3", "B2" },
      { "A2", "A2", "E3", "G3", "C3" },
      { "F2", "C3", "A2", "C3", "E3" },
      { "G2", "D3", "B2", "D3", "F3" },
    },
    arp = {
      "E4","G4","B4","G4", "A4","C5","E5","C5",
      "F4","A4","C5","A4", "B4","D5","F5","D5",
      "E4","G4","C5","G4", "C4","E4","G4","E4",
      "A4","C5","F5","C5", "B4","D5","G5","D5",
    },
    melody = {
      [0]={"G4",4,.42}, [6]={"A4",2,.34}, [8]={"B4",4,.42},
      [18]={"C5",3,.46}, [22]={"E5",3,.44}, [28]={"D5",4,.40},
      [36]={"A4",3,.36}, [40]={"C5",4,.44}, [48]={"B4",2,.36}, [52]={"G4",5,.38},
      [64]={"E5",4,.46}, [72]={"D5",4,.40}, [80]={"C5",3,.40}, [84]={"A4",3,.34},
      [96]={"F4",4,.34}, [104]={"A4",4,.38}, [112]={"B4",3,.40}, [116]={"D5",3,.42}, [120]={"C5",6,.44},
    }
  },

  {
    name = "Afterglow Lane",
    stepFrames = 3, -- 150 BPM but heavier/darker
    arpRate = 2,
    drum = "punchy",
    chords = {
      { "A2", "C3", "G3" }, { "F3", "A3", "E4" },
      { "G3", "B3", "F4" }, { "E3", "G3", "D4" },
      { "A2", "E3", "C4" }, { "D3", "F3", "C4" },
      { "G2", "B2", "F3" }, { "C3", "E3", "G3" },
    },
    bass = {
      { "A1", "A2", "E2", "G2", "C2" },
      { "F2", "F2", "C3", "E3", "A2" },
      { "G2", "G2", "D3", "F3", "B2" },
      { "E2", "E2", "B2", "D3", "G2" },
      { "A1", "A2", "E2", "C3", "G2" },
      { "D2", "D2", "A2", "C3", "F2" },
      { "G1", "G2", "D2", "F2", "B1" },
      { "C2", "C2", "G2", "E3", "G2" },
    },
    arp = {
      "C5","E5","G5","E5", "A4","C5","E5","C5",
      "B4","D5","F5","D5", "G4","B4","D5","B4",
      "C5","E5","A5","E5", "F4","A4","C5","A4",
      "B4","D5","G5","D5", "C5","E5","G5","E5",
    },
    melody = {
      [2]={"E5",2,.52}, [4]={"G5",2,.54}, [8]={"A5",4,.60}, [14]={"G5",2,.46},
      [18]={"E5",2,.46}, [20]={"C5",2,.44}, [24]={"D5",4,.50},
      [34]={"F5",2,.52}, [36]={"E5",2,.48}, [40]={"D5",3,.48}, [44]={"B4",2,.42},
      [50]={"C5",2,.44}, [52]={"E5",2,.50}, [56]={"G5",5,.58},
      [66]={"A5",2,.58}, [68]={"G5",2,.50}, [72]={"E5",4,.52},
      [82]={"D5",2,.46}, [84]={"F5",2,.52}, [88]={"G5",4,.56},
      [98]={"E5",2,.48}, [100]={"C5",2,.44}, [104]={"D5",3,.48}, [108]={"B4",2,.42},
      [116]={"C5",2,.44}, [118]={"D5",2,.46}, [120]={"E5",6,.54},
    }
  }
}

----------------------------------------------------------------------
-- Music sequencer
----------------------------------------------------------------------

local function resetSong()
  songFrame = 0
  songStep = -1
end

local function updateMusic()
  if not musicPlaying then return end

  local t = TRACKS[currentTrack]
  songFrame = songFrame + 1

  if songFrame % t.stepFrames ~= 0 then return end

  local step = math.floor(songFrame / t.stepFrames) % LOOP_STEPS
  if step == songStep then return end
  songStep = step

  local bar = math.floor(step / 16) + 1
  local inbar = step % 16

  local b = t.bass[bar]
  local c = t.chords[bar]

  -- Bass groove. Keeps the driving arcade feel.
  if inbar == 0 then
    play(bass, b[1], 0.58, 0.26)
    play(bass2, b[1], 0.17, 0.30)
  elseif inbar == 3 then
    play(bass, b[5], 0.28, 0.12)
  elseif inbar == 6 then
    play(bass, b[2], 0.42, 0.14)
  elseif inbar == 9 then
    play(bass, b[3], 0.42, 0.16)
  elseif inbar == 12 then
    play(bass, b[2], 0.46, 0.14)
  elseif inbar == 14 then
    play(bass, b[4], 0.46, 0.14)
  end

  -- Chord stabs / light pads.
  if inbar == 0 or inbar == 8 then
    local chordLen = (inbar == 0) and 0.45 or 0.28
    local v = (t.drum == "light") and 0.20 or 0.25
    play(chord1, c[1], v, chordLen)
    play(chord2, c[2], v * 0.82, chordLen)
    play(chord3, c[3], v * 0.68, chordLen)
  elseif inbar == 5 or inbar == 13 then
    play(chord2, c[2], 0.12, 0.11)
    play(chord3, c[3], 0.10, 0.11)
  end

  -- Arp sparkle.
  if step % t.arpRate == 0 then
    local arpIndex = (math.floor(step / t.arpRate) % #t.arp) + 1
    local arpVel = (t.drum == "light") and 0.16 or 0.21
    play(arp, t.arp[arpIndex], arpVel, 0.08)
  end

  -- Lead hook.
  local m = t.melody[step]
  if m then
    play(leadA, m[1], m[3], m[2] * 0.10)
    play(leadB, m[1], m[3] * 0.15, m[2] * 0.11)
  end

  -- Drums.
  if t.drum == "light" then
    if inbar == 0 or inbar == 10 then play(kick, "C2", 0.42, 0.050) end
    if inbar == 4 or inbar == 12 then play(snare, "C4", 0.26, 0.052) end
    if inbar % 4 == 0 then play(hat, "C6", 0.07, 0.020) end
  elseif t.drum == "punchy" then
    if inbar == 0 or inbar == 6 or inbar == 10 then play(kick, "C2", 0.58, 0.055) end
    if inbar == 4 or inbar == 12 then play(snare, "C4", 0.43, 0.055) end
    if inbar == 15 then play(snare, "C4", 0.18, 0.030) end
    if inbar % 2 == 0 then play(hat, "C6", 0.11, 0.025) end
  else
    if inbar == 0 or inbar == 10 then play(kick, "C2", 0.55, 0.055)
    elseif inbar == 6 then play(kick, "C2", 0.30, 0.045) end
    if inbar == 4 or inbar == 12 then play(snare, "C4", 0.38, 0.055)
    elseif inbar == 15 then play(snare, "C4", 0.16, 0.030) end
    if inbar % 2 == 0 then play(hat, "C6", 0.10, 0.025) end
  end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function Audio.init()
  -- Miata-ish engine approximation:
  -- A first-gen Miata is a small inline-4: light, revvy, a little raspy,
  -- not a deep V8 and not a screaming sawtooth synth.
  engineFund = snd.synth.new(snd.kWaveTriangle)
  engineFund:setADSR(0.018, 0.0, 1.0, 0.08)
  engineFund:setLegato(true)
  engineFund:setVolume(0.0)
  engineFund:playNote(60)

  -- Rasp layer. Kept quiet so it reads as exhaust/intake texture, not a kazoo.
  engineRasp = snd.synth.new(snd.kWaveSquare)
  engineRasp:setADSR(0.015, 0.0, 1.0, 0.08)
  engineRasp:setLegato(true)
  engineRasp:setVolume(0.0)
  if engineRasp.getParameterCount and engineRasp:getParameterCount() >= 1 then
    engineRasp:setParameter(1, 0.28)
  end
  engineRasp:playNote(60)

  -- Air/intake brightness at higher revs.
  engineAir = snd.synth.new(snd.kWaveNoise)
  engineAir:setADSR(0.005, 0.0, 1.0, 0.03)
  engineAir:setVolume(0.0)
  engineAir:playNote(120)

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

function Audio.setTrack(index)
  currentTrack = ((index - 1) % #TRACKS) + 1
  resetSong()
end

function Audio.nextTrack()
  Audio.setTrack(currentTrack + 1)
  Audio.blip(980, 0.05)
end

function Audio.prevTrack()
  Audio.setTrack(currentTrack - 1)
  Audio.blip(740, 0.05)
end

function Audio.getTrackName()
  return TRACKS[currentTrack].name
end

function Audio.raceMusicStart()
  musicPlaying = true
  resetSong()
end

function Audio.raceMusicStop()
  musicPlaying = false
end

-- speedPercent 0..1, gear 1=low 2=high, offRoad bool
function Audio.engineUpdate(speedPercent, gear, offRoad)
  updateMusic()

  local rpm = speedPercent
  if gear == 1 then
    -- Low gear reaches redline around half top speed.
    rpm = math.min(1.0, speedPercent / 0.5)
  end

  -- Revvy 4-cylinder pitch curve. Higher than v2, but less nasal than the original.
  local hz = 42 + rpm * rpm * 230
  if gear == 1 then hz = hz + 18 end

  -- Slightly louder than v2, still far quieter than the original harsh engine.
  local fundVol = 0.035 + speedPercent * 0.175
  local raspVol = speedPercent * speedPercent * 0.070
  local airVol  = math.max(0, speedPercent - 0.55) * 0.060

  if offRoad and speedPercent > 0.05 then
    hz = hz * (0.94 + math.random() * 0.12)
    fundVol = fundVol * 0.72
    raspVol = raspVol * 0.80
    airVol = airVol + 0.020
  end

  engineFund:setVolume(clamp(fundVol, 0.0, 0.21))
  engineFund:playNote(hz)

  engineRasp:setVolume(clamp(raspVol, 0.0, 0.07))
  engineRasp:playNote(hz * 1.98)

  engineAir:setVolume(clamp(airVol, 0.0, 0.05))
  engineAir:playNote(160 + speedPercent * 180)
end

function Audio.engineSilence()
  if engineFund then engineFund:setVolume(0.0) end
  if engineRasp then engineRasp:setVolume(0.0) end
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
