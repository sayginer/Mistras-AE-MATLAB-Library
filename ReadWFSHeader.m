function [Number_of_channels, Sample_rate, Pretrigger, Max_voltage, ...
          Header_length, Timestamp, SVersion, ChannelNumbers] = ...
          ReadWFSHeader(pathname, filename)
% ReadWFSHeader  Parse the binary file header of a .WFS waveform streaming file.
%
%   [nCh, Fs_kHz, pretrig, Vmax, hdrLen, stamp, ver, chNums] = ...
%       ReadWFSHeader(pathname, filename)
%
%   Reads the structured header tables written by Physical Acoustics /
%   Mistras AEwin at the beginning of every .WFS file. The header encodes
%   instrument model, software version, channel list, hardware setup
%   (sample rate, trigger mode, full-scale voltage), filter settings,
%   and the acquisition timestamp.
%
%   The parser handles two hardware/firmware branches:
%     • Express / PCI boards running AEwin < 5.0  (Tables 3–5 layout A)
%     • All other boards / AEwin ≥ 5.0           (Tables 3–5 layout B,
%       includes preamp gain, analog/digital filter records)
%
%   INPUTS
%     pathname : directory containing the file, ending with filesep (string)
%     filename : filename including extension, e.g. 'data.wfs' (string)
%
%   OUTPUTS
%     Number_of_channels : total number of acquired channels (integer)
%     Sample_rate        : sample rate per channel [kHz] (vector, Nch × 1)
%     Pretrigger         : pretrigger length per channel [samples] (vector)
%     Max_voltage        : full-scale voltage per channel [V] (vector),
%                          already divided by gain factors (fcoef)
%     Header_length      : byte offset at which the data section starts
%     Timestamp          : acquisition start time string (e.g. 'Jan 01 2024 ...')
%     SVersion           : AEwin software version string
%     ChannelNumbers     : hardware channel indices (vector)
%
%   NOTES
%     • This function is called by openWFS and is not normally invoked directly.
%     • The voltage scale returned here feeds ReadWFSDataTrunk via openWFS.
%     • 'findstr' is used for legacy compatibility with older MATLAB versions;
%       in R2016b+ it is replaced by strfind.
%
%   DEPENDENCIES  (none — fully self-contained)
%
%   Original authors: Physical Acoustics Corporation
%   Modified        : Jason Dong, January 31, 2016
%   Extended docs   : Osman Sayginer — Temple University — Mechatronics Lab
%   Web             : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

fid = fopen([pathname filename], 'r');

% =========================================================================
% TABLE 1 — Product identification block
% =========================================================================
Header.Size_table1 = fread(fid, 1, 'short');
Header.PRODUCTID   = fread(fid, 1, 'uint8');
Header.space       = fread(fid, 1, 'int8');
Header.block1      = fread(fid, 1, 'short');
Header.SModel      = fread(fid, Header.Size_table1 - 4, 'char');

% Extract 3-char board model abbreviation (e.g. 'Exp', 'PCI', 'USB')
amodel = char(Header.SModel(1:3))';

