% WFSRunner.m
% =========================================================================
% Quick viewer for Mistras AEwin .WFS waveform streaming files.
%
% Reads the entire .WFS file, prints the header metadata, and plots the
% waveform of a selected channel.
%
% DEPENDENCIES
%   openWFS.m, ReadWFSHeader.m, ReadWFSDataTrunk.m
%
% Author : Osman Sayginer
% Affil. : Temple University — Mechatronics Lab
% Web    : https://mechatronics.sayginer.com
% Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.
% =========================================================================

clc; clear all;  %#ok<CLALL>

% ---- Read the .WFS file -------------------------------------------------
[data, t, header] = openWFS('ExampleWFSdata.wfs');

% ---- Print header metadata ----------------------------------------------
disp(header)

% ---- Plot one channel ---------------------------------------------------
ch = 1;   % channel index to plot (1-based)

figure;
plot(t, data(ch, :));
xlabel('Time (s)');
ylabel('Amplitude (mV)');
title(sprintf('WFS — Channel %d Waveform', ch));
grid on;
