function D = AE_readDTA(filename, varargin)
% AE_readDTA  Parse an AEwin .DTA file once: setup, hit records and waveforms.
%
%   D = AE_readDTA(filename)
%   D = AE_readDTA(filename, 'Waveforms', false)       % hits only (fast, small)
%   D = AE_readDTA(filename, 'Waveforms', [1 5 20])    % decode selected waveforms
%
%   Walks the message stream of a Physical Acoustics / Mistras AEwin .DTA
%   file in a single pass. Hit features are decoded in bulk into column
%   vectors (fast and memory-light even for millions of hits). All other
%   functions in this library build on this parser, so a file is read from
%   disk and scanned only once.
%
%   The set and ORDER of hit features differ between instruments and between
%   AEwin "Hit Data Set" configurations. Every file lists its own features in
%   its setup (Msg 5); this reader follows that list, so the order does not
%   matter and any recorded feature is decoded with its documented scaling.
%
%   INPUT
%     filename : full or relative path to the .DTA file (string)
%
%   NAME-VALUE OPTIONS
%     'Waveforms' - true (default): decode every waveform
%                   false: skip waveform samples (catalog data is still read)
%                   numeric vector: decode only those waveform indices
%
%   OUTPUT
%     D : struct with fields
%       .clock_hz - timestamp counter rate [Hz] (4e6, i.e. 250 ns / tick)
%       .setup    - acquisition setup read from the file header:
%           .product    - product string (Msg 41), e.g. 'EasyAE ... V1.00'
%           .test_start - start-of-test date/time string (Msg 99)
%           .label      - test label / first user comment (Msg 7)
%           .chid       - feature IDs stored in every hit, in file order (Msg 5)
%           .hit_fields - names of the decoded hit fields, in file order
%           .n_param    - parametric channels declared per hit (Msg 5)
%           .n_partial_power - partial-power segments per hit (Msg 42, sub-ID 109)
%       .hit      - struct of column vectors, one entry per hit (see below)
%       .nhits    - number of hits
%       .wf       - struct with one entry per waveform (column vectors):
%           .counter, .time_s, .channel, .nsamp (uint32)
%           .samples  - {Nw x 1} cell of int16 raw ADC counts ([] if skipped)
%
%   HIT FIELDS  (CHID = feature ID in the file; scaling from the AEwin
%   "AE Features Scaling" notes). Only features the file records are present,
%   except the first five core fields, which are always there (NaN when the
%   file does not record them).
%     always   : counter, time_s, channel
%     CHID  1  : risetime_us        rise time [us]
%     CHID  2  : counts_to_peak     counts to peak
%     CHID  3  : counts             threshold-crossing counts
%     CHID  4  : energy_u           energy [a.u.]
%     CHID  5  : duration_us        duration [us]
%     CHID  6  : amplitude_db       amplitude [dB]       (CHID 27: x10 resolution)
%     CHID  7  : rms_v              RMS [V], 8-bit, = value/20  (obsolete)
%     CHID  8  : asl_db             average signal level [dB]   (CHID 28: x10)
%     CHID  9  : gain_db            gain
%     CHID 10  : threshold_db       threshold [dB]
%     CHID 11  : preamp_current     preamp current
%     CHID 12  : lost_hits          lost hits
%     CHID 13  : avg_freq_khz       average frequency (A-FRQ) [kHz]
%     CHID 17  : rms_v              RMS [V], 16-bit, = value/5000
%     CHID 18  : rev_freq_khz       reverberation frequency [kHz]
%     CHID 19  : init_freq_khz      initiation frequency [kHz]
%     CHID 20  : signal_strength_pvs signal strength [pVs], = value*3.05
%     CHID 21  : abs_energy_aj      absolute energy [aJ as shown by AEwin], = value*0.000931
%     CHID 22  : partial_power      [nhits x segments] partial powers (Msg 109 gives the segments)
%     CHID 23  : centroid_freq_khz  frequency centroid [kHz]
%     CHID 24  : peak_freq_khz      peak frequency [kHz]
%     CHID 27  : amplitude_db       amplitude [dB], 0.1 dB resolution (replaces CHID 6)
%     CHID 28  : asl_db             ASL [dB], 0.1 dB resolution (replaces CHID 8)
%
%   FILE LAYOUT (AEwin64 "Data File Definition", Appendix II)
%     Frame        : [len (uint16 LE)] [msgId (1)] [body (len-1 bytes)]
%     Msg 1  (hit) : time(6) ch(1) then the features listed in Msg 5,
%                    then parametric values (not decoded here)
%     Msg 5        : sub-message of Msg 42 (hardware setup) listing the CHIDs
%     Msg 173,1    : subId(1)=1 time(6) ch(1) pad(1) [N(2)] samples(int16 ...)
%                    The optional count word N is honoured only when it matches
%                    the body length exactly; otherwise all remaining bytes
%                    are samples (what AEwin writes in all tested files).
%     A waveform carries the same timestamp and channel as its hit, which is
%     what AE_listWaveforms uses to pair them.
%
%   NOTES
%     * Features are decoded in file order until the first ID this reader does
%       not know; a warning (AE:unknownCHID) lists the IDs that were skipped.
%     * Parametric values (analog inputs recorded with each hit) are not decoded.
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

