function W = AE_listWaveforms(filename)
% AE_listWaveforms  Build a catalog table of all AE waveforms in a .DTA file.
%
%   W = AE_listWaveforms(filename)
%
%   Scans a Physical Acoustics / Mistras AEwin .DTA binary file in a single
%   pass and returns a MATLAB table describing every Msg-173 waveform record.
%   Each waveform is paired to its corresponding Msg-1 hit record (matched by
%   file order; time-nearest fallback when hit count < waveform count) so that
%   hit feature data (amplitude, duration, counts, etc.) accompanies each row.
%
%   INPUT
%     filename : full or relative path to the .DTA file (string)
%
%   OUTPUT
%     W : MATLAB table with one row per waveform and columns:
%       idx          - waveform ordinal index (1-based)
%       channel      - acquisition channel (from paired hit)
%       hit_idx      - index of the paired Msg-1 hit record
%       amplitude_db - peak amplitude [dB AE]
%       duration_us  - hit duration [µs]
%       counts       - threshold-crossing count
%       risetime_us  - rise time [µs]
%       energy_u     - hit energy [a.u.]
%       t_rel_sec    - event time relative to first hit [s]
%       nsamp        - number of ADC samples in the waveform
%
%   ALGORITHM
%     1. The entire file is read once into memory.
%     2. All Msg-173 (waveform) and Msg-1 (hit) bodies are collected in file
%        order with their byte positions preserved.
%     3. Hit timestamps (48-bit, 4 MHz clock) are decoded and the inter-hit
%        cadence is used to estimate clock counts-per-second (median of diffs).
%     4. Each waveform is paired to the hit of the same ordinal index.
%        If more waveforms than hits exist, the nearest-by-time hit is used.
%     5. Sample count (nsamp) is derived from the body length, not from an
%        explicit header field, to be robust to encoder variations:
%          - If bytes 8-9 equal a uint16 N that satisfies  7+2+2N == bodyLen,
%            the record contains an explicit nsamp word → use N.
%          - Otherwise the remaining bytes after the 7-byte header are treated
%            as a raw int16 stream → nsamp = remaining / 2.
%
%   EXAMPLE
%     W = AE_listWaveforms('experiment_01.DTA');
%     disp(W(1:5, :))
%
%   DEPENDENCIES
%     AE_readHits_noPara.m  — hit-record parser (must be on MATLAB path)
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

% ---- Read entire file into memory as a raw byte vector ------------------
fid = fopen(filename, 'rb');
assert(fid > 0, 'AE_listWaveforms: Cannot open file: %s', filename);
c = onCleanup(@() fclose(fid));
R = fread(fid, inf, 'uint8=>uint8');
L = numel(R);

% ---- Single-pass scan: collect Msg-173 and Msg-1 bodies -----------------
pos       = 1;
wfBodies  = {};
hitBodies = {};  %#ok<NASGU>  (reserved for future use)

while pos <= L - 3
    len = uint16(R(pos)) + bitshift(uint16(R(pos+1)), 8);
    id  = R(pos+2);
    b0  = pos + 3;
    b1  = pos + 1 + double(len);
    if b1 > L, break; end

    if id == 173
        wfBodies{end+1} = R(b0:b1);   %#ok<AGROW>
    elseif id == 1
        hitBodies{end+1} = R(b0:b1);  %#ok<AGROW>
    end

    pos = pos + 2 + double(len);
end

Nw = numel(wfBodies);
assert(Nw > 0, 'AE_listWaveforms: No Msg-173 waveform records found in %s', filename);

% ---- Decode all hits via the dedicated hit parser -----------------------
hits = AE_readHits_noPara(filename);
Nh   = numel(hits);
assert(Nh > 0, 'AE_listWaveforms: No Msg-1 hit records found in %s', filename);

% ---- Convenience: convert 48-bit timestamp bytes to uint64 scalar ------
toU48 = @(A) u48_any(A);

