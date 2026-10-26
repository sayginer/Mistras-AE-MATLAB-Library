function T = AE_wfsFolderFeatures(folder, varargin)
% AE_wfsFolderFeatures  Extract waveform features from every .wfs file in a folder.
%
%   T = AE_wfsFolderFeatures(folder)
%   T = AE_wfsFolderFeatures(folder, Name, Value, ...)
%
%   Reads each .wfs file (sorted by name), computes AE_waveformFeatures on one
%   channel and returns one table row per file, ready for trending. Files that
%   hold no data (recording stopped before the first block) or cannot be read
%   keep their row with NaN features and a Status message, so the time axis
%   and row count always match the file list.
%
%   INPUT
%     folder : folder containing the .wfs files (string)
%
%   NAME-VALUE OPTIONS
%     'Channel'     - row of the data matrix to analyse (default: 1)
%     'DtMinutes'   - nominal minutes between files. If omitted, the time of
%                     each file is taken from its name (STREAMyyyymmdd-HHMMSS-nnn.wfs)
%     'Features'    - function handle f(x, Fs) returning a feature struct
%                     (default: @AE_waveformFeatures)
%     'SaveAs'      - path of a .mat file; the table is saved there as T
%     'Verbose'     - print progress every 25 files (default: true)
%
%   OUTPUT
%     T : table with columns
%           File       - file name
%           Status     - 'ok', 'empty', or the error message
%           Timestamp  - datetime from the file name (NaT if not parseable)
%           Time_min   - minutes since the first file
%         followed by one column per feature
%
%   EXAMPLE
%     T = AE_wfsFolderFeatures('Data_To_Analyze\STREAM20260121_1245', 'Channel', 2);
%     AE_plotFeatureTrends(T);
%
%   DEPENDENCIES
%     openWFS.m, AE_waveformFeatures.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

p = inputParser;
addParameter(p, 'Channel',   1);
addParameter(p, 'DtMinutes', []);
addParameter(p, 'Features',  @AE_waveformFeatures);
addParameter(p, 'SaveAs',    '');
addParameter(p, 'Verbose',   true);
parse(p, varargin{:});
ch      = p.Results.Channel;
featFcn = p.Results.Features;

files = dir(fullfile(folder, '*.wfs'));
assert(~isempty(files), 'AE_wfsFolderFeatures: no .wfs files in %s', folder);
[~, order] = sort({files.name});
files = files(order);
n = numel(files);

feats  = cell(n, 1);
status = repmat({'ok'}, n, 1);
ws = warning('off', 'AE:emptyWFS');
restoreWarning = onCleanup(@() warning(ws));

for k = 1:n
    if p.Results.Verbose && (k == 1 || mod(k, 25) == 0 || k == n)
        fprintf('AE_wfsFolderFeatures: %d / %d  %s\n', k, n, files(k).name);
    end
    try
        [data, ~, h] = openWFS(fullfile(files(k).folder, files(k).name));
        if isempty(data)
            status{k} = 'empty';
        elseif ch > size(data, 1)
            error('channel %d requested but file has %d', ch, size(data, 1));
        else
            feats{k} = featFcn(data(ch, :), h.SampleRate_Hz(1));
        end
    catch ME
        status{k} = ME.message;
    end
end

% ---- Assemble: failed rows get NaN in every feature column --------------
ok = find(~cellfun(@isempty, feats), 1);
assert(~isempty(ok), 'AE_wfsFolderFeatures: no file in %s produced features', folder);
tmpl = feats{ok};
fn   = fieldnames(tmpl);
for f = 1:numel(fn)
    tmpl.(fn{f}) = nan(size(tmpl.(fn{f})));
end
for k = 1:n
    if isempty(feats{k}), feats{k} = tmpl; end
end
T = struct2table([feats{:}].');

% ---- Time axis ----------------------------------------------------------
ts = NaT(n, 1);
for k = 1:n
    tok = regexp(files(k).name, '(\d{8})-(\d{6})', 'tokens', 'once');
    if ~isempty(tok)
        ts(k) = datetime([tok{1} tok{2}], 'InputFormat', 'yyyyMMddHHmmss');
    end
end
dt = p.Results.DtMinutes;
if ~isempty(dt)
    Time_min = (0:n-1).' * dt;
elseif ~any(isnat(ts))
    Time_min = minutes(ts - ts(1));
else
    warning('AE:noFileTimes', ['AE_wfsFolderFeatures: file names carry no time stamp; ' ...
        'using the file index as Time_min (pass ''DtMinutes'' to set the spacing).']);
    Time_min = (0:n-1).';
end

File = {files.name}.';
Status = status;
Timestamp = ts;
T = [table(File, Status, Timestamp, Time_min), T];

if ~isempty(p.Results.SaveAs)
    save(p.Results.SaveAs, 'T');
end
end
