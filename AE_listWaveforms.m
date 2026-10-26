function W = AE_listWaveforms(src)
% AE_listWaveforms  Build a catalog table of all AE waveforms in a .DTA file.
%
%   W = AE_listWaveforms(filename)
%   W = AE_listWaveforms(D)            % D = AE_readDTA(filename), no re-parse
%
%   Returns a MATLAB table describing every Msg-173 waveform record. Each
%   waveform is paired with the Msg-1 hit record that has the same 48-bit
%   timestamp and channel, so hit feature data (amplitude, duration, counts,
%   etc.) accompanies each row.
%
%   INPUT
%     src : path to the .DTA file (string), or a struct from AE_readDTA
%
%   OUTPUT
%     W : MATLAB table with one row per waveform and columns:
%       idx          - waveform ordinal index (1-based)
%       channel      - acquisition channel
%       hit_idx      - index of the paired Msg-1 hit (0 if none matches)
%       amplitude_db - peak amplitude [dB AE]            (NaN if unpaired)
%       duration_us  - hit duration [µs]                 (NaN if unpaired)
%       counts       - threshold-crossing count          (NaN if unpaired)
%       risetime_us  - rise time [µs]                    (NaN if unpaired)
%       energy_u     - hit energy [a.u.]                 (NaN if unpaired)
%       t_rel_sec    - waveform time relative to first hit [s] (4 MHz clock)
%       nsamp        - number of ADC samples in the waveform
%
%   PAIRING
%     A waveform and its hit share the same timestamp counter value and
%     channel, so they are matched on that pair (file order does not matter).
%     Waveforms with no matching hit keep hit_idx = 0 and NaN features.
%
%   EXAMPLE
%     W = AE_listWaveforms('experiment_01.DTA');
%     disp(W(1:5, :))
%
%   DEPENDENCIES
%     AE_readDTA.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

if isstruct(src), D = src; else, D = AE_readDTA(src, 'Waveforms', false); end

Nw = numel(D.wf.channel);
assert(Nw > 0, 'AE_listWaveforms: No Msg-173 waveform records found');

H  = D.hit;
Nh = D.nhits;

% ---- Pair waveforms to hits on (timestamp counter, channel) ------------
h_ref = zeros(Nw, 1);
if Nh > 0
    [found, loc] = ismember([D.wf.counter, D.wf.channel], [H.counter, H.channel], 'rows');
    h_ref(found) = loc(found);
end

% ---- Pull hit features for paired rows (NaN where unpaired) -------------
amp = nan(Nw, 1);  dur = nan(Nw, 1);  cnt = nan(Nw, 1);
rise = nan(Nw, 1); en = nan(Nw, 1);
ok = h_ref > 0;
amp(ok)  = double(H.amplitude_db(h_ref(ok)));
dur(ok)  = double(H.duration_us(h_ref(ok)));
cnt(ok)  = double(H.counts(h_ref(ok)));
rise(ok) = double(H.risetime_us(h_ref(ok)));
en(ok)   = double(H.energy_u(h_ref(ok)));

% Reference time for t_rel_sec: the first hit, or the first waveform when the
% file holds no hits at all.
if Nh > 0, t0 = H.time_s(1); else, t0 = D.wf.time_s(1); end
t_rel = D.wf.time_s - t0;

idx   = (1:Nw).';
chan  = D.wf.channel;
nsamp = D.wf.nsamp(:);

W = table(idx, chan, h_ref, amp, dur, cnt, rise, en, t_rel, nsamp, ...
    'VariableNames', {'idx','channel','hit_idx','amplitude_db', ...
                      'duration_us','counts','risetime_us','energy_u', ...
                      't_rel_sec','nsamp'});
end