p = inputParser;
addParameter(p, 'Waveforms', true);
parse(p, varargin{:});
wfOpt = p.Results.Waveforms;

CLOCK_HZ  = 4e6;
WF_HEADER = 9;    % subId + time6 + ch + pad, before the (optional N and) samples

% Known hit features: CHID -> {field name, bytes, class, scale}
% bytes = 0 means "one byte per partial-power segment" (CHID 22).
chidTable = containers.Map('KeyType', 'double', 'ValueType', 'any');
chidTable(1)  = {'risetime_us',         2, 'uint16', 1};
chidTable(2)  = {'counts_to_peak',      2, 'uint16', 1};
chidTable(3)  = {'counts',              2, 'uint16', 1};
chidTable(4)  = {'energy_u',            2, 'uint16', 1};
chidTable(5)  = {'duration_us',         4, 'uint32', 1};
chidTable(6)  = {'amplitude_db',        1, 'uint8',  1};
chidTable(7)  = {'rms_v',               1, 'uint8',  1/20};
chidTable(8)  = {'asl_db',              1, 'uint8',  1};
chidTable(9)  = {'gain_db',             1, 'uint8',  1};
chidTable(10) = {'threshold_db',        1, 'uint8',  1};
chidTable(11) = {'preamp_current',      1, 'uint8',  1};
chidTable(12) = {'lost_hits',           4, 'uint32', 1};
chidTable(13) = {'avg_freq_khz',        2, 'uint16', 1};
chidTable(17) = {'rms_v',               2, 'uint16', 1/5000};
chidTable(18) = {'rev_freq_khz',        2, 'uint16', 1};
chidTable(19) = {'init_freq_khz',       2, 'uint16', 1};
chidTable(20) = {'signal_strength_pvs', 4, 'uint32', 3.05};
chidTable(21) = {'abs_energy_aj',       4, 'single', 0.000931};
chidTable(22) = {'partial_power',       0, 'uint8',  1};
chidTable(23) = {'centroid_freq_khz',   2, 'uint16', 1};
chidTable(24) = {'peak_freq_khz',       2, 'uint16', 1};
chidTable(27) = {'amplitude_db',        2, 'uint16', 1/10};
chidTable(28) = {'asl_db',              2, 'uint16', 1/10};

fid = fopen(filename, 'rb');
assert(fid > 0, 'AE_readDTA: Cannot open file: %s', filename);
c = onCleanup(@() fclose(fid));
R = fread(fid, inf, 'uint8=>uint8');
L = numel(R);

% ---- Pass 1: index the frames (positions only, no copying) --------------
cap     = 4096;
hitPos  = zeros(cap, 1);  hitLen = zeros(cap, 1);  nh = 0;   % first body byte
wfPos   = zeros(cap, 1);  wfLen  = zeros(cap, 1);  nw = 0;
setupPos = struct('p41', 0, 'p42', 0, 'p99', 0, 'p7', 0);    % first occurrence

