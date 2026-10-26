function feat = AE_waveformFeatures(x, tOrFs)
% AE_waveformFeatures  Time-, frequency- and envelope-domain features of one waveform.
%
%   feat = AE_waveformFeatures(x, Fs)
%   feat = AE_waveformFeatures(x, t)       % t = time vector [s], uniform steps
%
%   Computes the condition-monitoring features commonly trended for AE data
%   (RMS, kurtosis, crest factor, spectral centroid, band energies, envelope
%   statistics, Hjorth parameters, ...). Needs no toolboxes: rms, kurtosis,
%   skewness, the Hann window and the Hilbert envelope are implemented here
%   with the same definitions as the Signal Processing / Statistics Toolbox
%   functions of the same names.
%
%   INPUTS
%     x     : waveform samples (vector, mV or any unit)
%     tOrFs : sample rate [Hz] (scalar) or time vector [s] (same length as x)
%
%   OUTPUT
%     feat : struct with fields
%       Time domain   : RMS, Peak, PeakToPeak, CrestFactor, Kurtosis, Skewness,
%                       EnergyTime, HitCount, Duration, RiseTime
%       Frequency     : FFT_PeakAmplitude, BroadbandEnergy, SpectralCentroid,
%                       SpectralKurtosis, BandEnergy_Low, BandEnergy_Mid,
%                       BandEnergy_High
%       Envelope      : Envelope_RMS, Envelope_Peak,
%                       EnvelopeSpec_PeakAmplitude, EnvelopeSpec_PeakFrequency
%       Hjorth        : Hjorth_Activity, Hjorth_Mobility, Hjorth_Complexity
%       Meta          : Fs, N
%
%   DEFINITIONS
%     * The mean is removed first. Peak is the signed maximum of that signal.
%     * HitCount / Duration / RiseTime use an automatic threshold of 4 x std(x):
%       upward crossings, first-to-last crossing time, and first crossing to
%       the peak (seconds; NaN when the threshold is never reached).
%     * Spectra use a Hann window and an FFT padded to the next power of two;
%       band energies split 0.05-0.25, 0.25-0.5 and 0.5-0.9 of Nyquist.
%     * Wavelet features are not included (they require the Wavelet Toolbox).
%
%   EXAMPLE
%     [data, t] = openWFS('STREAM20260121-162654-010.wfs');
%     f = AE_waveformFeatures(data(2, :), t);
%     fprintf('RMS %.2f mV, kurtosis %.2f\n', f.RMS, f.Kurtosis);
%
%   Author : Osman Sayginer
%   Affil. : Temple University — Mechatronics Lab
%   Web    : https://mechatronics.sayginer.com
%   Part of the Mistras AEwin DTA/WFS MATLAB Reader Library.

x = double(x(:));
N = numel(x);
assert(N >= 4, 'AE_waveformFeatures: need at least 4 samples');

if isscalar(tOrFs)
    Fs = tOrFs;
else
    assert(numel(tOrFs) == N, 'AE_waveformFeatures: t must have the same length as x');
    Fs = 1 / mean(diff(tOrFs(:)));
end
assert(Fs > 0 && isfinite(Fs), 'AE_waveformFeatures: invalid sample rate');
dt = 1 / Fs;

x = x - mean(x);

% ---- Time domain --------------------------------------------------------
feat.RMS         = sqrt(mean(x.^2));
feat.Peak        = max(x);
feat.PeakToPeak  = max(x) - min(x);
feat.CrestFactor = feat.Peak / feat.RMS;
feat.Kurtosis    = mean(x.^4) / mean(x.^2)^2;
feat.Skewness    = mean(x.^3) / mean(x.^2)^1.5;
feat.EnergyTime  = sum(x.^2) * dt;

thr = 4 * std(x);
feat.HitCount = sum(x(1:end-1) < thr & x(2:end) >= thr);
idxCross = find(x >= thr);
if ~isempty(idxCross)
    iFirst = idxCross(1);
    iLast  = idxCross(end);
    feat.Duration = (iLast - iFirst) / Fs;
    [~, ip] = max(x(iFirst:iLast));
    feat.RiseTime = (ip - 1) / Fs;
else
    feat.Duration = NaN;
    feat.RiseTime = NaN;
end

% ---- Frequency domain ---------------------------------------------------
w    = hann_(N);
NFFT = 2^nextpow2(N);
X    = fft(x .* w, NFFT);
half = 1:floor(NFFT/2);
f    = (half(:) - 1) * (Fs / NFFT);
P    = abs(X(half)).^2;

feat.FFT_PeakAmplitude = max(P);
feat.BroadbandEnergy   = sum(P) * (Fs / NFFT);
feat.SpectralCentroid  = sum(f .* P) / sum(P);
feat.SpectralKurtosis  = mean((P - mean(P)).^4) / mean((P - mean(P)).^2)^2;

edges = [0.05 0.25; 0.25 0.5; 0.5 0.9] * (Fs / 2);
names = {'BandEnergy_Low', 'BandEnergy_Mid', 'BandEnergy_High'};
for b = 1:3
    in = f >= edges(b,1) & f <= edges(b,2);
    feat.(names{b}) = sum(P(in)) * (Fs / NFFT);
end

% ---- Envelope -----------------------------------------------------------
env = abs(analytic_(x));
feat.Envelope_RMS  = sqrt(mean(env.^2));
feat.Envelope_Peak = max(env);

Pe = abs(fft(env .* w, NFFT));
Pe = Pe(half).^2;
if numel(Pe) > 2
    [feat.EnvelopeSpec_PeakAmplitude, ie] = max(Pe(2:end));
    feat.EnvelopeSpec_PeakFrequency = f(ie + 1);
else
    feat.EnvelopeSpec_PeakAmplitude = NaN;
    feat.EnvelopeSpec_PeakFrequency = NaN;
end

% ---- Hjorth parameters --------------------------------------------------
dx  = diff(x);
ddx = diff(dx);
v0 = var(x);  v1 = var(dx);  v2 = var(ddx);
feat.Hjorth_Activity   = v0;
feat.Hjorth_Mobility   = sqrt(v1 / v0);
feat.Hjorth_Complexity = sqrt(v2 / v1) / feat.Hjorth_Mobility;

feat.Fs = Fs;
feat.N  = N;
end

% =========================================================================
function w = hann_(N)
% Symmetric Hann window (same as hann(N)).
    w = 0.5 - 0.5 * cos(2*pi*(0:N-1).' / (N-1));
end

function z = analytic_(x)
% Analytic signal via the FFT (same as hilbert(x)).
    N = numel(x);
    X = fft(x);
    h = zeros(N, 1);
    if mod(N, 2) == 0
        h([1 N/2+1]) = 1;
        h(2:N/2)     = 2;
    else
        h(1)         = 1;
        h(2:(N+1)/2) = 2;
    end
    z = ifft(X .* h);
end
