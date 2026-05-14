function [data_length, numb_of_channels, wfsdatas] = ...
         ReadWFSDataTrunk(filename, pathname, Header_length, voltage_scale)
% ReadWFSDataTrunk  Read the waveform data trunk of a .WFS file.
%
%   [data_length, numb_of_channels, wfsdatas] = ...
%       ReadWFSDataTrunk(filename, pathname, Header_length, voltage_scale)
%
%   Reads all waveform streaming data from the data section (trunk) of a
%   Physical Acoustics / Mistras AEwin .WFS file, assembles per-channel
%   sample arrays, corrects for FIFO read offsets, and applies voltage scaling.
%
%   INPUTS
%     filename      : filename including extension (string)
%     pathname      : directory path ending with filesep (string)
%     Header_length : byte offset returned by ReadWFSHeader (integer)
%                     — the file pointer is seeked here before reading
%     voltage_scale : [mV / ADC count] per channel (vector, 1 × nCh)
%                     Typically:  1000 * Max_voltage / 32767
%
%   OUTPUTS
%     data_length      : number of samples per channel in wfsdatas (integer)
%     numb_of_channels : number of channels found in the trunk (integer)
%     wfsdatas         : [numb_of_channels × data_length] array in mV
%
%   FILE FORMAT (trunk)
%   The trunk begins with a "sync" message that describes channel count and
%   per-channel trigger times and FIFO offsets, followed by a sequence of
%   data chunk messages (ID 174, sub-ID 1).  Each chunk carries nSamples
%   int16 ADC values for one channel.  Chunk message length is either 2076
%   (nSamples = 1024) or 8220 (nSamples = 4096).
%
%   FIFO OFFSET CORRECTION
%   The AEwin hardware buffers samples in a FIFO.  The distance between the
%   FIFO write pointer at trigger time (sampleStart) and the FIFO read
%   pointer (fifoRead) gives a per-channel sample offset.  The longest
%   offset across channels is removed so all channels share the same
%   time origin.
%
%   NOTES
%     • This function is normally called by openWFS, not directly.
%     • Returns immediately if filename == 0 (dialog-cancelled guard).
%
%   Original authors: Physical Acoustics Corporation
%   Modified        : Jason Dong, January 31, 2016
%   Extended docs   : Osman Sayginer — Temple University — Mechatronics Lab
%   Web             : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

if filename == 0
    return
end

fid = fopen([pathname filename], 'r');
fseek(fid, Header_length, -1);   % jump past the header to the data trunk

% =========================================================================
% SYNC MESSAGE — channel list, trigger times, FIFO start pointers
% =========================================================================
msgLength        = fread(fid, 1, 'short');   % trunk header message length
mid              = fread(fid, 1, 'uchar');   % message ID  = 174
sid              = fread(fid, 1, 'uchar');   % sub-ID      = 174
mver             = fread(fid, 1, 'short');   % message version
numb_of_channels = fread(fid, 1, 'short');  % number of channels in this file

% Per-channel sync data
channelList  = zeros(1, numb_of_channels);
trigTime_us  = zeros(1, numb_of_channels);
sampleStart  = zeros(1, numb_of_channels, 'int64');

for k = 1 : numb_of_channels
    channelList(k)  = fread(fid, 1, 'uint8');
    trigTime0_1     = fread(fid, 1, 'ulong');   % lower 32 bits of trigger time
    trigTime2       = fread(fid, 1, 'ushort');  % upper 16 bits
    % Reconstruct 48-bit trigger time in microseconds (4 MHz clock → ÷4)
    trigTime_us(k)  = ((4294967296.0 * trigTime2) + trigTime0_1) / 4;
    sampleStart(k)  = fread(fid, 1, 'int64');   % FIFO write pointer at trigger
end

data_start = ftell(fid);   % remember position for the second pass below

% =========================================================================
% FIRST DATA CHUNK — determine nSamples and per-channel FIFO offsets
% =========================================================================
msgLength = fread(fid, 1, 'short');
nSamples  = (msgLength - 28) / 2;   % int16 per sample; 28 bytes of chunk header

waveformIndex(1:32) = 0;   % running sample index per channel (max 32 ch)
nChunks             = 0;

% Read FIFO state from the first chunk of each channel
offset = zeros(1, numb_of_channels);
for k = 1 : numb_of_channels
    mid        = fread(fid, 1, 'uchar');   % sub-message ID = 174
    sid        = fread(fid, 1, 'uchar');   % sub-ID         = 1
    mver       = fread(fid, 1, 'short');
    sync       = fread(fid, 1, 'ulong');
    chanum     = fread(fid, 1, 'ulong');   % channel number (0-based)
    fifoWriter = fread(fid, 1, 'int64');   % FIFO write pointer
    fifoReadm  = fread(fid, 1, 'ulong');   % FIFO read pointer (high 32 bits)
    fifoReadl  = fread(fid, 1, 'ulong');   % FIFO read pointer (low  32 bits)
    fifoRead   = (fifoReadm * 4294967296.0) + fifoReadl;

    % Sample offset = distance from FIFO read to trigger-time write pointer
    % (×2 because fifoRead is in bytes, sampleStart is in samples)
    offset(k)  = double(sampleStart(k)) - (2 * fifoRead);

    fread(fid, nSamples, 'short');   % skip sample data (handled in second pass)
    msgLength = fread(fid, 1, 'short');
end

% =========================================================================
% SECOND PASS — assemble all sample chunks into per-channel arrays
% =========================================================================
fseek(fid, data_start, -1);
msgLength = fread(fid, 1, 'short');

while feof(fid) == 0
    if (msgLength ~= 2076) && (msgLength ~= 8220)
        % Not a data chunk (unknown or padding message) — skip it
        fseek(fid, msgLength, 0);
    else
        % Data chunk: read header fields, then the sample block
        fread(fid,  8, 'uchar');            % 8-byte sub-header (ID, sub-ID, version, sync)
        chanNum = fread(fid, 1, 'ulong');   % 0-based channel index
        fread(fid, 16, 'uchar');            % remaining header bytes
        chunk   = fread(fid, nSamples, 'short');

        % Append to the running sample buffer for this channel
        idxStart = waveformIndex(chanNum) + 1;
        idxEnd   = waveformIndex(chanNum) + nSamples;
        datas(chanNum, idxStart:idxEnd) = chunk(1:nSamples);  %#ok<AGROW>
        waveformIndex(chanNum) = idxEnd;
        nChunks = nChunks + 1;
    end

    msgLength = fread(fid, 1, 'short');
end

nChunks = nChunks / numb_of_channels;   % chunks per channel
fclose(fid);

% =========================================================================
% FIFO OFFSET CORRECTION — align all channels to the same time origin
% =========================================================================
% The maximum FIFO offset defines the common start; shorter-offset channels
% are shifted forward by their relative offset before cropping.
amax = max(offset);

data_length = nChunks * nSamples - amax;

for k = 1 : numb_of_channels
    a = offset(k) + 1;
    b = offset(k) + data_length;
    wfsdatas(k, :) = datas(k, a:b) * voltage_scale(k);  %#ok<AGROW>
end

clear datas;   % free raw buffer
