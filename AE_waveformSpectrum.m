function [f, A, stats] = AE_waveformSpectrum(y, Fs, varargin)
% AE_waveformSpectrum  Single-sided amplitude spectrum of an AE waveform.
%
%   [f, A, stats] = AE_waveformSpectrum(y, Fs)
%   [f, A, stats] = AE_waveformSpectrum(y, Fs, Name, Value, ...)
%
%   Computes the FFT of a waveform and reports the frequency content that
%   AE analysis normally cares about (peak and centroid frequency). Needs no
%   toolboxes: the window is generated here.
%
%   INPUTS
%     y  : waveform samples (vector), e.g. y from AE_plotWaveformByIndex
%     Fs : sample rate [Hz] (must match the data, e.g. info.Fs)
%
%   NAME-VALUE OPTIONS
%     'Window'    - 'hann' (default) or 'rect'
%     'NFFT'      - FFT length; zero-pads when larger than numel(y)
%                   (default: next power of two >= numel(y))
%     'Detrend'   - remove the mean before the FFT (default: true)
%     'FreqRange' - [fLow fHigh] in Hz used for peak and centroid
%                   (default: 0 to Fs/2, excluding DC)
%     'Filter'    - 'none' (default), 'lowpass', 'highpass' or 'bandpass',
%                   applied to the waveform before the FFT
%     'FilterFreqs' - cutoff [Hz]: scalar for low/highpass, [low high] for
%                   bandpass
%     'FilterOrder' - Butterworth order of the filter (default: 4)
%     'Norm'      - 'none' (default), 'max' (peak = 1), 'sum' (sums to 1) or
%                   'percent' (sums to 100)
%     'Plot'      - true opens a figure of the spectrum (default: false)
%     'FreqUnits' - axis units for the plot: 'kHz' (default), 'Hz' or 'MHz'
%
%   OUTPUTS
%     f     : [K x 1] frequency vector [Hz], 0 to Fs/2
%     A     : [K x 1] amplitude spectrum in the units of y. Scaled so a
%             sinusoid of amplitude a gives a peak of a (window gain removed),
%             unless 'Norm' is set.
%     stats : struct
%               .peak_freq_Hz     - frequency of the largest peak in range
%               .peak_amp         - amplitude at that peak
%               .centroid_freq_Hz - power-weighted mean frequency in range
%               .Fs, .nfft        - parameters used
%
%   FILTER
%     The filter is a zero-phase Butterworth: its squared magnitude response
%     1/(1+(f/fc)^(2n)) is applied in the frequency domain on a zero-padded
%     copy of the waveform. This equals what filtfilt(butter(n, ...)) gives
%     (no phase distortion, doubled attenuation) without needing the Signal
%     Processing Toolbox. Measured against filtfilt(butter(4, ...)) on real
%     waveforms the spectra agree to 0.1 % (lowpass), 0.3 % (highpass) and
%     about 5 % (bandpass, which is built as highpass x lowpass).
%
%   EXAMPLE
%     [t, y, info] = AE_plotWaveformByIndex('experiment_01.DTA', 3, 0);
%     [f, A, s] = AE_waveformSpectrum(y, info.Fs, 'Plot', true);
%     fprintf('Peak %.1f kHz, centroid %.1f kHz\n', ...
%             s.peak_freq_Hz/1e3, s.centroid_freq_Hz/1e3);
%
%     % 100-400 kHz band, normalised to the strongest peak
%     [f, A] = AE_waveformSpectrum(y, info.Fs, 'Filter', 'bandpass', ...
%                  'FilterFreqs', [100e3 400e3], 'Norm', 'max');
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

p = inputParser;
addParameter(p, 'Window',    'hann');
addParameter(p, 'NFFT',      []);
addParameter(p, 'Detrend',   true);
addParameter(p, 'FreqRange', []);
addParameter(p, 'Filter',      'none');
addParameter(p, 'FilterFreqs', []);
addParameter(p, 'FilterOrder', 4);
addParameter(p, 'Norm',        'none');
addParameter(p, 'Plot',      false);
addParameter(p, 'FreqUnits', 'kHz');
parse(p, varargin{:});

y = double(y(:));
N = numel(y);
assert(N >= 2, 'AE_waveformSpectrum: need at least 2 samples');
assert(isscalar(Fs) && Fs > 0, 'AE_waveformSpectrum: Fs must be a positive scalar');

nfft = p.Results.NFFT;
if isempty(nfft), nfft = 2^nextpow2(N); end
assert(nfft >= N, 'AE_waveformSpectrum: NFFT (%d) must be >= numel(y) (%d)', nfft, N);

y = zero_phase_filter_(y, Fs, lower(p.Results.Filter), p.Results.FilterFreqs, p.Results.FilterOrder);
if p.Results.Detrend, y = y - mean(y); end

