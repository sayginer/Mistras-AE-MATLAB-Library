classdef TestAELibrary < matlab.unittest.TestCase
% TestAELibrary  Regression tests for the Mistras AE MATLAB library.
%
%   Run from the library folder:
%       results = runtests('TestAELibrary'); table(results)
%
%   Uses ExampleDTAfile.DTA and ExampleWFSdata.wfs, plus small synthetic
%   .DTA files built on the fly for pairing and error-handling cases.

    properties
        Dir
        DTA = 'ExampleDTAfile.DTA'
        WFS = 'ExampleWFSdata.wfs'
    end

    methods (TestClassSetup)
        function addPath(tc)
            tc.Dir = fileparts(mfilename('fullpath'));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(tc.Dir));
            tc.DTA = fullfile(tc.Dir, tc.DTA);
            tc.WFS = fullfile(tc.Dir, tc.WFS);
        end
    end

    methods (Test)
        function hitsMatchExample(tc)
            h = AE_readHits_noPara(tc.DTA);
            tc.verifyEqual(numel(h), 4);
            tc.verifyEqual([h.channel], [1 2 1 2]);
            tc.verifyEqual([h.amplitude_db], uint8([92 90 93 91]));
            tc.verifyEqual([h.counts], uint16([1371 687 1326 690]));
            tc.verifyEqual([h.duration_us], uint32([14441 11047 16011 12592]));
            tc.verifyEqual(h(1).time6, [21 169 96 0 0 0]);
            tc.verifyEqual(h(1).time_s, 6334741 / 4e6, 'AbsTol', 1e-12);
        end

        function catalogPairsByTimestamp(tc)
            W = AE_listWaveforms(tc.DTA);
            tc.verifyEqual(height(W), 4);
            tc.verifyEqual(W.hit_idx.', 1:4);
            tc.verifyEqual(W.channel.', [1 2 1 2]);
            tc.verifyEqual(W.nsamp.', uint32([1024 1024 1024 1024]));
            % 4 MHz clock: hit 3 arrives ~4.87 s after hit 1
            tc.verifyEqual(W.t_rel_sec(1), 0);
            tc.verifyEqual(W.t_rel_sec(3), (25797993 - 6334741) / 4e6, 'AbsTol', 1e-9);
        end

        function waveformDecoding(tc)
            [t, y, info] = AE_plotWaveformByIndex(tc.DTA, 1, 0);
            tc.verifySize(y, [1024 1]);
            tc.verifySize(t, [1024 1]);
            tc.verifyEqual(t(2) - t(1), 1, 'AbsTol', 1e-12);        % 1 MHz, µs axis
            tc.verifyEqual(max(abs(y)), 4112.01, 'AbsTol', 0.01);   % mV
            tc.verifyEqual(info.channel, 1);
            tc.verifyEqual(info.nsamp, uint32(1024));
            % unit / scale options
            [~, yV]  = AE_plotWaveformByIndex(tc.DTA, 1, 0, 'Units', 'V');
            [~, yH]  = AE_plotWaveformByIndex(tc.DTA, 1, 0, 'Scale', 0.5);
            tc.verifyEqual(yV * 1e3, y, 'AbsTol', 1e-9);
            tc.verifyEqual(yH, y * 0.5, 'AbsTol', 1e-9);
        end

        function preParsedStructGivesSameResult(tc)
            D = AE_readDTA(tc.DTA);
            [~, y1] = AE_plotWaveformByIndex(tc.DTA, 3, 0);
            [~, y2] = AE_plotWaveformByIndex(D,      3, 0);
            tc.verifyEqual(y1, y2);
        end

        function indexOutOfRangeErrors(tc)
            tc.verifyError(@() AE_plotWaveformByIndex(tc.DTA, 0, 0), '');
            tc.verifyError(@() AE_plotWaveformByIndex(tc.DTA, 5, 0), '');
        end

        function missingFileErrors(tc)
            tc.verifyError(@() AE_readDTA('does_not_exist.DTA'), '');
            tc.verifyError(@() openWFS('does_not_exist.wfs'), '');
        end

        function pairingIgnoresFileOrderAndFlagsOrphans(tc)
            % Real frames from the example, reordered: hit 2 is dropped and
            % the remaining hits are swapped, so ordinal pairing would fail.
            f = tc.frames();
            syn = [f.header; f.wf{1}; f.wf{2}; f.hit{2}; f.hit{1}; f.wf{3}];
            fn = [tempname '.DTA'];
            fid = fopen(fn, 'wb'); fwrite(fid, syn); fclose(fid);
            cleanup = onCleanup(@() delete(fn));

            W = AE_listWaveforms(fn);
            tc.verifyEqual(W.channel.', [1 2 1]);
            tc.verifyEqual(W.amplitude_db(1), 92);    % wf1 -> hit of ch 1 (92 dB)
            tc.verifyEqual(W.amplitude_db(2), 90);    % wf2 -> hit of ch 2 (90 dB)
            tc.verifyEqual(W.hit_idx(3), 0);          % wf3 has no hit
            tc.verifyTrue(isnan(W.amplitude_db(3)));
        end

        function exportRoundTrip(tc)
            mf = [tempname '.mat'];
            cleanup = onCleanup(@() delete(mf));
            evalc("AE_exportAllWaveforms(tc.DTA, mf, 'Scale', 0.5)");
            S = load(mf);
            tc.verifyEqual(height(S.W), 4);
            [~, y] = AE_plotWaveformByIndex(tc.DTA, 2, 0, 'Scale', 0.5);
            tc.verifyEqual(S.y_cell{2}, y);
        end

        function hitTableAndCumulativeSums(tc)
            H = AE_plotHits(tc.DTA, 'Plot', false);
            tc.verifyEqual(height(H), 4);
            tc.verifyTrue(issorted(H.time));
            tc.verifyEqual(H.time(1), 0);
            tc.verifyEqual(H.cum_counts(end), 1371 + 687 + 1326 + 690);
            tc.verifyEqual(H.cum_energy(end), 2153 + 1574 + 2068 + 1688);
            H1 = AE_plotHits(tc.DTA, 'Plot', false, 'Channels', 1);
            tc.verifyEqual(height(H1), 2);
            tc.verifyEqual(H1.cum_counts(end), 1371 + 1326);
            Hm = AE_plotHits(tc.DTA, 'Plot', false, 'TimeUnits', 'min');
            tc.verifyEqual(Hm.time(end), H.time(end) / 60, 'AbsTol', 1e-12);
            tc.verifyError(@() AE_plotHits(tc.DTA, 'Plot', false, 'Channels', 99), '');
            tc.verifyError(@() AE_plotHits(tc.DTA, 'TimeUnits', 'days'), '');
        end

        function hitPlotDrawsFourPanels(tc)
            [~, fig] = AE_plotHits(tc.DTA);
            cleanup = onCleanup(@() close(fig));
            tc.verifyEqual(numel(findobj(fig, 'Type', 'axes')), 4);
        end

        function spectrumOfKnownTone(tc)
            Fs = 1e6;  N = 1024;  f0 = 100 * Fs / N;           % exactly on bin 100
            t = (0:N-1).' / Fs;
            y = 3 * sin(2*pi*f0*t) + 5;                        % amplitude 3, DC offset 5
            [f, A, s] = AE_waveformSpectrum(y, Fs, 'Window', 'rect');
            tc.verifyEqual(f(end), Fs/2);
            tc.verifyEqual(s.peak_freq_Hz, f0, 'AbsTol', 1e-6);
            tc.verifyEqual(s.peak_amp, 3, 'AbsTol', 1e-9);
            tc.verifyEqual(A(1), 0, 'AbsTol', 1e-9);           % DC removed
            [~, ~, sh] = AE_waveformSpectrum(y, Fs);           % hann
            tc.verifyEqual(sh.peak_freq_Hz, f0, 'AbsTol', Fs/N);
            tc.verifyEqual(sh.peak_amp, 3, 'RelTol', 0.02);
            tc.verifyEqual(sh.centroid_freq_Hz, f0, 'AbsTol', 2 * Fs/N);
            % band limiting ignores the tone
            [~, ~, sb] = AE_waveformSpectrum(y, Fs, 'FreqRange', [200e3 400e3]);
            tc.verifyGreaterThan(sb.peak_freq_Hz, 200e3);
        end

        function spectrumOfRealWaveform(tc)
            [~, y, info] = AE_plotWaveformByIndex(tc.DTA, 1, 0);
            [f, A, s] = AE_waveformSpectrum(y, info.Fs, 'Plot', true);
            cleanup = onCleanup(@() close('all'));
            tc.verifySize(f, [513 1]);
            tc.verifyTrue(all(A >= 0));
            tc.verifyGreaterThan(s.peak_freq_Hz, 0);
            tc.verifyLessThanOrEqual(s.peak_freq_Hz, info.Fs / 2);
            tc.verifyError(@() AE_waveformSpectrum(y, -1), '');
            tc.verifyError(@() AE_waveformSpectrum(y, 1e6, 'NFFT', 16), '');
        end

        function wfsExample(tc)
            [d, t, h] = openWFS(tc.WFS);
            tc.verifyEqual(size(d, 1), 2);
            tc.verifyEqual(size(d, 2), numel(t));
            tc.verifyEqual(h.SampleRate_Hz(1), 1e6);
            tc.verifyTrue(all(isfinite(d(:))));
            tc.verifyEmpty(regexp([h.Timestamp h.Version], '[^\x20-\x7E]', 'once'));
        end
    end

    methods (Test)
        function setupIsParsed(tc)
            D = AE_readDTA(tc.DTA);
            tc.verifyEqual(D.setup.chid, [1 3 4 5 6]);
            tc.verifyEqual(D.setup.n_param, 1);
            tc.verifySubstring(D.setup.product, 'EasyAE');
            tc.verifySubstring(D.setup.test_start, '2025');
            tc.verifyEqual(D.nhits, 4);
        end

        function hitsOnlyAndSelectedWaveforms(tc)
            D0 = AE_readDTA(tc.DTA, 'Waveforms', false);
            tc.verifyTrue(all(cellfun(@isempty, D0.wf.samples)));
            tc.verifyEqual(D0.wf.nsamp.', uint32([1024 1024 1024 1024]));
            tc.verifyEqual(height(AE_listWaveforms(D0)), 4);
            tc.verifyError(@() AE_plotWaveformByIndex(D0, 1, 0), '');
            D2 = AE_readDTA(tc.DTA, 'Waveforms', [2 3]);
            tc.verifyEqual(cellfun(@isempty, D2.wf.samples).', [true false false true]);
            [~, y2] = AE_plotWaveformByIndex(D2, 2, 0);
            [~, yf] = AE_plotWaveformByIndex(tc.DTA, 2, 0);
            tc.verifyEqual(y2, yf);
        end

        function customHitLayoutFollowsEventDefinition(tc)
            % Msg 5 says each hit carries [amplitude(1) rise(2)] and no parametrics
            msg5  = [2 6 1 0];                                  % #CHID, CHIDs, #PID
            setup = tc.frame(42, [0 200 0, tc.lsub(5, msg5)]);
            hit   = @(t, ch, amp, rise) tc.frame(1, [tc.t6(t) ch amp typecast(uint16(rise), 'uint8')]);
            fn = tc.writeDTA([setup hit(1000, 1, 77, 321) hit(2000, 2, 55, 654)]);
            D = AE_readDTA(fn);
            tc.verifyEqual(D.setup.chid, [6 1]);
            tc.verifyEqual(D.hit.channel.', [1 2]);
            tc.verifyEqual(D.hit.amplitude_db.', uint8([77 55]));
            tc.verifyEqual(D.hit.risetime_us.', uint16([321 654]));
            tc.verifyEqual(D.hit.counter.', [1000 2000]);
            tc.verifyFalse(isfield(D.hit, 'counts'));
        end

        function unknownCharacteristicsStopDecodingSafely(tc)
            % CHID 99 is unknown: fields before it decode, the rest is ignored
            msg5  = [3 6 99 1 0];
            setup = tc.frame(42, [0 200 0, tc.lsub(5, msg5)]);
            hit   = tc.frame(1, [tc.t6(500) 3 88 zeros(1, 9)]);
            D = AE_readDTA(tc.writeDTA([setup hit]));
            tc.verifyEqual(D.hit.amplitude_db, uint8(88));
            tc.verifyFalse(isfield(D.hit, 'risetime_us'));
        end

        function waveformCountWordAndOtherSubIds(tc)
            s = int16([5 -6 7 8 -9]);
            sb = typecast(s, 'uint8');
            % waveform with N word, followed by trailing AEF bytes that must be ignored
            wfN   = tc.frame(173, [1 tc.t6(10) 2 0 typecast(uint16(5), 'uint8') sb 9 9 9 9]);
            % waveform without N word (first two bytes are samples)
            wfRaw = tc.frame(173, [1 tc.t6(20) 3 0 sb]);
            spec  = tc.frame(173, [3 tc.t6(30) 4 0 sb]);        % sub-ID 3 = not a waveform
            D = AE_readDTA(tc.writeDTA([wfN wfRaw spec]));
            tc.verifyEqual(numel(D.wf.channel), 2);
            tc.verifyEqual(D.wf.channel.', [2 3]);
            tc.verifyEqual(D.wf.samples{1}.', s);
            tc.verifyEqual(D.wf.nsamp.', uint32([5 5]));
            tc.verifyEqual(D.wf.counter.', [10 20]);
        end

        function emptyWfsReturnsEmptyWithWarning(tc)
            fn = tc.truncatedWFS();
            tc.verifyWarning(@() openWFS(fn), 'AE:emptyWFS');
            warning('off', 'AE:emptyWFS');
            [d, t, h] = openWFS(fn);
            warning('on', 'AE:emptyWFS');
            tc.verifySize(d, [2 0]);
            tc.verifyEmpty(t);
            tc.verifyEqual(h.DataLength, 0);
        end

        function waveformFeaturesOfKnownSignals(tc)
            Fs = 1e6;  t = (0:4095).' / Fs;
            a = 3;  x = a * sin(2*pi*50e3*t) + 10;               % DC offset must not matter
            f = AE_waveformFeatures(x, Fs);
            tc.verifyEqual(f.RMS, a / sqrt(2), 'RelTol', 1e-3);
            tc.verifyEqual(f.CrestFactor, sqrt(2), 'RelTol', 1e-3);
            tc.verifyEqual(f.Kurtosis, 1.5, 'RelTol', 1e-3);
            tc.verifyEqual(f.Skewness, 0, 'AbsTol', 5e-3);
            tc.verifyEqual(f.SpectralCentroid, 50e3, 'AbsTol', 2e3);
            tc.verifyEqual(f.Envelope_RMS, a / sqrt(2) * sqrt(2), 'RelTol', 2e-2);   % envelope ~ a
            tc.verifyEqual(f.Fs, Fs);
            f2 = AE_waveformFeatures(x, t);                       % time vector input
            tc.verifyEqual(f2.RMS, f.RMS, 'RelTol', 1e-9);
            tc.verifyError(@() AE_waveformFeatures(x, t(1:10)), '');
            tc.verifyError(@() AE_waveformFeatures(1:3, Fs), '');
        end

        function spectrumFilterAndNorm(tc)
            % Tones sit exactly on FFT bins 205 and 1229 so amplitudes read 1.0
            Fs = 1e6;  N = 4096;  t = (0:N-1).' / Fs;
            kLo = 205;  kHi = 1229;
            y = sin(2*pi*kLo*Fs/N*t) + sin(2*pi*kHi*Fs/N*t);
            lo = @(A) A(kLo + 1);  hi = @(A) A(kHi + 1);
            [~, A] = AE_waveformSpectrum(y, Fs, 'Window', 'rect');
            tc.verifyEqual([lo(A) hi(A)], [1 1], 'AbsTol', 1e-9);     % unfiltered reference
            [~, A] = AE_waveformSpectrum(y, Fs, 'Filter', 'lowpass', 'FilterFreqs', 100e3, 'Window', 'rect');
            tc.verifyGreaterThan(lo(A), 0.98);
            tc.verifyLessThan(hi(A), 0.01);
            [~, A] = AE_waveformSpectrum(y, Fs, 'Filter', 'highpass', 'FilterFreqs', 100e3, 'Window', 'rect');
            tc.verifyLessThan(lo(A), 0.01);
            tc.verifyGreaterThan(hi(A), 0.98);
            [~, A] = AE_waveformSpectrum(y, Fs, 'Filter', 'bandpass', 'FilterFreqs', [200e3 400e3], 'Window', 'rect');
            tc.verifyLessThan(lo(A), 0.01);
            tc.verifyGreaterThan(hi(A), 0.85);
            [~, An] = AE_waveformSpectrum(y, Fs, 'Norm', 'max');
            tc.verifyEqual(max(An), 1, 'AbsTol', 1e-9);
            [~, As] = AE_waveformSpectrum(y, Fs, 'Norm', 'sum');
            tc.verifyEqual(sum(As), 1, 'AbsTol', 1e-9);
            tc.verifyError(@() AE_waveformSpectrum(y, Fs, 'Filter', 'lowpass'), '');
            tc.verifyError(@() AE_waveformSpectrum(y, Fs, 'Filter', 'lowpass', 'FilterFreqs', 6e5), '');
            tc.verifyError(@() AE_waveformSpectrum(y, Fs, 'Filter', 'bandpass', 'FilterFreqs', [4e5 2e5]), '');
            tc.verifyError(@() AE_waveformSpectrum(y, Fs, 'Norm', 'bogus'), '');
        end

        function folderFeaturesAndTrends(tc)
            dirn = tempname;  mkdir(dirn);
            cleanup = onCleanup(@() rmdir(dirn, 's'));
            names = {'STREAM20260101-120000-001.wfs', 'STREAM20260101-120200-002.wfs', ...
                     'STREAM20260101-120400-003.wfs'};
            copyfile(tc.WFS, fullfile(dirn, names{1}));
            copyfile(tc.truncatedWFS(), fullfile(dirn, names{2}));      % header only
            copyfile(tc.WFS, fullfile(dirn, names{3}));
            matf = [tempname '.mat'];
            T = AE_wfsFolderFeatures(dirn, 'Channel', 2, 'Verbose', false, 'SaveAs', matf);
            c2 = onCleanup(@() delete(matf));
            tc.verifyEqual(height(T), 3);
            tc.verifyEqual(T.Status, {'ok'; 'empty'; 'ok'});
            tc.verifyEqual(T.Time_min, [0; 2; 4]);
            tc.verifyTrue(isnan(T.RMS(2)));
            tc.verifyEqual(T.RMS(1), T.RMS(3));                         % same source file
            tc.verifyTrue(all(ismember({'RMS', 'Kurtosis', 'Envelope_RMS'}, T.Properties.VariableNames)));
            S = load(matf);  tc.verifyEqual(S.T.RMS, T.RMS);
            [d, ~, h] = openWFS(tc.WFS);
            ref = AE_waveformFeatures(d(2, :), h.SampleRate_Hz(1));
            tc.verifyEqual(T.RMS(1), ref.RMS);
            T2 = AE_wfsFolderFeatures(dirn, 'Channel', 1, 'DtMinutes', 5, 'Verbose', false);
            tc.verifyEqual(T2.Time_min, [0; 5; 10]);
            % a channel the files do not have: no file yields features -> clear error
            tc.verifyError(@() AE_wfsFolderFeatures(dirn, 'Channel', 7, 'Verbose', false), '');        end

        function featureTrendPlot(tc)
            T = table((0:4).', rand(5,1), rand(5,1), 'VariableNames', {'Time_min', 'RMS', 'Kurtosis'});
            fig = AE_plotFeatureTrends(T, 'Features', {'RMS', 'Kurtosis'});
            cleanup = onCleanup(@() close(fig));
            tc.verifyEqual(numel(findobj(fig, 'Type', 'axes')), 2);
            tc.verifyError(@() AE_plotFeatureTrends(T, 'Features', {'Nope'}), '');
            tc.verifyError(@() AE_plotFeatureTrends(T(:, 2:3)), '');
        end
    end

    methods (Access = private)
        function b = t6(~, v)
            b = double(typecast(uint64(v), 'uint8'));  b = b(1:6);
        end
        function b = lsub(~, id, body)
            b = [typecast(uint16(1 + numel(body)), 'uint8'), id, body];
        end
        function b = frame(~, id, body)
            b = [typecast(uint16(1 + numel(body)), 'uint8'), id, body];
        end
        function fn = writeDTA(tc, bytes)
            fn = [tempname '.DTA'];
            fid = fopen(fn, 'wb');  fwrite(fid, bytes, 'uint8');  fclose(fid);
            tc.addTeardown(@delete, fn);
        end
        function fn = truncatedWFS(tc)
            % Header plus sync message only: what AEwin leaves when a recording
            % is stopped before the first data block (282 bytes for 2 channels).
            fid = fopen(tc.WFS, 'rb');  b = fread(fid, 282, 'uint8');  fclose(fid);
            fn = [tempname '.wfs'];
            fid = fopen(fn, 'wb');  fwrite(fid, b, 'uint8');  fclose(fid);
            tc.addTeardown(@delete, fn);
        end
        function f = frames(tc)
            % Split the example file into raw frames (header, wf, hit).
            fid = fopen(tc.DTA, 'rb'); R = fread(fid, inf, 'uint8=>uint8'); fclose(fid);
            pos = 1; f.wf = {}; f.hit = {}; f.header = uint8([]);
            while pos <= numel(R) - 3
                len = double(R(pos)) + 256 * double(R(pos+1));
                fr  = R(pos : pos + 1 + len);
                switch R(pos+2)
                    case 173, f.wf{end+1}  = fr;
                    case 1,   f.hit{end+1} = fr;
                    otherwise
                        if isempty(f.wf), f.header = [f.header; fr]; end
                end
                pos = pos + 2 + len;
            end
        end
    end
end