pos = 1;
while pos <= L - 3
    len = double(R(pos)) + 256 * double(R(pos+1));
    b0  = pos + 3;
    b1  = pos + 1 + len;
    if b1 > L, break; end
    id = R(pos+2);
    switch id
        case 1
            nh = nh + 1;
            if nh > numel(hitPos), hitPos(end*2) = 0; hitLen(end*2) = 0; end
            hitPos(nh) = b0;  hitLen(nh) = b1 - b0 + 1;
        case 173
            if b1 - b0 + 1 >= WF_HEADER && R(b0) == 1       % sub-ID 1 = waveform
                nw = nw + 1;
                if nw > numel(wfPos), wfPos(end*2) = 0; wfLen(end*2) = 0; end
                wfPos(nw) = b0;  wfLen(nw) = b1 - b0 + 1;
            end
        case 42, if setupPos.p42 == 0, setupPos.p42 = [b0 b1]; end
        case 41, if setupPos.p41 == 0, setupPos.p41 = [b0 b1]; end
        case 99, if setupPos.p99 == 0, setupPos.p99 = [b0 b1]; end
        case 7,  if setupPos.p7  == 0, setupPos.p7  = [b0 b1]; end
    end
    pos = pos + 2 + len;
end
hitPos = hitPos(1:nh);  hitLen = hitLen(1:nh);
wfPos  = wfPos(1:nw);   wfLen  = wfLen(1:nw);

% ---- Setup: product, date, label, hit layout ----------------------------
setup.product    = '';
setup.test_start = '';
setup.label      = '';
setup.chid       = [1 3 4 5 6];     % default when the file carries no Msg 5
setup.n_param    = 0;
nseg = 0;
if setupPos.p41(1) > 0, setup.product    = ascii_(R(setupPos.p41(1)+3 : setupPos.p41(2))); end
if setupPos.p99(1) > 0, setup.test_start = ascii_(R(setupPos.p99(1)   : setupPos.p99(2))); end
if setupPos.p7(1)  > 0, setup.label      = ascii_(R(setupPos.p7(1)    : setupPos.p7(2)));  end
if setupPos.p42(1) > 0
    [chid, npid, nseg] = parse_msg42_(R(setupPos.p42(1) : setupPos.p42(2)));
    if ~isempty(chid), setup.chid = chid;  setup.n_param = npid; end
end
setup.n_partial_power = nseg;

% Decode features in file order up to the first unknown CHID
layout = struct('name', {}, 'bytes', {}, 'cls', {}, 'scale', {}, 'off', {});
need = 7;                                     % time6 + channel
for k = 1:numel(setup.chid)
    cid = setup.chid(k);
    if ~isKey(chidTable, cid)
        warning('AE:unknownCHID', ['AE_readDTA: %s: feature ID(s) %s are not known to this reader; ' ...
            'features from ID %d onward are not decoded.'], filename, ...
            mat2str(setup.chid(k:end)), cid);
        break
    end
    e = chidTable(cid);
    nb = e{2};  if nb == 0, nb = nseg; end                 % partial power: 1 byte / segment
    if nb == 0, continue; end                              % no segments defined: nothing stored
    layout(end+1) = struct('name', e{1}, 'bytes', nb, 'cls', e{3}, 'scale', e{4}, 'off', need); %#ok<AGROW>
    need = need + nb;
end
setup.hit_fields = unique({layout.name}, 'stable');

% ---- Pass 2: decode hits in bulk ----------------------------------------
tick = 256 .^ (0:5).';
okHit  = hitLen >= need;
if nh > 0 && ~any(okHit)
    warning('AE:hitLayout', ['AE_readDTA: %s: hits are shorter (%d bytes) than the layout in the ' ...
        'file setup needs (%d bytes); no hits decoded.'], filename, max(hitLen), need);
end
hitPos = hitPos(okHit);
nh = numel(hitPos);

