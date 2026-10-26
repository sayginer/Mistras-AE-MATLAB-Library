function [H, fig] = AE_plotHits(src, varargin)
% AE_plotHits  Tabulate and plot hit features from an AEwin .DTA file.
%
%   H = AE_plotHits(src)
%   [H, fig] = AE_plotHits(src, Name, Value, ...)
%
%   Builds a table of hit features sorted by time and draws a 2x2 summary:
%     1. peak amplitude [dB AE] vs time, one colour per channel
%     2. cumulative counts vs time (one curve per channel + total)
%     3. cumulative energy vs time (one curve per channel + total)
%     4. amplitude histogram, one colour per channel
%
%   INPUT
%     src : path to the .DTA file (string), a struct from AE_readDTA, or the
%           hit struct array returned by AE_readHits_noPara
%
%   NAME-VALUE OPTIONS
%     'Channels' - channels to include (default: all)
%     'Plot'     - true (default) draws the figure; false only returns H
%     'TimeUnits'- 's' (default), 'min' or 'h'. Time is measured from the
%                  first hit in the selection.
%
%   OUTPUTS
%     H   : table sorted by time with columns
%           channel, time (in TimeUnits, 0 = first hit), amplitude_db,
%           counts, energy_u, duration_us, risetime_us, cum_counts, cum_energy
%           (cumulative sums over all selected channels)
%     fig : figure handle ([] when 'Plot' is false)
%
%   EXAMPLE
%     H = AE_plotHits('experiment_01.DTA');
%     H = AE_plotHits('experiment_01.DTA', 'Channels', 1, 'TimeUnits', 'min');
%
%   DEPENDENCIES
%     AE_readDTA.m (when src is a filename)
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

p = inputParser;
addParameter(p, 'Channels',  []);
addParameter(p, 'Plot',      true);
addParameter(p, 'TimeUnits', 's');
parse(p, varargin{:});
chSel = p.Results.Channels;
TU    = lower(p.Results.TimeUnits);

switch TU
    case 's',   tdiv = 1;     tlab = 'Time (s)';
    case 'min', tdiv = 60;    tlab = 'Time (min)';
    case 'h',   tdiv = 3600;  tlab = 'Time (h)';
    otherwise
        error('AE_plotHits: TimeUnits must be ''s'', ''min'' or ''h''.');
end

% ---- Resolve hits from whatever the caller gave us ----------------------
if ischar(src) || isstring(src)
    hit = AE_readDTA(char(src), 'Waveforms', false).hit;
elseif isfield(src, 'hit')                       % struct from AE_readDTA
    hit = src.hit;
else                                             % struct array from AE_readHits_noPara
    hit = struct('time_s', [src.time_s].', 'channel', [src.channel].', ...
                 'amplitude_db', [src.amplitude_db].', 'counts', [src.counts].', ...
                 'energy_u', [src.energy_u].', 'duration_us', [src.duration_us].', ...
                 'risetime_us', [src.risetime_us].');
end
assert(~isempty(hit.time_s), 'AE_plotHits: No hit records found');

keep = true(size(hit.channel));
if ~isempty(chSel)
    keep = ismember(hit.channel, chSel);
    assert(any(keep), 'AE_plotHits: No hits on the requested channels');
end

% ---- Build the feature table (sorted by time) ---------------------------
[ts, order] = sort(hit.time_s(keep));
time   = (ts - ts(1)) / tdiv;
channel      = pick_(hit.channel,      keep, order);
amplitude_db = pick_(hit.amplitude_db, keep, order);
counts       = pick_(hit.counts,       keep, order);
energy_u     = pick_(hit.energy_u,     keep, order);
duration_us  = pick_(hit.duration_us,  keep, order);
risetime_us  = pick_(hit.risetime_us,  keep, order);
cum_counts   = cumsum(counts);
cum_energy   = cumsum(energy_u);

H = table(channel, time, amplitude_db, counts, energy_u, duration_us, ...
          risetime_us, cum_counts, cum_energy);

fig = [];
if ~p.Results.Plot, return; end

% ---- Figure -------------------------------------------------------------
chans  = unique(channel).';
colors = lines(max(numel(chans), 1));
fig    = figure('Name', 'AE hit summary');

subplot(2, 2, 1); hold on;
for i = 1:numel(chans)
    m = channel == chans(i);
    plot(time(m), amplitude_db(m), '.', 'Color', colors(i,:), 'MarkerSize', 12);
end
grid on; xlabel(tlab); ylabel('Amplitude (dB AE)'); title('Amplitude vs time');
legend(arrayfun(@(c) sprintf('Ch %d', c), chans, 'uni', false), 'Location', 'best');

subplot(2, 2, 2);
cumulative_panel(time, channel, counts, chans, colors);
xlabel(tlab); ylabel('Cumulative counts'); title('Cumulative counts');

subplot(2, 2, 3);
cumulative_panel(time, channel, energy_u, chans, colors);
xlabel(tlab); ylabel('Cumulative energy (a.u.)'); title('Cumulative energy');

subplot(2, 2, 4); hold on;
edges = (floor(min(amplitude_db)) : 2 : ceil(max(amplitude_db)) + 2);
for i = 1:numel(chans)
    histogram(amplitude_db(channel == chans(i)), edges, ...
        'FaceColor', colors(i,:), 'FaceAlpha', 0.6);
end
grid on; xlabel('Amplitude (dB AE)'); ylabel('Hits'); title('Amplitude distribution');
end

% =========================================================================
function v = pick_(v, keep, order)
% Selected hits (logical mask), time-sorted, as double column.
    v = double(v(keep));
    v = v(order);
end

% =========================================================================
function cumulative_panel(time, channel, value, chans, colors)
% One stairs curve per channel plus the total over all selected channels.
    hold on;
    for i = 1:numel(chans)
        m = channel == chans(i);
        stairs(time(m), cumsum(value(m)), 'Color', colors(i,:), 'LineWidth', 1.2);
    end
    stairs(time, cumsum(value), 'k--', 'LineWidth', 1.2);
    grid on;
    legend([arrayfun(@(c) sprintf('Ch %d', c), chans, 'uni', false), {'Total'}], ...
           'Location', 'best');
end
