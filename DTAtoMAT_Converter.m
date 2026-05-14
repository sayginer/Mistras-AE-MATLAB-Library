% DTAtoMAT_Converter.m
% =========================================================================
% Batch converter: exports all waveforms from a .DTA file to a .mat file,
% then demonstrates loading and plotting a single waveform from the .mat.
%
% WHY USE THIS?
%   Parsing a large .DTA binary on every run is slow. This script converts
%   it once to a MATLAB-native .mat file (HDF5 v7.3 format). Subsequent
%   analyses load the .mat in a fraction of the time.
%
% OUTPUT FILE CONTAINS:
%   W         — waveform catalog table (from AE_listWaveforms)
%   t_cell    — {N×1} cell of time vectors  [µs or s depending on options]
%   y_cell    — {N×1} cell of voltage vectors [mV or V]
%   info_cell — {N×1} cell of metadata structs
%
% DEPENDENCIES
%   AE_exportAllWaveforms.m, AE_listWaveforms.m,
%   AE_plotWaveformByIndex.m, AE_readHits_noPara.m
%
% Author : Osman Sayginer
% Affil. : Temple University — Mechatronics Lab
% Web    : https://mechatronics.sayginer.com
% Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.
% =========================================================================

clc; clear; close all;

% =========================================================================
% STEP 1: Convert .DTA → .mat  (run once, then comment out if desired)
% =========================================================================
tic
FileName = 'ExampleDTAfile.DTA';   % source .DTA file
OutMAT   = 'DTA_Converted.mat';    % output .mat file

% 'Scale', 0.5 applies a 0.5× post-ADC voltage multiplier — adjust as needed
AE_exportAllWaveforms(FileName, OutMAT, 'Scale', 0.5);
toc

% =========================================================================
% STEP 2: Load .mat and plot a specific waveform (fast — no .DTA parsing)
% =========================================================================
tic
load(OutMAT);   % loads: W, t_cell, y_cell, info_cell

k = 2;          % waveform index to plot
t = t_cell{k};
y = y_cell{k};

figure;
plot(t, y);
grid on;
xlabel('Time (\mus)');
ylabel('Amplitude (mV)');
title(sprintf('Waveform %d  |  Ch %d  |  %.1f dB AE', ...
              k, W.channel(k), W.amplitude_db(k)));
toc
