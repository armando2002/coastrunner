-- audio.lua -- CoastRunner synth audio v4: mono speaker mix + Splash-Wave-energy reference
-- Drop-in replacement for Claude's existing audio.lua.
--
-- Built for the Playdate speaker, not headphones:
--   - no stereo/panning assumptions
--   - fuller mono arrangement
--   - more rhythmic chord stabs
--   - call-and-response leads
--   - quieter hats/noise
--   - slightly louder, smoother Miata-ish inline-4 engine
--
-- Existing API preserved:
--   Audio.init()
--   Audio.engineUpdate(speedPercent, gear, offRoad)
--   Audio.engineSilence()
--   Audio.titleStart()
--   Audio.titleStop()
--   Audio.titleUpdate()
--   Audio.blip(freq, len)
--
-- Optional radio helpers for later:
--   Audio.setTrack(index)
--   Audio.nextTrack()
--   Audio.prevTrack()
--   Audio.getTrackName()
--
-- All music is original. It is an arcade-coastal homage, not a copy of
-- Splash Wave, Magical Sound Shower, Passing Breeze, Sega, or OutRun music.

local snd <const> = playdate.sound
Audio = {}

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

local function noteToMidi(note)
    if type(note) == "number" then return note end

    local name, octave = note:match("^([A-G][b#]?)(%-?%d+)$")
    if not name then return 69 end

    return (tonumber(octave) + 1) * 12 + (NOTE_BASE[name] or 0)
end

local function noteToHz(note)
    return midiToHz(noteToMidi(note))
end

local function play(synth, note, vel, len)
    if synth and note then
        synth:playNote(noteToHz(note), vel or 0.4, len or 0.12)
    end
end

local function makeSynth(waveform, a, d, s, r, vol)
    local synth = snd.synth.new(waveform)
    synth:setADSR(a, d, s, r)
    synth:setVolume(vol or 0.2)
    return synth
end

----------------------------------------------------------------------
-- Synths/state
----------------------------------------------------------------------

local engineFund, engineRasp, engineAir
local titleLead

local bass, bassLow
local chord1, chord2, chord3
local arp
local leadA, leadB, answerLead
local kick, snare, hat, click

local titleNotes = { 57, 64, 69, 72, 69, 64, 60, 67 }
local titleStep = 0
local titleFrame = 0
local titlePlaying = false

local musicPlaying = false
local songFrame = 0
local songStep = -1
local currentTrack = 1

local LOOP_STEPS = 128

----------------------------------------------------------------------
-- Original radio tracks
----------------------------------------------------------------------

local TRACKS = {
    {
        -- Fast, bright, syncopated default. This is the one most directly
        -- inspired by the user's favorite "Splash Wave" energy, but it uses
        -- original harmony/melody/riffs.
        name = "Neon Causeway",
        stepFrames = 3, -- 150 BPM at 30 FPS, one step = 16th note
        arpRate = 2,
        drum = "busy",
        chords = {
            { "F3", "A3", "E4" }, { "G3", "B3", "E4" },
            { "E3", "G3", "D4" }, { "A3", "C4", "G4" },
            { "D3", "F3", "E4" }, { "G3", "B3", "F4" },
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
            "F4","A4","E5","A4", "B4","D5","F5","D5",
            "E4","G4","B4","G4", "E4","G4","D5","G4",
        },
        melody = {
            [4]={"C5",2,.50}, [6]={"D5",2,.46}, [8]={"E5",3,.55}, [12]={"A4",2,.38},
            [16]={"G4",2,.34}, [20]={"B4",2,.45}, [22]={"D5",2,.48}, [24]={"E5",4,.55},
            [34]={"G4",2,.40}, [36]={"B4",2,.44}, [38]={"D5",3,.48}, [42]={"E5",2,.52},
            [48]={"A4",2,.36}, [52]={"C5",2,.46}, [54]={"E5",2,.50}, [56]={"G5",5,.56},
            [68]={"F5",2,.54}, [70]={"E5",2,.46}, [72]={"D5",3,.48}, [76]={"C5",2,.44},
            [80]={"A4",2,.36}, [84]={"B4",2,.46}, [86]={"D5",2,.50}, [88]={"F5",3,.52}, [92]={"E5",2,.50},
            [100]={"G4",2,.40}, [102]={"B4",2,.46}, [104]={"E5",4,.54}, [112]={"G5",2,.48},
            [116]={"D5",2,.46}, [118]={"E5",2,.48}, [120]={"C5",6,.56},
        },
        answer = {
            [28]={"B4",2,.22}, [30]={"C5",2,.22},
            [60]={"E5",2,.21}, [62]={"D5",2,.21},
            [96]={"C5",2,.21}, [98]={"B4",2,.20},
            [124]={"A4",2,.20}, [126]={"G4",2,.20},
        }
    },

    {
        -- Relaxed sunny cruising track.
        name = "Vista Run",
        stepFrames = 4, -- 112.5 BPM
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
            [0]={"G4",4,.38}, [6]={"A4",2,.30}, [8]={"B4",4,.38},
            [18]={"C5",3,.42}, [22]={"E5",3,.40}, [28]={"D5",4,.36},
            [36]={"A4",3,.32}, [40]={"C5",4,.40}, [48]={"B4",2,.32}, [52]={"G4",5,.34},
            [64]={"E5",4,.42}, [72]={"D5",4,.36}, [80]={"C5",3,.36}, [84]={"A4",3,.30},
            [96]={"F4",4,.30}, [104]={"A4",4,.34}, [112]={"B4",3,.36}, [116]={"D5",3,.38}, [120]={"C5",6,.40},
        },
        answer = {
            [14]={"E4",3,.15}, [30]={"G4",3,.15},
            [58]={"C5",3,.16}, [90]={"E4",3,.15},
            [124]={"G4",4,.16},
        }
    },

    {
        -- More dramatic high-speed/night-drive track.
        name = "Afterglow Lane",
        stepFrames = 3,
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
            [2]={"E5",2,.48}, [4]={"G5",2,.50}, [8]={"A5",4,.56}, [14]={"G5",2,.42},
            [18]={"E5",2,.42}, [20]={"C5",2,.40}, [24]={"D5",4,.46},
            [34]={"F5",2,.48}, [36]={"E5",2,.44}, [40]={"D5",3,.44}, [44]={"B4",2,.38},
            [50]={"C5",2,.40}, [52]={"E5",2,.46}, [56]={"G5",5,.54},
            [66]={"A5",2,.54}, [68]={"G5",2,.46}, [72]={"E5",4,.48},
            [82]={"D5",2,.42}, [84]={"F5",2,.48}, [88]={"G5",4,.52},
            [98]={"E5",2,.44}, [100]={"C5",2,.40}, [104]={"D5",3,.44}, [108]={"B4",2,.38},
            [116]={"C5",2,.40}, [118]={"D5",2,.42}, [120]={"E5",6,.50},
        },
        answer = {
            [30]={"A4",2,.22}, [46]={"G4",2,.20},
            [78]={"B4",2,.22}, [94]={"A4",2,.20},
            [110]={"G4",2,.20}, [126]={"E4",2,.18},
        }
    }
}

