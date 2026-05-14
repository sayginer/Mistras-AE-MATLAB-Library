function AE_exportAllWaveforms(DTAfile, MATfile, varargin)
% AE_exportAllWaveforms  Batch-export all waveforms from a .DTA file to a .mat file.
%
%   AE_exportAllWaveforms(DTAfile, MATfile)
%   AE_exportAllWaveforms(DTAfile, MATfile, Name, Value, ...)
%
%   Extracts every Msg-173 waveform from the AEwin .DTA file in a single
%   batch pass and saves them — together with time axes, voltage traces, and
%   waveform metadata — into a single .mat file (HDF5/v7.3 format).
%   After export, waveforms can be loaded and plotted instantly without
%   reopening or re-parsing the binary .DTA file.
%
%   INPUTS
%     DTAfile : path to the source .DTA file  (string)
%     MATfile : path for the output .mat file (string)
%
%   NAME-VALUE OPTIONS  (passed through to AE_plotWaveformByIndex)
%     'Fs'        - sample rate [Hz]         (default: 1e6)
%     'TimeUnits' - 'us' (default) or 's'
%     'Scale'     - post-ADC linear multiplier (default: 1)
%     'Units'     - 'mV' (default) or 'V'
%
%   OUTPUT FILE CONTENTS (variables saved to MATfile)
%     W         - waveform catalog table (from AE_listWaveforms)
%     t_cell    - {N x 1} cell array of time vectors
%     y_cell    - {N x 1} cell array of voltage vectors
%     info_cell - {N x 1} cell array of metadata structs
%
%   EXAMPLE
%     % Export all waveforms with 0.5× voltage scale
%     AE_exportAllWaveforms('experiment_01.DTA', 'experiment_01.mat', 'Scale', 0.5);
%
%     % Load and plot waveform 7
%     load experiment_01.mat
%     figure; plot(t_cell{7}, y_cell{7});
%     title(sprintf('Waveform 7 — Ch %d — %.1f dB AE', ...
%           W.channel(7), W.amplitude_db(7)));
%
%   DEPENDENCIES
%     AE_listWaveforms.m, AE_plotWaveformByIndex.m, AE_readHits_noPara.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

% ---- Build the waveform catalog (one pass over the .DTA) ----------------
W = AE_listWaveforms(DTAfile);
N = height(W);
fprintf('AE_exportAllWaveforms: found %d waveforms in %s\n', N, DTAfile);

% ---- Pre-allocate storage cells -----------------------------------------
t_cell    = cell(N, 1);
y_cell    = cell(N, 1);
info_cell = cell(N, 1);

% ---- Decode each waveform (plotMode = 0 → no figure) --------------------
for k = 1:N
    [t_cell{k}, y_cell{k}, info_cell{k}] = ...
        AE_plotWaveformByIndex(DTAfile, k, 0, varargin{:});
end

% ---- Save to .mat (v7.3 = HDF5, supports large arrays) ------------------
save(MATfile, 'W', 't_cell', 'y_cell', 'info_cell', '-v7.3');
fprintf('AE_exportAllWaveforms: saved %d waveforms → %s\n', N, MATfile);

end