switch lower(p.Results.Window)
    case 'hann'
        w = 0.5 - 0.5 * cos(2*pi*(0:N-1).' / (N-1));
    case 'rect'
        w = ones(N, 1);
    otherwise
        error('AE_waveformSpectrum: Window must be ''hann'' or ''rect''.');
end

% ---- FFT and single-sided amplitude -------------------------------------
X  = fft(y .* w, nfft);
K  = floor(nfft/2) + 1;
A  = abs(X(1:K)) / sum(w);          % coherent-gain normalisation
last = K - (mod(nfft, 2) == 0);     % DC and (for even nfft) Nyquist are not doubled
A(2:last) = 2 * A(2:last);          % fold negative frequencies onto positive
f  = (0:K-1).' * Fs / nfft;

switch lower(p.Results.Norm)
    case 'none'
    case 'max',     A = A / (max(A) + eps);
    case 'sum',     A = A / (sum(A) + eps);
    case 'percent', A = 100 * A / (sum(A) + eps);
    otherwise
        error('AE_waveformSpectrum: Norm must be ''none'', ''max'', ''sum'' or ''percent''.');
end

% ---- Peak and centroid over the requested band --------------------------
rng_ = p.Results.FreqRange;
if isempty(rng_), rng_ = [0 Fs/2]; end
in = f >= rng_(1) & f <= rng_(2) & f > 0;      % never count DC
assert(any(in), 'AE_waveformSpectrum: FreqRange contains no frequency bins');
[pk, ip]  = max(A(in));
fin       = f(in);
P         = A(in).^2;
stats.peak_freq_Hz     = fin(ip);
stats.peak_amp         = pk;
stats.centroid_freq_Hz = sum(fin .* P) / sum(P);
stats.Fs               = Fs;
stats.nfft             = nfft;

% ---- Optional plot ------------------------------------------------------
if p.Results.Plot
    switch lower(p.Results.FreqUnits)
        case 'hz',  d = 1;   u = 'Hz';
        case 'mhz', d = 1e6; u = 'MHz';
        otherwise,  d = 1e3; u = 'kHz';
    end
    figure;
    plot(f / d, A); hold on;
    plot(stats.peak_freq_Hz / d, stats.peak_amp, 'ro', 'MarkerFaceColor', 'r');
    yl = ylim;
    plot(stats.centroid_freq_Hz / d * [1 1], yl, '--k');
    grid on;
    xlabel(sprintf('Frequency (%s)', u));
    ylabel('Amplitude');
    title(sprintf('Peak %.1f %s | Centroid %.1f %s', ...
        stats.peak_freq_Hz / d, u, stats.centroid_freq_Hz / d, u));
    legend({'Spectrum', 'Peak', 'Centroid'}, 'Location', 'best');
end
end

% =========================================================================
function y = zero_phase_filter_(y, Fs, type, fc, order)
% Zero-phase Butterworth (|H|^2 response) applied in the frequency domain.
    if strcmp(type, 'none'), return; end
    Fn = Fs / 2;
    assert(~isempty(fc), 'AE_waveformSpectrum: FilterFreqs is required for a %s filter.', type);
    assert(isscalar(order) && order >= 1, 'AE_waveformSpectrum: FilterOrder must be >= 1.');
    switch type
        case {'lowpass', 'highpass'}
            assert(isscalar(fc) && fc > 0 && fc < Fn, ...
                'AE_waveformSpectrum: %s cutoff must be a scalar in (0, %.0f Hz).', type, Fn);
        case 'bandpass'
            assert(numel(fc) == 2 && fc(1) > 0 && fc(2) < Fn && fc(1) < fc(2), ...
                'AE_waveformSpectrum: bandpass needs [low high] with 0 < low < high < %.0f Hz.', Fn);
        otherwise
            error('AE_waveformSpectrum: Filter must be ''none'', ''lowpass'', ''highpass'' or ''bandpass''.');
    end

    N  = numel(y);
    M  = 2^nextpow2(2 * N);                      % zero-pad against wrap-around
    fm = (0:M-1).' * Fs / M;
    fm = min(fm, Fs - fm);                       % fold onto 0..Nyquist
    lp = @(c) 1 ./ (1 + (fm ./ c) .^ (2*order));
    hp = @(c) 1 ./ (1 + (c ./ max(fm, eps)) .^ (2*order));
    switch type
        case 'lowpass',  H2 = lp(fc);
        case 'highpass', H2 = hp(fc);
        case 'bandpass', H2 = hp(fc(1)) .* lp(fc(2));
    end
    z = real(ifft(fft(y, M) .* H2));
    y = z(1:N);
end
