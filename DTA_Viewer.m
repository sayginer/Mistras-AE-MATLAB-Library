% DTA_Viewer.m
% =========================================================================
% Interactive single-waveform viewer for Mistras AEwin .DTA files.
%
% Loads one waveform by index, plots it, and prints timing information.
% Adjust 'FileName' and 'WF_Name' (waveform index) to inspect any hit.
%
% DEPENDENCIES
%   AE_listWaveforms.m, AE_plotWaveformByIndex.m, AE_readHits_noPara.m
%
% Author : Osman Sayginer
% Affil. : Temple University — Mechatronics Lab
% Web    : https://mechatronics.sayginer.com
% Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.
% =========================================================================

clc; clear; close all;

tic

% ---- Configuration ------------------------------------------------------
FileName = 'ExampleDTAfile.DTA';   % path to your .DTA file
WF_Name  = 1;                      % waveform index to display (1-based)

% ---- List all waveforms (builds the catalog) ----------------------------
W = AE_listWaveforms(FileName);
fprintf('Total waveforms found: %d\n', height(W));
% disp(W);   % uncomment to print full catalog table

% ---- Load and plot the selected waveform --------------------------------
%   plotMode = 1  → opens a figure
%   'Scale', 0.5  → apply 0.5× post-ADC voltage multiplier (adjust as needed)
[t, y, info] = AE_plotWaveformByIndex(FileName, WF_Name, 1, 'Scale', 0.5);

fprintf('Waveform %d  |  Ch %d  |  %.1f dB AE  |  %d samples\n', ...
        WF_Name, info.channel, info.amplitude_db, info.nsamp);

toc
