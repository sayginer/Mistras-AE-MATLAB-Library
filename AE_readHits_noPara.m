function hits = AE_readHits_noPara(filename)
% AE_readHits_noPara  Parse AE hit records (Msg ID 1) from an AEwin .DTA file.
%
%   hits = AE_readHits_noPara(filename)
%
%   Reads all Msg-1 ("hit") records from a Physical Acoustics / Mistras AEwin
%   .DTA binary file. This variant handles files that carry NO per-hit
%   parametric channels (i.e. the hit body is exactly 18 bytes of core fields,
%   optionally followed by 1-3 pad bytes that are silently skipped).
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
%
%   NOTES
%     * The 6-byte timestamp is a 48-bit little-endian counter ticked at 4 MHz
%       (250 ns / tick). Convert to seconds: sum(time6 .* 256.^(0:5)) / 4e6.
%     * Bodies shorter than 18 bytes are skipped with a warning suppressed;
%       any bytes beyond the 18 core bytes are ignored (pad/reserved).
%     * This function is called internally by AE_listWaveforms but can also be
%       used standalone to extract hit-feature tables without waveform data.
%
%   EXAMPLE
%     hits = AE_readHits_noPara('experiment_01.DTA');
%     fprintf('Found %d hits\n', numel(hits));
%     amp  = [hits.amplitude_db];
%     hist(amp, 20);
%
%   DEPENDENCIES  (none — fully self-contained)
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

% ---- Read entire file into memory as raw bytes -------------------------
raw = readall_(filename);
L   = numel(raw);
pos = 1;

hits = struct([]);   % grow incrementally
n    = 0;

% ---- Walk the message stream -------------------------------------------
% Each message frame layout:
%   [len_lo | len_hi | msgId | body(len-1 bytes)]
% where 'len' is a little-endian uint16 = total bytes AFTER the 2-byte
% length field itself (i.e. msgId byte + body bytes).
% Frame total size = 2 (length word) + len bytes.

while pos <= L - 3

    len      = uint16(raw(pos)) + bitshift(uint16(raw(pos+1)), 8);
    msgIdPos = pos + 2;
    if msgIdPos > L, break; end

    msgId    = raw(msgIdPos);
    bodyStart = msgIdPos + 1;
    bodyEnd   = pos + 1 + double(len);   % inclusive last byte of frame
    if bodyEnd > L, break; end

    body = raw(bodyStart:bodyEnd);       % bytes AFTER the msgId byte

    % ---- Process Msg 1 (Hit Data) ------------------------------------
    if msgId == 1

        if numel(body) < 18
            % Malformed / truncated hit — skip silently
            pos = bodyEnd + 1;
            continue
        end

        p = 1;

        % 6-byte little-endian 48-bit timestamp counter
        t6       = double(body(p:p+5)).';   p = p + 6;

        % Channel number (1-based)
        ch       = double(body(p));          p = p + 1;

        % Feature fields (all little-endian)
        rise     = typecast(uint8(body(p:p+1)), 'uint16');  p = p + 2;
        counts   = typecast(uint8(body(p:p+1)), 'uint16');  p = p + 2;
        energy_u = typecast(uint8(body(p:p+1)), 'uint16');  p = p + 2;
        duration = typecast(uint8(body(p:p+3)), 'uint32');  p = p + 4;
        amp_db   = body(p);                  % 1 byte; remaining bytes ignored

        % Store
        n = n + 1;
        hits(n).time6        = t6;           %#ok<AGROW>
        hits(n).channel      = ch;
        hits(n).risetime_us  = rise;
        hits(n).counts       = counts;
        hits(n).energy_u     = energy_u;
        hits(n).duration_us  = duration;
        hits(n).amplitude_db = amp_db;

    end

    pos = bodyEnd + 1;   % advance to next frame
end
end

% =========================================================================
function raw = readall_(filename)
% Read entire file as a uint8 byte vector.
    fid = fopen(filename, 'rb');
    assert(fid > 0, 'AE_readHits_noPara: Cannot open file: %s', filename);
    c   = onCleanup(@() fclose(fid));
    raw = fread(fid, inf, 'uint8=>uint8');
end
