function hits = AE_readHits_noPara(filename)
% AE_readHits_noPara  Parse AE hit records (Msg ID 1) from an AEwin .DTA file.
%
%   hits = AE_readHits_noPara(filename)
%
%   Reads all Msg-1 ("hit") records from a Physical Acoustics / Mistras AEwin
%   .DTA binary file and returns them as a struct array. The hit layout is
%   taken from the file's own event definition (Msg 5), so files with extra
%   characteristics are handled too.
%
%   INPUT
%     filename  : full or relative path to the .DTA file (string)
%
%   OUTPUT
%     hits : 1-x-N struct array, one element per hit, with fields:
%       .time6        - 6-byte little-endian timestamp counter (double row vec)
%       .channel      - acquisition channel number (double)
%       .risetime_us  - rise time in microseconds (uint16)
%       .counts       - threshold crossing count (uint16)
%       .energy_u     - energy in arbitrary units (uint16)
%       .duration_us  - hit duration in microseconds (uint32)
%       .amplitude_db - peak amplitude in dB AE (uint8)
%       .time_s       - hit time in seconds since the counter started (double)
%       plus every further feature the file records, with physical units
%       (rms_v, asl_db, avg_freq_khz, abs_energy_aj, ... see AE_readDTA).
%       The five core fields are NaN when the file does not record them.
%
%   NOTES
%     * The 6-byte timestamp is a 48-bit little-endian counter ticked at 4 MHz
%       (250 ns / tick); .time_s already holds counter / 4e6.
%     * A struct array with millions of elements is slow and memory-hungry.
%       For large files use AE_readDTA(file, 'Waveforms', false) and work with
%       the column vectors in D.hit instead (or AE_plotHits for a table).
%
%   EXAMPLE
%     hits = AE_readHits_noPara('experiment_01.DTA');
%     fprintf('Found %d hits\n', numel(hits));
%     amp  = [hits.amplitude_db];
%     histogram(amp, 20);
%
%   DEPENDENCIES
%     AE_readDTA.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

D = AE_readDTA(filename, 'Waveforms', false);
H = D.hit;
if D.nhits == 0
    hits = struct([]);
    return
end

% Row-wise 6-byte timestamp for backward compatibility
time6 = mod(floor(H.counter ./ (256 .^ (0:5))), 256);

fields = fieldnames(H);
fields = fields(~ismember(fields, {'counter', 'time6'}));
args   = {'time6', num2cell(time6, 2)};
for k = 1:numel(fields)
    v = H.(fields{k});
    if size(v, 2) > 1, c = num2cell(v, 2); else, c = num2cell(v); end   % matrix fields: one row per hit
    args = [args, {fields{k}, c}];   %#ok<AGROW>
end
hits = struct(args{:}).';
end