% ---- Build hit clock-counter array (Nh x 1) ----------------------------
T6_hits = cell2mat(arrayfun(@(h) h.time6(:).', hits, 'uni', false).');  % Nh x 6
Ch = zeros(Nh, 1);
for i = 1:Nh
    Ch(i) = double(toU48(uint8(T6_hits(i,:))));
end

% ---- Estimate clock counts-per-second from median inter-hit cadence ----
% This is more robust than assuming a fixed 4 MHz because the recorded
% counter may already be scaled differently in some AEwin versions.
dC  = diff(Ch);
dC  = dC(dC > 0);
cps = median(dC);
if isempty(dC) || cps == 0, cps = 1; end   % fallback: ratios stay raw

% ---- Decode each waveform's own 48-bit timestamp (for fallback pairing) -
Cw = zeros(Nw, 1);
for k = 1:Nw
    B     = wfBodies{k};
    Cw(k) = double(toU48(uint8(double(B(1:6)).')));
end

% ---- Pair each waveform to a hit ----------------------------------------
% Primary: same ordinal index (Msg-173 #k → Msg-1 #k).
% Fallback: nearest by timestamp counter when waveforms outnumber hits.
h_ref = zeros(Nw, 1, 'uint32');
for k = 1:Nw
    if k <= Nh
        h_ref(k) = k;
    else
        [~, h_ref(k)] = min(abs(Ch - Cw(k)));
    end
end

% ---- Pre-allocate output columns ----------------------------------------
idx   = (1:Nw).';
chan  = zeros(Nw, 1);
nsamp = zeros(Nw, 1, 'uint32');
t_rel = zeros(Nw, 1);
amp   = zeros(Nw, 1);
dur   = zeros(Nw, 1);
cnt   = zeros(Nw, 1, 'uint32');
rise  = zeros(Nw, 1);
en    = zeros(Nw, 1, 'uint32');

Ch0 = Ch(1);   % reference counter (first hit)

% ---- Fill per-waveform rows ---------------------------------------------
for k = 1:Nw
    B       = wfBodies{k};
    bodyLen = numel(B);

    % ---- Determine sample count from body layout -----------------------
    % Waveform body layout (bytes):
    %   [time6 (6)] [channel (1)] [nsamp_u16 (2, optional)] [int16 samples ...]
    % If the optional nsamp word is present: bodyLen == 7 + 2 + 2*nsamp
    % If absent:                             bodyLen == 7 + 2*nsamp  (even rem)

    remAfterCh = bodyLen - 7;   % bytes after the 7-byte (time6+ch) header
    ns_calc    = NaN;
    has_u16    = false;

    if remAfterCh >= 2
        n_le = double(typecast(uint8(B(8:9)), 'uint16'));   % candidate nsamp word
        if (7 + 2 + 2*n_le) == bodyLen
            ns_calc = n_le;
            has_u16 = true;
        end
    end

    if ~has_u16
        if remAfterCh >= 2 && mod(remAfterCh, 2) == 0
            ns_calc = remAfterCh / 2;   % raw int16 stream (no explicit nsamp)
        else
            ns_calc = remAfterCh;       % int8 fallback (uncommon)
        end
    end

    if ns_calc <= 0
        ns_calc = max(1, floor(remAfterCh / 2));
    end
    nsamp(k) = uint32(ns_calc);

    % ---- Pull feature metrics from the paired hit -----------------------
    hi      = h_ref(k);
    H       = hits(hi);

    chan(k) = H.channel;
    amp(k)  = H.amplitude_db;
    dur(k)  = H.duration_us;
    cnt(k)  = H.counts;
    rise(k) = H.risetime_us;
    en(k)   = H.energy_u;

    % Relative time: (waveform counter − first-hit counter) / cps
    t_rel(k) = (double(toU48(uint8(H.time6(:).'))) - Ch0) / cps;
end

% ---- Assemble output table ----------------------------------------------
W = table(idx, chan, h_ref, amp, dur, cnt, rise, en, t_rel, nsamp, ...
    'VariableNames', {'idx','channel','hit_idx','amplitude_db', ...
                      'duration_us','counts','risetime_us','energy_u', ...
                      't_rel_sec','nsamp'});
end

% =========================================================================
% LOCAL HELPER
% =========================================================================
function u = u48_any(A)
% u48_any  Convert a 6-element uint8 vector (little-endian) to uint64 scalar.
% Accepts row or column orientation.
    A = uint64(reshape(A, 1, []));
    assert(numel(A) >= 6, 'u48_any: expected 6 bytes, got %d', numel(A));
    u = A(1)              + bitshift(A(2),  8) + bitshift(A(3), 16) + ...
        bitshift(A(4), 24) + bitshift(A(5), 32) + bitshift(A(6), 40);
end