% Extract software version number (digits around the first '.')
Header.SVer = str2num(char(Header.SModel( ...
    findstr(char(Header.SModel'), '.') - 1 : ...
    findstr(char(Header.SModel'), '.') + 2 ))');  %#ok<ST2NM,FSTR>

fcoef = 1.0;   % voltage gain correction factor (modified below if needed)

% =========================================================================
% TABLE 2 — Define group (active channel list)
% =========================================================================
Header.Size_table2         = fread(fid, 1, 'short');
Header.ID174               = fread(fid, 1, 'uint8');   % always 174
Header.SubID106            = fread(fid, 1, 'uint8');   % always 106
Header.Group_number        = fread(fid, 1, 'int8');    % always 1
Header.Number_of_channels  = fread(fid, 1, 'int8');

for k = 1 : Header.Number_of_channels
    Header.channelList(k) = fread(fid, 1, 'int8');
end

% =========================================================================
% TABLE 3 — Hardware setup (per channel: ADC bits, sample rate, trigger,
%            pretrigger, full-scale voltage)
% =========================================================================
for i = 1 : Header.Number_of_channels
    Header.Size_table3(i)    = fread(fid, 1, 'short');
    Header.ID212_2(i)        = fread(fid, 1, 'uint8');    % 212
    Header.S488ID(i)         = fread(fid, 1, 'uint8');
    Header.Version(i)        = fread(fid, 1, 'short');
    Header.Adbits(i)         = fread(fid, 1, 'int8');     % ADC resolution
    Header.Channel_number(i) = fread(fid, 1, 'uint8');
    Header.Hardware_size(i)  = fread(fid, 1, 'ulong');    % data block size
    Header.Reserved(i)       = fread(fid, 1, 'short');
    Header.sample_rate(i)    = fread(fid, 1, 'short');    % [kHz]
    Header.Trigger_mode(i)   = fread(fid, 1, 'short');
    Header.Trigger_type(i)   = fread(fid, 1, 'short');
    Header.pretrigger(i)     = fread(fid, 1, 'int32');    % [samples]
    Header.maxvoltage(i)     = fread(fid, 1, 'short');    % [V] before gain
    Header.Short(i)          = fread(fid, 1, 'short');
end

% =========================================================================
% TABLES 4 & 5 — Gain / filter tables (layout depends on board/version)
% =========================================================================
if (strcmp(amodel, 'Exp') || strcmp(amodel, 'PCI')) && Header.SVer < 5.0

    % ---- Layout A: Express/PCI, AEwin < 5.0 ----------------------------

    % Table 4 — preamplifier gain (pre-gain per channel)
    Header.Size_table4              = fread(fid, 1, 'short');
    Header.Table4_ID174             = fread(fid, 1, 'uint8');
    Header.Table4_subID20           = fread(fid, 1, 'uint8');
    Header.Table4_message_version   = fread(fid, 1, 'short');
    Header.Table4_Active_Channels   = fread(fid, 1, 'short');
    for i = 1 : Header.Number_of_channels
        Header.Table4_Channel_Number(i) = fread(fid, 1, 'int8');
        Header.Table4_Channel_PreGain(i) = fread(fid, 1, 'int8');
    end

    % Table 5 — additional header (AEwin ≥ 1.53 only)
    if Header.SVer > 1.53
        Header.Size_table5            = fread(fid, 1, 'short');
        Header.Table5_ID174           = fread(fid, 1, 'uint8');
        Header.Table5_subID23         = fread(fid, 1, 'uint8');
        Header.Table5_message_version = fread(fid, 1, 'short');
        Header.Table5_Active_Channels = fread(fid, 1, 'short');
        for i = 1 : Header.Number_of_channels
            Header.Table5_ch(i)   = fread(fid, 1, 'int8');
            Header.Table5_gain(i) = fread(fid, 1, 'int8');
        end
    end

    % Per-channel correction shorts
    for i = 1 : Header.Number_of_channels
        Header.Table5_short(i)    = fread(fid, 1, 'short');
        Header.Table5_uint8s(i)   = fread(fid, 1, 'uint8');
        Header.Table5_int8s(i, :) = fread(fid, 4, 'int8');
    end

else

    % ---- Layout B: USB/DiSP/AEwin ≥ 5.0 --------------------------------

    % Table 4
    Header.Size_table4              = fread(fid, 1, 'short');
    Header.Table4_ID174             = fread(fid, 1, 'uint8');
    Header.Table4_subID20           = fread(fid, 1, 'uint8');
    Header.Table4_message_version   = fread(fid, 1, 'short');
    Header.Table4_Active_Channels   = fread(fid, 1, 'short');
    for i = 1 : Header.Number_of_channels
        Header.Table4_Channel_Number(i)  = fread(fid, 1, 'int8');
        Header.Table4_Channel_PreGain(i) = fread(fid, 1, 'int8');
    end

    % Table 5
    Header.Size_table5            = fread(fid, 1, 'short');
    Header.Table5_ID174           = fread(fid, 1, 'uint8');
    Header.Table5_subID23         = fread(fid, 1, 'uint8');
    Header.Table5_message_version = fread(fid, 1, 'short');
    Header.Table5_Active_Channels = fread(fid, 1, 'short');
    for i = 1 : Header.Number_of_channels
        Header.Table5_ch(i)   = fread(fid, 1, 'int8');
        Header.Table5_gain(i) = fread(fid, 1, 'int8');
    end

    % Preamp message (contains hardware gain flags)
    Header.Preamp_Message = fread(fid, 1, 'short');
    Header.Preamp_ID174   = fread(fid, 1, 'uint8');
    atemp = fread(fid, Header.Preamp_Message - 1, 'uint8');

    % Byte 9 of the preamp block encodes a ×5 / ÷5 gain switch
    if atemp(9) == 5, fcoef = 0.2; end

    % Table5 gain codes: 6 dB → ÷2,  12 dB → ÷4
    if     Header.Table5_gain(1) == 6,  fcoef = fcoef / 2;
    elseif Header.Table5_gain(1) == 12, fcoef = fcoef / 4;
    end

    % Analog filter records (one per channel, ID 137)
    for i = 1 : Header.Number_of_channels
        Header.AFilter_Message(i)    = fread(fid, 1, 'short');
        Header.AFilter_IDs(i)        = fread(fid, 1, 'uint8');
        Header.AFilter_Bytes(i, :)   = fread(fid, 4, 'int8');
    end

    % Digital filter records (one per channel, ID 146)
    for i = 1 : Header.Number_of_channels
        Header.DFilter_Message(i)    = fread(fid, 1, 'short');
        Header.DFilter_IDs(i)        = fread(fid, 1, 'uint8');
        Header.DFilter_Bytes(i, :)   = fread(fid, 9, 'int8');
    end

end  % end hardware branch

% =========================================================================
% TABLE 6 — Date / time stamp
% =========================================================================
Header.Size_table6          = fread(fid, 1, 'short');
Header.Table6_Time_Data_ID  = fread(fid, 1, 'uint8');   % ID 99
Header.Timestamp            = char(fread(fid, Header.Size_table6 - 1, 'char'));

% =========================================================================
% TABLE 7 — Separator / marker (ID 11, length 0)
% =========================================================================
Header.Size_table7  = fread(fid, 1, 'short');
Header.Table7_uint8 = fread(fid, 1, 'uint8');

% =========================================================================
% TABLE 8 — Resume / start-of-data marker (ID 128)
% =========================================================================
Header.Size_table8  = fread(fid, 1, 'short');
Header.Table8_uint8 = fread(fid, 1, 'uint8');   % ID 128
Header.Table8_short = fread(fid, 3, 'short');   % 6 reserved bytes

% ---- Record byte offset where the data trunk begins --------------------
Header.Length_of_header = ftell(fid);
fclose(fid);

% =========================================================================
% Output assignments
% =========================================================================
Number_of_channels = Header.Number_of_channels;
Sample_rate        = Header.sample_rate;           % [kHz], per channel
Pretrigger         = Header.pretrigger;            % [samples], per channel
Max_voltage        = Header.maxvoltage * fcoef;    % [V], gain-corrected
Header_length      = Header.Length_of_header;      % [bytes]
Timestamp          = char(Header.Timestamp)';
SVersion           = char(Header.SModel)';
ChannelNumbers     = Header.channelList;
