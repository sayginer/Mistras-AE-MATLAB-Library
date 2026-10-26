# Mistras AE MATLAB Library

A MATLAB library for reading, decoding, and visualizing Acoustic Emission data files produced by **Mistras / Physical Acoustics AEwin** software (`.DTA` and `.WFS` formats).

---

## Overview

Mistras AEwin records Acoustic Emission experiments as proprietary binary files:
- **`.DTA`** — hit feature data (Msg-1) and raw waveforms (Msg-173)
- **`.WFS`** — continuous waveform streaming data

This library provides a clean MATLAB interface to parse both formats — extracting hit features, raw ADC waveforms, channel metadata, and timestamps — **without requiring AEwin software or any additional MATLAB toolboxes**.

---

## File Structure

```
Mistras-AE-MATLAB-Library/
├── AE_readDTA.m               % Single-pass .DTA parser (hits + waveforms), used by all DTA functions
├── AE_readHits_noPara.m       % Parse Msg-1 hit records from a .DTA file
├── AE_listWaveforms.m         % Catalog all Msg-173 waveforms in a .DTA file
├── AE_plotWaveformByIndex.m   % Decode and plot a single waveform by index
├── AE_exportAllWaveforms.m    % Batch-export all waveforms to a .mat file
├── AE_plotHits.m              % Hit table + amplitude / cumulative counts / energy plots
├── AE_waveformSpectrum.m      % FFT amplitude spectrum (+ filter, normalisation), peak / centroid
├── AE_waveformFeatures.m      % RMS, kurtosis, band energies, envelope, Hjorth ... of one waveform
├── AE_wfsFolderFeatures.m     % Features of every .wfs in a folder -> table over time
├── AE_plotFeatureTrends.m     % Plot those features against time
├── openWFS.m                  % Read a .WFS waveform streaming file
├── ReadWFSHeader.m            % Parse the binary header tables of a .WFS file
├── ReadWFSDataTrunk.m         % Decode the waveform data trunk of a .WFS file
├── DTA_Viewer.m               % Demo script: view one waveform from a .DTA
├── DTAtoMAT_Converter.m       % Demo script: convert .DTA → .mat
├── WFSRunner.m                % Demo script: plot a channel from a .WFS file
└── TestAELibrary.m            % Unit tests (run: runtests('TestAELibrary'))
```

---

## Quick Start

```matlab
% ---- DTA: read hit features ------------------------------------------
hits = AE_readHits_noPara('experiment.DTA');
amp  = [hits.amplitude_db];   % peak amplitudes in dB AE

% ---- DTA: parse once, then list / plot many waveforms ----------------
D = AE_readDTA('experiment.DTA');
W = AE_listWaveforms(D);
disp(W)

% ---- DTA: plot waveform #3 -------------------------------------------
[t, y, info] = AE_plotWaveformByIndex(D, 3, 1, ...
                   'Fs', 1e6, 'TimeUnits', 'us', 'Units', 'mV');

% ---- DTA: hit summary plots (amplitude, cumulative counts/energy) ----
H = AE_plotHits('experiment.DTA');                       % table of hit features
H = AE_plotHits('experiment.DTA', 'Channels', 1, 'TimeUnits', 'min');

% ---- DTA: frequency content of waveform #3 ----------------------------
[t, y, info] = AE_plotWaveformByIndex(D, 3, 0);
[f, A, s] = AE_waveformSpectrum(y, info.Fs, 'Plot', true);
fprintf('Peak %.1f kHz, centroid %.1f kHz\n', s.peak_freq_Hz/1e3, s.centroid_freq_Hz/1e3);

% ---- DTA: very large file -> hits only (column vectors, no samples) ---
D = AE_readDTA('big.DTA', 'Waveforms', false);   % 5 million hits in ~1 s
plot(D.hit.time_s, D.hit.amplitude_db, '.');

% ---- DTA: batch export to .mat (do once, then load instantly) --------
AE_exportAllWaveforms('experiment.DTA', 'experiment.mat', 'Scale', 0.5);
load experiment.mat
plot(t_cell{1}, y_cell{1});

% ---- WFS: read streaming file ----------------------------------------
[data, t, header] = openWFS('experiment.wfs');
plot(t, data(1, :));   % channel 1

% ---- WFS: filtered, normalised spectrum (no toolboxes needed) ---------
[f, A] = AE_waveformSpectrum(data(1, :), header.SampleRate_Hz(1), ...
             'Filter', 'bandpass', 'FilterFreqs', [100e3 400e3], 'Norm', 'max');

% ---- WFS: condition-monitoring trend over a whole folder of .wfs ------
T = AE_wfsFolderFeatures('STREAM20260121_1245', 'Channel', 2);   % one row per file
AE_plotFeatureTrends(T);                                         % RMS, kurtosis, ...
```

---

## Function Reference

