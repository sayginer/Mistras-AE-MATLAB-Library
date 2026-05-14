function [t_out, y_out, info] = AE_plotWaveformByIndex(filename, wf_index, plotMode, varargin)
% AE_plotWaveformByIndex  Decode and (optionally) plot a single AE waveform.
%
%   [t, y, info] = AE_plotWaveformByIndex(filename, wf_index, plotMode)
%   [t, y, info] = AE_plotWaveformByIndex(filename, wf_index, plotMode, Name, Value, ...)
%
%   Extracts the wf_index-th Msg-173 waveform from an AEwin .DTA file,
%   converts raw ADC counts to physical voltage units, builds a time axis,
%   and optionally renders a figure.
%
%   INPUTS
%     filename  : path to the .DTA file (string)
%     wf_index  : 1-based waveform index (integer)
%     plotMode  : 0 = no plot  |  1 = open a new figure
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
%               .risetime_us, .energy_u, .t_rel_sec, .nsamp,
%               .decoder  - encoding detected ('int16+nsamp', 'int16 (no nsamp)', 'int8')
%               .Fs       - sample rate used [Hz]
%               .units    - voltage units string
%               .scale    - Scale factor applied
%
%   ADC SCALING
%     Raw int16 counts are mapped to volts with VPC = 0.000305 V/count
%     (±10 V full scale, 16-bit ADC: 20 / 65536 ≈ 3.05 × 10⁻⁴).
%     int8 bodies are rescaled by ×(256/32768) before the VPC factor.
%     The 'Scale' option is then applied as a final linear multiplier.
%
%   DECODER SELECTION
%     Three candidate decodings are attempted and the one with the highest
%     RMS value (non-zero) is selected, matching the actual waveform encoding:
%       int16+nsamp       - body has explicit uint16 sample count word
%       int16 (no nsamp)  - body has raw int16 stream with no count word
%       int8              - body is an int8 (unsigned, offset 128) stream
%
%   EXAMPLE
%     % Plot waveform 3 in millivolts with microsecond time axis
%     [t, y, info] = AE_plotWaveformByIndex('experiment_01.DTA', 3, 1, ...
%                        'Fs', 1e6, 'TimeUnits', 'us', 'Units', 'mV');
%
%   DEPENDENCIES
%     AE_listWaveforms.m, AE_readHits_noPara.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

% ---- Parse optional name-value arguments --------------------------------
p = inputParser;
addParameter(p, 'Fs',        1e6);    % sample rate [Hz]
addParameter(p, 'TimeUnits', 'us');   % 'us' or 's'
addParameter(p, 'Scale',     1);      % post-ADC linear multiplier
addParameter(p, 'Units',     'mV');   % 'mV' or 'V'
parse(p, varargin{:});

Fs   = p.Results.Fs;
TU   = lower(p.Results.TimeUnits);
K    = p.Results.Scale;
outU = lower(p.Results.Units);

% ---- Look up waveform metadata from the catalog -------------------------
W = AE_listWaveforms(filename);
assert(~isempty(W), 'AE_plotWaveformByIndex: No waveforms found in %s', filename);
assert(wf_index >= 1 && wf_index <= height(W), ...
    'AE_plotWaveformByIndex: wf_index %d out of range [1, %d]', wf_index, height(W));
row = W(wf_index, :);

% ---- Decode the raw waveform bytes --------------------------------------
[v_raw, nsamp, chan, decoder] = local_decode_wave(filename, wf_index);

% ---- Convert raw ADC counts → volts ------------------------------------
% ±10 V full scale / 2^15 counts = 3.05176e-4 V per count
VPC = 0.000305;   % volts per count (int16 full-scale)
switch decoder
    case {'int16+nsamp', 'int16 (no nsamp)'}
        v_adc = double(v_raw) * VPC;
    case 'int8'
        % int8 bodies use 8-bit samples; scale up to match int16 VPC
        v_adc = double(v_raw) * (VPC * 256 / 32768);
    otherwise
        v_adc = double(v_raw) * VPC;
end

