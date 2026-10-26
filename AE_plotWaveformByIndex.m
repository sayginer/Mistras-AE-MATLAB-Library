function [t_out, y_out, info] = AE_plotWaveformByIndex(src, wf_index, plotMode, varargin)
% AE_plotWaveformByIndex  Decode and (optionally) plot a single AE waveform.
%
%   [t, y, info] = AE_plotWaveformByIndex(src, wf_index)
%   [t, y, info] = AE_plotWaveformByIndex(src, wf_index, plotMode)
%   [t, y, info] = AE_plotWaveformByIndex(src, wf_index, plotMode, Name, Value, ...)
%
%   Extracts the wf_index-th Msg-173 waveform from an AEwin .DTA file,
%   converts raw ADC counts to physical voltage units, builds a time axis,
%   and optionally renders a figure.
%
%   INPUTS
%     src       : path to the .DTA file (string), or a struct from
%                 AE_readDTA(file). Pass the struct when decoding many
%                 waveforms so the file is parsed only once. If the struct
%                 has a .catalog field (from AE_listWaveforms) it is reused.
%     wf_index  : 1-based waveform index (integer)
%     plotMode  : 0 = no plot (default)  |  1 = open a new figure
%
%   NAME-VALUE OPTIONS
%     'Fs'        - sample rate in Hz             (default: 1e6 = 1 MHz)
%     'TimeUnits' - 'us' (microseconds, default) or 's' (seconds)
%     'Scale'     - linear multiplier applied after ADC→volt conversion
%                   (useful for matched sensor/preamp calibration; default 1)
%     'Units'     - output voltage unit: 'mV' (default) or 'V'
%
%   OUTPUTS
%     t_out : time vector [Ns x 1], in units specified by 'TimeUnits'
%     y_out : voltage vector [Ns x 1], in units specified by 'Units'
%     info  : struct with waveform metadata:
%               .idx, .channel, .amplitude_db, .duration_us, .counts,
%               .risetime_us, .energy_u, .t_rel_sec, .nsamp, .hit_idx,
%               .decoder  - encoding used ('int16')
%               .Fs       - sample rate used [Hz]
%               .units    - voltage units string
%               .scale    - Scale factor applied
%
%   ADC SCALING
%     Raw int16 counts are mapped to volts with VPC = 0.000305 V/count
%     (±10 V full scale, 16-bit ADC: 20 / 65536 ≈ 3.05 × 10⁻⁴).
%     The 'Scale' option is then applied as a final linear multiplier.
%
%   EXAMPLE
%     % Plot waveform 3 in millivolts with microsecond time axis
%     [t, y, info] = AE_plotWaveformByIndex('experiment_01.DTA', 3, 1, ...
%                        'Fs', 1e6, 'TimeUnits', 'us', 'Units', 'mV');
%
%   DEPENDENCIES
%     AE_readDTA.m, AE_listWaveforms.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

if nargin < 3 || isempty(plotMode), plotMode = 0; end

% ---- Parse optional name-value arguments --------------------------------
p = inputParser;
addParameter(p, 'Fs',        1e6);    % sample rate [Hz]
addParameter(p, 'TimeUnits', 'us');   % 'us' or 's'
addParameter(p, 'Scale',     1);      % post-ADC linear multiplier
addParameter(p, 'Units',     'mV');   % 'mV' or 'V'
parse(p, varargin{:});

Fs   = p.Results.Fs;
TU   = p.Results.TimeUnits;
K    = p.Results.Scale;
outU = lower(p.Results.Units);

% ---- Parse the file (or reuse a pre-parsed struct) ----------------------
if isstruct(src), D = src; else, D = AE_readDTA(src, 'Waveforms', wf_index); end
if isfield(D, 'catalog'), W = D.catalog; else, W = AE_listWaveforms(D); end
assert(wf_index >= 1 && wf_index <= height(W) && wf_index == fix(wf_index), ...
    'AE_plotWaveformByIndex: wf_index %d out of range [1, %d]', wf_index, height(W));
assert(~isempty(D.wf.samples{wf_index}), ['AE_plotWaveformByIndex: waveform %d has no ' ...
    'samples in D (parsed with ''Waveforms'' false or without this index)'], wf_index);
row = W(wf_index, :);

% ---- Convert raw ADC counts → volts ------------------------------------
% ±10 V full scale / 2^15 counts = 3.05176e-4 V per count
VPC     = 0.000305;   % volts per count (int16 full-scale)
v_raw   = D.wf.samples{wf_index};
nsamp   = numel(v_raw);
v_scaled = double(v_raw(:)) * VPC * K;

% ---- Convert to requested voltage units ---------------------------------
switch outU
    case 'mv'
        y_out = v_scaled * 1e3;
        ylab  = 'Amplitude (mV)';
    otherwise  % 'v'
        y_out = v_scaled;
        ylab  = 'Amplitude (V)';
end

% ---- Build time axis ----------------------------------------------------
t_s = (0 : nsamp-1).' / Fs;   % time in seconds
if strcmpi(TU, 'us')
    t_out = t_s * 1e6;
    xlab  = 'Time (\mus)';
else
    t_out = t_s;
    xlab  = 'Time (s)';
end

% ---- Plot if requested --------------------------------------------------
if plotMode == 1
    figure;
    plot(t_out, y_out);
    grid on;
    xlabel(xlab);
    ylabel(ylab);
    title(sprintf('Waveform #%d  |  Ch %d  |  %.1f dB AE', ...
                  row.idx, row.channel, row.amplitude_db));
end

% ---- Assemble metadata output -------------------------------------------
info         = table2struct(row);
info.decoder = 'int16';
info.Fs      = Fs;
info.units   = outU;
info.scale   = K;

end