| Function | Description |
|---|---|
| `AE_readDTA(file, 'Waveforms', ...)` | Parses the file once; returns setup (`D.setup`), hits as column vectors (`D.hit`) and waveform samples (`D.wf`). The hit layout comes from the file's own event definition. `'Waveforms'` false skips samples; a vector decodes only those indices |
| `AE_readHits_noPara(file)` | Returns struct array with amplitude, duration, counts, energy, rise time and `time_s` per hit (slow for millions of hits: prefer `D.hit`) |
| `AE_listWaveforms(file or D)` | Returns a MATLAB table cataloging every waveform (channel, amplitude, nsamp, t_rel, …); waveforms are paired to hits by timestamp + channel |
| `AE_plotWaveformByIndex(file or D, idx, plotMode, ...)` | Decodes waveform `idx`, applies ADC→mV conversion, optionally plots. Pass `D` instead of a filename when looping over many waveforms |
| `AE_plotHits(file or D, ...)` | Returns a time-sorted hit-feature table (with cumulative counts/energy) and draws a 2×2 summary; options `'Channels'`, `'Plot'`, `'TimeUnits'` |
| `AE_waveformSpectrum(y, Fs, ...)` | Single-sided amplitude spectrum `[f, A, stats]` with peak and centroid frequency; options `'Window'`, `'NFFT'`, `'FreqRange'`, `'Filter'`/`'FilterFreqs'` (zero-phase Butterworth), `'Norm'`, `'Plot'` |
| `AE_waveformFeatures(x, Fs or t)` | 26 time / frequency / envelope / Hjorth features of one waveform (same definitions as the Signal Processing and Statistics Toolbox functions; no wavelet features) |
| `AE_wfsFolderFeatures(folder, ...)` | Features of one channel for every `.wfs` in a folder, as a table with `Time_min` (from the file names, or `'DtMinutes'`). Empty or unreadable files become NaN rows with a `Status` |
| `AE_plotFeatureTrends(T, ...)` | One trend panel per feature from that table |
| `AE_exportAllWaveforms(dta, mat)` | Batch-exports all waveforms to a `.mat` for fast offline analysis |
| `openWFS(file)` | Returns `[nCh × nSamples]` data matrix, time vector `[s]`, and header struct. A header-only recording returns empty data with the warning `AE:emptyWFS` |
| `ReadWFSHeader(path, file)` | Low-level: parses .WFS header tables (called by `openWFS`) |
| `ReadWFSDataTrunk(file, path, hdrLen, vscale)` | Low-level: decodes .WFS data trunk (called by `openWFS`) |

---

## Requirements

| | |
|---|---|
| **MATLAB** | R2016b or later |
| **Toolboxes** | None required |
| **Tests** | `runtests('TestAELibrary')` (23 tests; developed and verified on R2026a) |
| **File formats** | AEwin `.DTA` (Msg-1 hits + Msg-173 waveforms), `.WFS` waveform streaming |

---

## Validation and known limits

Checked on 43 real `.DTA` files (about 5.9 million hits, up to 1 GB per file, including the
AEwin64 `Felicity.DTA` sample with 11 hit characteristics and variable-length waveforms) and
1,574 real `.wfs` files:

- Hit decoding follows the AEwin64 *Data File Definition* (Msg 5 event definition) and is
  identical to the earlier fixed-layout reader on every lab file.
- Waveforms are paired to hits by timestamp and channel. Unpaired waveforms (e.g. the last
  frame of a file that was cut short) are kept with `hit_idx = 0` and NaN features.
- `AE_waveformFeatures` and the spectrum filter agree with the Signal Processing / Statistics
  Toolbox versions (features to 1e-14, lowpass/highpass filtering to 0.3 %, bandpass to about 5 %).

Known limits:

- The sample rate (`Fs`, default 1 MHz) and the ADC scale (0.000305 V/count) are defaults, not
  read from the file. Pass `'Fs'` if your acquisition used another rate.
- Hit characteristics are decoded in file order up to the first one this reader does not know the
  size of (e.g. CHIDs 20-24 in SAMOS files); everything before it is exact.
- `AE_readDTA` loads the whole file into memory (a 1 GB file needs a few GB of RAM).
- Only the first test label, product string and event definition of a `.DTA` are read.

---

## Disclaimer

> **⚠ This software is provided "as is", without warranty of any kind, express or implied.**
>
> The author and Temple University accept **no responsibility** for errors, incorrect results, data loss, or any other damage arising from the use of this software. This is an independent, community-developed tool and is **not affiliated with, endorsed by, or supported by Mistras Group, Physical Acoustics Corporation, or any of their subsidiaries.**
>
> Binary format parsing is based on reverse-engineering and empirical testing — edge cases, firmware variants, or future AEwin versions may not be handled correctly. **Always verify results against your raw data before drawing scientific conclusions.**

---

## Citation

If you use this library in your research, please cite it as
([DOI: 10.5281/zenodo.23519131](https://doi.org/10.5281/zenodo.23519131)):

```bibtex
@software{sayginer_mistras_ae_library,
  author = {Sayginer, Osman},
  title  = {Mistras AE MATLAB Library},
  year   = {2026},
  doi    = {10.5281/zenodo.23519131},
  url    = {https://doi.org/10.5281/zenodo.23519131}
}
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.
