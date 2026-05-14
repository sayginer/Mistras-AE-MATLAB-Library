function [data, t, header] = openWFS(fname)
% openWFS  Read a Physical Acoustics / Mistras .WFS waveform streaming file.
%
%   [data, t, header] = openWFS(fname)
%   [data, t, header] = openWFS()         % opens a file-chooser dialog
%
%   Wrapper that calls ReadWFSHeader and ReadWFSDataTrunk, handles unit
%   conversions, and returns a clean data matrix with a proper time vector.
%
%   INPUT
%     fname  : path to the .wfs file (string, optional).
%              If omitted or empty, a file-chooser dialog is shown.
%
%   OUTPUTS
%     data   : [nChannels × nSamples] numeric array of waveform amplitudes [mV]
%     t      : [1 × nSamples] time vector in seconds
%     header : struct with acquisition metadata:
%                .NumChannels    - number of recorded channels
%                .SampleRate_kHz - per-channel sample rates [kHz] (vector)
%                .SampleRate_Hz  - per-channel sample rates [Hz]  (vector)
%                .Pretrigger     - pretrigger samples per channel (vector)
%                .MaxVoltage     - full-scale voltage per channel [V] (vector)
%                .HeaderLength   - byte offset where data section begins
%                .Timestamp      - acquisition start timestamp (string)
%                .Version        - AEwin software version string
%                .ChannelNumbers - hardware channel indices
%                .DataLength     - total samples per channel in data
%
%   VOLTAGE SCALING
%     Raw ADC counts (int16, ±32767) are scaled to millivolts using:
%         mV_per_count = 1000 × MaxVoltage / 32767
%     where MaxVoltage is read from the file header and may be attenuated by
%     gain settings parsed in ReadWFSHeader (fcoef).
%
%   EXAMPLE
%     [data, t, h] = openWFS('ExampleWFSdata.wfs');
%     figure;
%     plot(t, data(1, :));
%     xlabel('Time (s)'); ylabel('Amplitude (mV)');
%     title(sprintf('Ch 1 — %s', h.Timestamp));
%
%   DEPENDENCIES
%     ReadWFSHeader.m, ReadWFSDataTrunk.m
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

% ---- Resolve file path --------------------------------------------------
if nargin < 1 || isempty(fname)
    [fname, pathname] = uigetfile('*.wfs', 'Select a WFS file');
    if isequal(fname, 0)
        data   = [];
        t      = [];
        header = struct();
        return;
    end
else
    [pathname, name, ext] = fileparts(fname);
    if isempty(pathname), pathname = pwd; end
    if isempty(ext),      ext = '.wfs';  end
    fname = [name ext];
end

% Ensure pathname ends with a file separator
if ~isempty(pathname) && pathname(end) ~= filesep
    pathname = [pathname filesep];
end

% ---- Parse file header --------------------------------------------------
[Number_of_channels, sample_rate, Pretrigger, Max_voltage, Header_length, ...
    stamp, SVersion, ChannelNumbers] = ReadWFSHeader(pathname, fname);

% Sample rate is stored in kHz; convert to Hz
sample_rate_Hz = sample_rate * 1e3;
if numel(sample_rate_Hz) > 1
    fs = sample_rate_Hz(1);   % all channels share the same clock; use ch1
else
    fs = sample_rate_Hz;
end

% ---- Read waveform data trunk -------------------------------------------
% Voltage scale: mV per raw ADC count (applied per channel inside the trunk reader)
voltage_scale = 1000 * Max_voltage / 32767;   % [mV / count], one per channel

[data_len, ~, wfsdatas] = ReadWFSDataTrunk(fname, pathname, Header_length, voltage_scale);

data = wfsdatas;   % [nChannels × nSamples], units: mV

% ---- Build time vector --------------------------------------------------
if nargout >= 2
    t = (0 : data_len - 1) / fs;   % [1 × nSamples], units: seconds
end

% ---- Assemble header struct ---------------------------------------------
if nargout >= 3
    header.NumChannels    = Number_of_channels;
    header.SampleRate_kHz = sample_rate;
    header.SampleRate_Hz  = sample_rate_Hz;
    header.Pretrigger     = Pretrigger;
    header.MaxVoltage     = Max_voltage;
    header.HeaderLength   = Header_length;
    header.Timestamp      = stamp;
    header.Version        = SVersion;
    header.ChannelNumbers = ChannelNumbers;
    header.DataLength     = data_len;
end

end