% ---- Apply user-specified post-ADC scale --------------------------------
v_scaled = v_adc * K;

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
if strcmp(TU, 'us')
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
info             = table2struct(row);
info.decoder     = decoder;
info.nsamp       = nsamp;
info.channel     = chan;
info.Fs          = Fs;
info.units       = outU;
info.scale       = K;

end % main function


% =========================================================================
% LOCAL SUBFUNCTIONS
% =========================================================================

function [v, nsamp, wf_ch, decoder] = local_decode_wave(filename, wf_index)
% local_decode_wave  Extract and decode the raw ADC samples for one waveform.
%
%   Reads the file, finds the wf_index-th Msg-173 body, and tries three
%   candidate decodings. The decoding with the highest non-zero RMS wins.

    fid = fopen(filename, 'rb');
    assert(fid > 0, 'local_decode_wave: Cannot open %s', filename);
    c = onCleanup(@() fclose(fid));
    R = fread(fid, inf, 'uint8=>uint8');
    L = numel(R);

    % ---- Collect Msg-173 bodies in file order ---------------------------
    pos    = 1;
    bodies = {};
    while pos <= L - 3
        len = uint16(R(pos)) + bitshift(uint16(R(pos+1)), 8);
        id  = R(pos+2);
        b0  = pos + 3;
        b1  = pos + 1 + double(len);
        if b1 > L, break; end
        if id == 173
            bodies{end+1} = R(b0:b1);  %#ok<AGROW>
        end
        pos = pos + 2 + double(len);
    end

    assert(wf_index <= numel(bodies), ...
        'local_decode_wave: wf_index %d exceeds waveform count %d', ...
        wf_index, numel(bodies));

    B = bodies{wf_index};

    % ---- Parse body header: [time6 (6)] [channel (1)] ------------------
    ptr   = 7;                         % 0-based offset; byte 7 is channel
    wf_ch = double(B(ptr));
    ptr   = ptr + 1;                   % now points to first post-header byte

    % ---- Try three candidate decodings and pick the best ---------------
    [v1, n1] = try_int16_nsamp(B, ptr);
    [v2, n2] = try_int16_no_nsamp(B, 8);   % byte 8 = first sample (no count word)
    [v3, n3] = try_int8(B, 8);

    scores = [rmsnz(v1), rmsnz(v2), rmsnz(v3)];
    [~, ix] = max(scores);

    switch ix
        case 1,  v = v1; nsamp = n1; decoder = 'int16+nsamp';
        case 2,  v = v2; nsamp = n2; decoder = 'int16 (no nsamp)';
        case 3,  v = v3; nsamp = n3; decoder = 'int8';
    end
end

% ---- Candidate decoder 1: int16 with explicit leading nsamp uint16 ------
function [v, ns] = try_int16_nsamp(B, p)
    v = []; ns = [];
    if p + 1 > numel(B), return; end
    n  = typecast(uint8(B(p:p+1)), 'uint16');   % candidate sample count
    p2 = p + 2;
    if p2 + 2*n - 1 <= numel(B)
        v  = typecast(uint8(B(p2 : p2 + 2*n - 1)), 'int16');
        ns = double(n);
    end
end

% ---- Candidate decoder 2: raw int16 stream (no explicit count word) -----
function [v, ns] = try_int16_no_nsamp(B, p)
    v = []; ns = [];
    rem = numel(B) - p + 1;
    if rem >= 2 && mod(rem, 2) == 0
        v  = typecast(uint8(B(p : p + rem - 1)), 'int16');
        ns = rem / 2;
    end
end

% ---- Candidate decoder 3: int8 stream (offset-128 unsigned encoding) ----
function [v, ns] = try_int8(B, p)
    v = []; ns = [];
    rem = numel(B) - p + 1;
    if rem >= 1
        v  = int16(B(p : p + rem - 1)) - int16(128);
        ns = rem;
    end
end

% ---- RMS of non-zero elements (used to rank decodings) ------------------
function r = rmsnz(v)
    if isempty(v)
        r = 0;
    else
        r = sqrt(mean(double(v).^2));
    end
end