hit = struct();
if nh > 0
    G  = reshape(R(hitPos + (0:need-1)), nh, need);   % nh x need byte matrix
                                              % (reshape: a single hit would index as a column)
    ct = double(G(:, 1:6)) * tick;
    hit.counter = ct;
    hit.time_s  = ct / CLOCK_HZ;
    hit.channel = double(G(:, 7));
    for k = 1:numel(layout)
        e   = layout(k);
        raw = G(:, e.off + 1 : e.off + e.bytes);
        if strcmp(e.cls, 'uint8')
            v = raw;                                  % 1 byte (column) or segments (matrix)
        else
            v = typecast(reshape(raw.', [], 1), e.cls);
        end
        if e.scale ~= 1, v = double(v) * e.scale; end
        hit.(e.name) = v;
    end
    clear G
else
    hit.counter = zeros(0, 1);  hit.time_s = zeros(0, 1);  hit.channel = zeros(0, 1);
    for k = 1:numel(layout)
        hit.(layout(k).name) = zeros(0, 1);
    end
end
% Core fields downstream code relies on are always present (NaN if not recorded)
for name = {'risetime_us', 'counts', 'energy_u', 'duration_us', 'amplitude_db'}
    if ~isfield(hit, name{1}), hit.(name{1}) = nan(nh, 1); end
end

% ---- Decode waveforms ---------------------------------------------------
if islogical(wfOpt) && isscalar(wfOpt)
    doIdx = find(repmat(wfOpt, nw, 1));
else
    doIdx = unique(double(wfOpt(:)));
    doIdx = doIdx(doIdx >= 1 & doIdx <= nw);
end

wf.counter = zeros(nw, 1);
wf.channel = zeros(nw, 1);
wf.nsamp   = zeros(nw, 1, 'uint32');
wf.samples = cell(nw, 1);
for k = 1:nw
    p = wfPos(k);
    wf.counter(k) = double(R(p+1:p+6)).' * tick;
    wf.channel(k) = double(R(p+7));
    [~, ns] = sample_range_(R, p, wfLen(k), WF_HEADER);
    wf.nsamp(k) = ns;
end
for k = doIdx.'
    p = wfPos(k);
    [s0, ns] = sample_range_(R, p, wfLen(k), WF_HEADER);
    wf.samples{k} = typecast(R(p + s0 : p + s0 + 2*ns - 1), 'int16');
end
wf.time_s = wf.counter / CLOCK_HZ;

D.clock_hz = CLOCK_HZ;
D.setup    = setup;
D.hit      = hit;
D.nhits    = nh;
D.wf       = wf;
end

% =========================================================================
function [s0, ns] = sample_range_(R, p, bodyLen, hdr)
% Offset of the first sample relative to p (the first body byte, so the first
% sample is R(p + s0)) and the number of samples. The optional N word is used
% only when it accounts for the body length exactly; a first sample that merely
% looks like a small count (e.g. 1) must not be mistaken for it, so anything
% else is read as a plain stream of samples.
    s0 = hdr;
    ns = floor((bodyLen - hdr) / 2);
    if bodyLen >= hdr + 2
        n = double(R(p+hdr)) + 256 * double(R(p+hdr+1));       % body bytes 10-11
        if n > 0 && hdr + 2 + 2*n == bodyLen
            s0 = hdr + 2;  ns = n;
        end
    end
end

function [chid, npid, nseg] = parse_msg42_(B)
% Read the hit layout from a Msg-42 body.
%   Msg 42 body: [idHi (1)] [MVERN (2)] then sub-messages [LSUB (2)] [SUBID (1)] [body]
%   sub-ID   5 : [#CHID] [CHID ...] [#PID]                 (event data set definition)
%   sub-ID 109 : [segment type (1)] [#segments (2)] ...    (partial power setup)
    chid = [];  npid = 0;  nseg = 0;
    q = 4;
    while q + 2 <= numel(B)
        ls = double(B(q)) + 256 * double(B(q+1));
        if ls < 1 || q + 1 + ls > numel(B), break; end
        switch B(q+2)
            case 5
                n = double(B(q+3));
                if ls >= 2 && n > 0 && q + 3 + n <= numel(B)
                    chid = double(B(q+4 : q+3+n)).';
                    if q + 4 + n <= q + 1 + ls, npid = double(B(q+4+n)); end
                end
            case 109
                if ls >= 4, nseg = double(B(q+4)) + 256 * double(B(q+5)); end
        end
        q = q + 2 + ls;
    end
end

function s = ascii_(b)
% Printable-ASCII text of a byte vector (control characters become spaces).
    s = strtrim(regexprep(char(b(:).'), '[^\x20-\x7E]+', ' '));
end
