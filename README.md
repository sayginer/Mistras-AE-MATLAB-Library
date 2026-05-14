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
├── AE_readHits_noPara.m       % Parse Msg-1 hit records from a .DTA file
├── AE_listWaveforms.m         % Catalog all Msg-173 waveforms in a .DTA file
├── AE_plotWaveformByIndex.m   % Decode and plot a single waveform by index
├── AE_exportAllWaveforms.m    % Batch-export all waveforms to a .mat file
├── openWFS.m                  % Read a .WFS waveform streaming file
├── ReadWFSHeader.m            % Parse the binary header tables of a .WFS file
├── ReadWFSDataTrunk.m         % Decode the waveform data trunk of a .WFS file
├── DTA_Viewer.m               % Demo script: view one waveform from a .DTA
├── DTAtoMAT_Converter.m       % Demo script: convert .DTA → .mat
└── WFSRunner.m                % Demo script: plot a channel from a .WFS file
```

---

## Quick Start

```matlab
% ---- DTA: read hit features ------------------------------------------
hits = AE_readHits_noPara('experiment.DTA');
amp  = [hits.amplitude_db];   % peak amplitudes in dB AE

% ---- DTA: list all waveforms -----------------------------------------
W = AE_listWaveforms('experiment.DTA');
disp(W)

% ---- DTA: plot waveform #3 -------------------------------------------
[t, y, info] = AE_plotWaveformByIndex('experiment.DTA', 3, 1, ...
                   'Fs', 1e6, 'TimeUnits', 'us', 'Units', 'mV');

% ---- DTA: batch export to .mat (do once, then load instantly) --------
AE_exportAllWaveforms('experiment.DTA', 'experiment.mat', 'Scale', 0.5);
load experiment.mat
plot(t_cell{1}, y_cell{1});

% ---- WFS: read streaming file ----------------------------------------
[data, t, header] = openWFS('experiment.wfs');
plot(t, data(1, :));   % channel 1
```

---

## Function Reference

| Function | Description |
|---|---|
| `AE_readHits_noPara(file)` | Returns struct array with amplitude, duration, counts, energy, rise time per hit |
| `AE_listWaveforms(file)` | Returns a MATLAB table cataloging every waveform (channel, amplitude, nsamp, t_rel, …) |
| `AE_plotWaveformByIndex(file, idx, plotMode)` | Decodes waveform `idx`, applies ADC→mV conversion, optionally plots |
| `AE_exportAllWaveforms(dta, mat)` | Batch-exports all waveforms to a `.mat` for fast offline analysis |
| `openWFS(file)` | Returns `[nCh × nSamples]` data matrix, time vector `[s]`, and header struct |
| `ReadWFSHeader(path, file)` | Low-level: parses .WFS header tables (called by `openWFS`) |
| `ReadWFSDataTrunk(file, path, hdrLen, vscale)` | Low-level: decodes .WFS data trunk (called by `openWFS`) |

---

## Requirements

| | |
|---|---|
| **MATLAB** | R2016b or later |
| **Toolboxes** | None required |
| **File formats** | AEwin `.DTA` (Msg-1 hits + Msg-173 waveforms), `.WFS` waveform streaming |

---

## Disclaimer

> **⚠ This software is provided "as is", without warranty of any kind, express or implied.**
>
> The author and Temple University accept **no responsibility** for errors, incorrect results, data loss, or any other damage arising from the use of this software. This is an independent, community-developed tool and is **not affiliated with, endorsed by, or supported by Mistras Group, Physical Acoustics Corporation, or any of their subsidiaries.**
>
> Binary format parsing is based on reverse-engineering and empirical testing — edge cases, firmware variants, or future AEwin versions may not be handled correctly. **Always verify results against your raw data before drawing scientific conclusions.**

---

## Citation

If you use this library in your research, please cite it as:

```bibtex
@software{sayginer_mistras_ae_library,
  author = {Sayginer, Osman},
  title  = {Mistras AE MATLAB Library},
  year   = {2026},
  url    = {https://github.com/sayginer/Mistras-AE-MATLAB-Library}
}
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.
