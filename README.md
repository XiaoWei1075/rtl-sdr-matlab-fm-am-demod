# MATLAB SDR — Educational AM/FM Broadcast Demodulation System

A Software Defined Radio (SDR) teaching platform built on RTL-SDR Blog V4 hardware and MATLAB. Supports spectrum analysis, offline (non-real-time) demodulation of pre-recorded IQ data, and real-time demodulation of live broadcast signals.

## Background

This project is the coursework deliverable for a university "Digital Radio System Design" course. Using the RTL-SDR Blog V4 as the RF front-end, combined with SDR#/SDR++ and MATLAB, it systematically explores signal reception, spectrum analysis, and modulation/demodulation in an SDR context. The workflow spans hardware driver setup, broadcast signal reception, IQ baseband recording, and both offline and real-time demodulation system design in MATLAB.

## Features

### Offline Demodulation (`SDR_Demod_GUI.m`)

- Loads dual-channel IQ WAV files recorded by SDR++ or SDR#
- Auto-parses recording center frequency from filename (SDR++ naming convention)
- Dual-mode: AM envelope detection / FM phase-difference discrimination
- Digital down-conversion: shifts target station to baseband when its frequency differs from the recording center frequency
- Spectrum visualization: FFT with reference lines for center frequency and target station
- Demodulated waveform display (50 ms preview window)
- Audio post-processing: RMS AGC + tanh soft limiter
- 48 kHz audio output with playback

### Real-Time Demodulation (`SDR_RealTime_GUI.m`)

- Live RTL-SDR streaming via `comm.SDRRTLReceiver`
- Real-time AM/FM demodulation with audio playback
- Real-time spectrum and waveform visualization
- On-the-fly center frequency and gain adjustment
- IQ baseband recording (`.bb` format)
- Multiple real-time optimizations (see Performance Optimizations below)

## Hardware Requirements

| Device | Notes |
|--------|-------|
| RTL-SDR Blog V4 | Core receiver (R828D tuner + RTL2832U ADC) |
| Antenna | SMA connector; telescopic whip for FM, loop antenna for AM |
| PC | Windows / Linux / macOS with USB 2.0 |

> **Note:** The offline system requires no hardware — only pre-recorded IQ WAV files. The real-time system requires RTL-SDR hardware.

## Software Dependencies

| Software | Version | Purpose |
|----------|---------|---------|
| MATLAB | R2023b or later | Running the demodulation GUIs |
| Communications Toolbox | — | `comm.SDRRTLReceiver`, `comm.BasebandFileWriter` (required for real-time) |
| DSP System Toolbox | — | `dsp.FIRDecimator` polyphase decimator (required for real-time) |
| Audio Toolbox | Optional | `audioDeviceWriter` for real-time playback (degrades gracefully if absent) |
| SDR# or SDR++ | — | IQ baseband recording (for offline system) |
| Zadig USB driver | — | RTL-SDR driver installation (Windows) |

## Quick Start

### 1. Offline Demodulation

```matlab
% In the MATLAB command window:
SDR_Demod_GUI
```

Steps:
1. Click **"Load IQ File"** and select a dual-channel WAV file recorded by SDR++/SDR#
2. Enter the target broadcast frequency (MHz) and click **OK**
3. Select modulation mode: **AM** or **FM**
4. Click **"Demodulate"**
5. Click **"▶ Play"** to listen to the demodulated audio

### 2. Real-Time Demodulation (requires RTL-SDR hardware)

```matlab
% In the MATLAB command window:
SDR_RealTime_GUI
```

Steps:
1. Connect the RTL-SDR Blog V4; ensure Zadig driver is properly installed
2. Enter the target frequency (MHz) and gain (dB), then click **"Tune"**
3. Select mode: **FM** (default 105.6 MHz) or **AM** (default 1.008 MHz)
4. Click **"▶ Start"** to begin real-time reception and demodulation
5. Optional: click **"⏺ Record"** to save IQ baseband data
6. Click **"■ Stop"** to end

## System Architecture

### DSP Signal Processing Pipeline

