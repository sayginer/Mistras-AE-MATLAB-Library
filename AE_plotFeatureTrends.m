function fig = AE_plotFeatureTrends(T, varargin)
% AE_plotFeatureTrends  Plot waveform features against time.
%
%   fig = AE_plotFeatureTrends(T)
%   fig = AE_plotFeatureTrends(T, Name, Value, ...)
%
%   One panel per feature from the table returned by AE_wfsFolderFeatures
%   (or any table with a Time_min column). Rows with NaN features, such as
%   empty recordings, appear as gaps.
%
%   NAME-VALUE OPTIONS
%     'Features' - cellstr of columns to plot
%                  (default: RMS, Kurtosis, HitCount, BandEnergy_High, Envelope_RMS)
%     'Title'    - figure title (default: none)
%
%   OUTPUT
%     fig : figure handle
%
%   EXAMPLE
%     T = AE_wfsFolderFeatures('STREAM20260121_1245', 'Channel', 2);
%     AE_plotFeatureTrends(T, 'Features', {'RMS', 'Kurtosis', 'SpectralCentroid'});
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

p = inputParser;
addParameter(p, 'Features', {'RMS', 'Kurtosis', 'HitCount', 'BandEnergy_High', 'Envelope_RMS'});
addParameter(p, 'Title',    '');
parse(p, varargin{:});
feats = cellstr(p.Results.Features);

assert(ismember('Time_min', T.Properties.VariableNames), ...
    'AE_plotFeatureTrends: table needs a Time_min column');
missing = feats(~ismember(feats, T.Properties.VariableNames));
assert(isempty(missing), 'AE_plotFeatureTrends: unknown feature(s): %s', strjoin(missing, ', '));

nf   = numel(feats);
cols = 2;
rows = ceil(nf / cols);
fig  = figure('Name', 'AE feature trends');
for i = 1:nf
    subplot(rows, cols, i);
    plot(T.Time_min, T.(feats{i}), 'LineWidth', 1.5);
    grid on;
    xlabel('Time [min]');
    ylabel(strrep(feats{i}, '_', ' '));
    title(strrep(feats{i}, '_', ' '));
end
if ~isempty(p.Results.Title) && exist('sgtitle', 'file')   % sgtitle needs R2018b
    sgtitle(p.Results.Title);
end
end