----------------------------------------------------------------------
-- Sequencer
----------------------------------------------------------------------

local function resetSong()
    songFrame = 0
    songStep = -1
end

local function playDrums(t, inbar)
    if t.drum == "light" then
        if inbar == 0 or inbar == 10 then play(kick, "C2", 0.38, 0.05) end
        if inbar == 4 or inbar == 12 then play(snare, "C4", 0.22, 0.05) end
        if inbar % 4 == 0 then play(hat, "C6", 0.055, 0.02) end
    elseif t.drum == "punchy" then
        if inbar == 0 or inbar == 6 or inbar == 10 then play(kick, "C2", 0.52, 0.055) end
        if inbar == 4 or inbar == 12 then play(snare, "C4", 0.36, 0.055) end
        if inbar == 15 then play(snare, "C4", 0.14, 0.03) end
        if inbar % 2 == 0 then play(hat, "C6", 0.085, 0.025) end
    else
        if inbar == 0 or inbar == 10 then
            play(kick, "C2", 0.48, 0.055)
        elseif inbar == 6 then
            play(kick, "C2", 0.26, 0.045)
        end

        if inbar == 4 or inbar == 12 then
            play(snare, "C4", 0.31, 0.055)
        elseif inbar == 15 then
            play(snare, "C4", 0.12, 0.03)
        end

        if inbar % 2 == 0 then play(hat, "C6", 0.075, 0.025) end
        if inbar == 3 or inbar == 11 then play(click, "C5", 0.07, 0.025) end
    end
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

    -- Bass: prominent enough on speaker, but not sub-heavy.
    if inbar == 0 then
        play(bass, b[1], 0.52, 0.24)
        play(bassLow, b[1], 0.12, 0.28)
    elseif inbar == 3 then
        play(bass, b[5], 0.24, 0.10)
    elseif inbar == 6 then
        play(bass, b[2], 0.36, 0.13)
    elseif inbar == 9 then
        play(bass, b[3], 0.36, 0.14)
    elseif inbar == 12 then
        play(bass, b[2], 0.40, 0.13)
    elseif inbar == 14 then
        play(bass, b[4], 0.40, 0.13)
    end

    -- Rhythmic chord stabs: this is the mono substitute for "wide" stereo.
    if inbar == 0 or inbar == 8 then
        local len = (inbar == 0) and 0.36 or 0.24
        play(chord1, c[1], 0.18, len)
        play(chord2, c[2], 0.16, len)
        play(chord3, c[3], 0.14, len)
    elseif inbar == 5 or inbar == 13 then
        play(chord2, c[2], 0.10, 0.09)
        play(chord3, c[3], 0.09, 0.09)
    end

    -- Arp sparkle.
    if step % t.arpRate == 0 then
        local arpIndex = (math.floor(step / t.arpRate) % #t.arp) + 1
        local arpVel = (t.drum == "light") and 0.13 or 0.18
        play(arp, t.arp[arpIndex], arpVel, 0.07)
    end

    -- Main hook plus mono thickening layers.
    local m = t.melody[step]
    if m then
        play(leadA, m[1], m[3], m[2] * 0.095)
        play(leadB, m[1], m[3] * 0.14, m[2] * 0.11)
    end

    -- One-step delayed echo: mono depth without stereo.
    local echoStep = (step - 2) % LOOP_STEPS
    local em = t.melody[echoStep]
    if em and t.drum ~= "light" then
        play(leadEcho, em[1], em[3] * 0.13, 0.055)
    end

    -- Call-and-response phrase.
    local a = t.answer and t.answer[step]
    if a then
        play(answerLead, a[1], a[3], a[2] * 0.08)
    end

    playDrums(t, inbar)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function Audio.init()
    -- Miata-ish inline-4 approximation:
    -- compact, revvy, slightly raspy, but not nasal/loud like the original saw.
    engineFund = snd.synth.new(snd.kWaveTriangle)
    engineFund:setADSR(0.018, 0.0, 1.0, 0.08)
    engineFund:setLegato(true)
    engineFund:setVolume(0.0)
    engineFund:playNote(60)

    engineRasp = snd.synth.new(snd.kWaveSquare)
    engineRasp:setADSR(0.015, 0.0, 1.0, 0.08)
    engineRasp:setLegato(true)
    engineRasp:setVolume(0.0)
    engineRasp:playNote(60)

    engineAir = snd.synth.new(snd.kWaveNoise)
    engineAir:setADSR(0.005, 0.0, 1.0, 0.03)
    engineAir:setVolume(0.0)
    engineAir:playNote(120)

    titleLead = makeSynth(snd.kWaveSquare, 0.005, 0.08, 0.0, 0.05, 0.22)

    bass     = makeSynth(snd.kWaveSquare,   0.004, 0.05, 0.38, 0.04, 0.19)
    bassLow  = makeSynth(snd.kWaveTriangle, 0.006, 0.04, 0.32, 0.05, 0.07)

    chord1   = makeSynth(snd.kWaveTriangle, 0.018, 0.09, 0.26, 0.14, 0.09)
    chord2   = makeSynth(snd.kWaveTriangle, 0.018, 0.09, 0.25, 0.14, 0.08)
    chord3   = makeSynth(snd.kWaveTriangle, 0.018, 0.09, 0.24, 0.14, 0.07)

    arp      = makeSynth(snd.kWaveSquare,   0.002, 0.030, 0.12, 0.035, 0.075)
    leadA    = makeSynth(snd.kWaveSquare,   0.003, 0.065, 0.24, 0.07, 0.16)
    leadB    = makeSynth(snd.kWaveTriangle, 0.004, 0.070, 0.18, 0.07, 0.055)
    leadEcho = makeSynth(snd.kWaveTriangle, 0.004, 0.050, 0.12, 0.06, 0.040)
    answerLead = makeSynth(snd.kWaveSquare, 0.002, 0.040, 0.10, 0.035, 0.080)

    kick     = makeSynth(snd.kWaveTriangle, 0.001, 0.030, 0.00, 0.018, 0.16)
    snare    = makeSynth(snd.kWaveNoise,    0.001, 0.030, 0.00, 0.035, 0.085)
    hat      = makeSynth(snd.kWaveNoise,    0.001, 0.009, 0.00, 0.010, 0.038)
    click    = makeSynth(snd.kWaveNoise,    0.001, 0.010, 0.00, 0.010, 0.030)
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
        rpm = math.min(1.0, speedPercent / 0.5)
    end

    -- Small revvy roadster pitch curve.
    local hz = 42 + rpm * rpm * 225
    if gear == 1 then hz = hz + 18 end

    -- Audible but still not dominant over music.
    local fundVol = 0.035 + speedPercent * 0.170
    local raspVol = speedPercent * speedPercent * 0.060
    local airVol  = math.max(0, speedPercent - 0.55) * 0.040

    if offRoad and speedPercent > 0.05 then
        hz = hz * (0.94 + math.random() * 0.12)
        fundVol = fundVol * 0.72
        raspVol = raspVol * 0.80
        airVol = airVol + 0.018
    end

    engineFund:setVolume(clamp(fundVol, 0.0, 0.205))
    engineFund:playNote(hz)

    engineRasp:setVolume(clamp(raspVol, 0.0, 0.060))
    engineRasp:playNote(hz * 1.98)

    engineAir:setVolume(clamp(airVol, 0.0, 0.040))
    engineAir:playNote(150 + speedPercent * 160)
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

function Audio.titleUpdate()
    if not titlePlaying then return end

    titleFrame = titleFrame + 1
    if titleFrame % 11 == 0 then
        local note = titleNotes[(titleStep % #titleNotes) + 1]
        play(titleLead, note, 0.18, 0.11)
        titleStep = titleStep + 1
    end
end

function Audio.blip(freq, len)
    if titleLead then
        titleLead:playNote(freq or 880, 0.24, len or 0.08)
    end
end

return Audio