```
IQ Data Input
    │
    ▼
Digital Down-Conversion (frequency shift to baseband)
    │
    ▼
Channel Low-Pass FIR Filtering (Kaiser window)
  FM: 75 kHz cutoff  |  AM: 10 kHz cutoff
    │
    ▼
Demodulation
  FM: phase-difference discriminator  |  AM: envelope detection
    │
    ▼
Polyphase Decimation Filtering (anti-aliasing + 20× decimation → 48 kHz)
    │
    ▼
Audio Post-Processing
  ├── IIR DC removal ([1 -1] / [1 -0.995])
  ├── RMS AGC (smoothed gain interpolation)
  └── tanh soft limiter
    │
    ▼
Audio Output / Playback
```

### Key Differences Between the Two Systems

| Aspect | Offline (`SDR_Demod_GUI`) | Real-Time (`SDR_RealTime_GUI`) |
|--------|--------------------------|--------------------------------|
| Data source | Pre-recorded WAV files | RTL-SDR live stream |
| Filtering | `filtfilt` (zero-phase, bidirectional) | `filter` (causal, state-preserving across frames) |
| Decimation | `resample` | `dsp.FIRDecimator` (polyphase) |
| Inter-frame continuity | N/A (batch processing) | Filter states + NCO phase preserved across frames |
| Driving mechanism | GUI button callbacks | Timer (30 ms period) |

## Performance Optimizations (Real-Time System)

The real-time system incorporates several optimizations tailored to MATLAB's interpreted execution model:

1. **Reduced sample rate**: 960 kHz (vs. the conventional 2.4 MHz), significantly lowering DSP computation
2. **Large frame size**: `SamplesPerFrame = 32000` (33.3 ms of data), reducing function call overhead
3. **Pre-designed filters**: FIR coefficients computed once at startup; only `filter()` is called at runtime
4. **Polyphase decimation**: Audio LPF + anti-aliasing + 20× decimation merged into a single operation via `dsp.FIRDecimator`, reducing multiply-accumulate operations by ~95%
5. **Cross-frame phase continuity**: FM discriminator saves the last IQ sample of each frame and reuses it as the delayed sample for the next frame, eliminating 30 Hz clicking artifacts at frame boundaries
6. **Throttled GUI refresh**: Spectrum and waveform updated every 10 frames (~350 ms) with `drawnow limitrate`
7. **AM hardware tuning compensation**: RTL-SDR V4 cannot tune directly below ~500 kHz; the system automatically shifts the hardware to the nearest supported frequency (740 kHz or 1065 kHz) and compensates with a digital frequency offset

## Key Innovations

1. **Digital down-conversion preprocessing in the offline system**: Resolves target station frequency misalignment caused by wideband SDR++ recording
2. **Polyphase decimation filter replacing conventional stepwise downsampling**: ~95% reduction in multiply-accumulate operations
3. **Cross-frame phase continuity in FM discrimination**: Eliminates periodic clicking artifacts inherent to block-based processing
4. **Soft limiting + IIR continuous DC removal**: Superior subjective audio quality compared to hard clipping and per-block mean subtraction

## Experimental Results

| Metric | FM Broadcast | AM Broadcast |
|--------|-------------|-------------|
| Frequency band | 87–108 MHz | 526.5–1606.5 kHz |
| Channel bandwidth | ≈200 kHz | ≈9 kHz |
| Audio quality | Clear, noise-robust | Environment-dependent, noisier |
| Spectrum signature | Wideband, flat distribution | Narrowband, prominent carrier spike at center |

Digital down-conversion and channel filtering are the two indispensable steps in the SDR demodulation chain — omitting down-conversion causes frequency misalignment, and omitting channel filtering introduces severe adjacent-channel interference and wideband noise.

## File Overview

| File | Description |
|------|-------------|
| `SDR_Demod_GUI.m` | Offline demodulation GUI (~410 lines) |
| `SDR_RealTime_GUI.m` | Real-time demodulation GUI (~610 lines) |

## License

This project is intended for educational and learning purposes only.
