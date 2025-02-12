function c = fmcw_range2(vdat,p,maxRange,winfun)

% c = fmcw_range2(vdat,p,maxrange,winfun)

% Phase sensitive processing of FMCW radar data based on Brennan et al. 2013
%
% Based on Paul's scripts but following the nomenclature of:
% "Phase-sensitive FMCW radar imaging system for high precision Antarctic
% ice shelf profile monitoring"
% Brennan, Lok, Nicholls and Corr, 2013
%
% Summary: phase sensitive processing for FMCW radar intermediate frequency 
% voltage timeseries. Output: coarse and fine range and corrected and
% uncorrected complex spectrums.
%
% input args: 
% vdat = structure containing shot metadata
% vdat.vif = data matrix of vltages as digitised with one chirp per row size(nchirps,nsamples)
% p = pad factor (i.e. level of interpolation to use during fft)
% maxrange = maximum range to crop output to
% winfun = window function handle (default: @blackman)
%
% outputs:
% c = structure conmtaining all output fields:
% .rangeCoarse = range to bin centres (m)
% .rangeFine = range to reflector from bin centre (m)
% .specRaw = spectrum without phase correction
% .specRel = spectrum corrected. positive frequency half of spectrum with
% ref phase subtracted. This is the complex signal which can be used for
% cross-correlating two shot segements.
% .
%
% Craig Stewart
% Modified from fmcw_range 23 Oct 2014 to produce outptu structure rather
% than multiple parameters

if nargin < 3
    maxRange = 2000; %m (range to crop output to)
end
if nargin < 4
    winfun = @blackman; % default to blackman window
end

% Ensure odd number of samples per chirp (to get phase centering right)
vdat = fmcw_burst_make_length_odd(vdat);

% Extract variables from structure to make it readable
B = vdat.B; %bandwidth 
K = vdat.K; %chirp gradient
ci = vdat.ci; %speed of light in ice
fc = vdat.fc; %center frequency
lambdac = vdat.lambdac; %center wavelength

% Processing settings
N = size(vdat.vif,2);
if mod(N,2)
    xn = 0.5*(N-1); % timeshift amount (steps) prior to fft to get fft measuring phase at t=T/2
    %shiftFrac = 0.45;
    %xn = round(shiftFrac*(N-1)); % timeshift amount (steps) prior to fft to get fft measuring phase at t=T/2
    %disp(['warning - non standard shift offset ' num2str(shiftFrac)])
else
    disp('Warning: even number of sample in record, not possible to correctly offset to phase centre')
    xn = 0.5*(N);
end
[nchirps,N] = size(vdat.vif);

win = window(winfun,N); %chebwin(N);  %rectwin(N); %

%% Loop through for each shot in burst
% Calculate phase of each range bin centre for correction
nf = round((p*N)/2 - 0.5); % max number of frequencies to recover
n = (0:nf - 1)';
rangeCoarse = transpose(n*ci/(2*B*p));
% Calculate requested depth range
nmax = find(rangeCoarse<=maxRange,1,'last');
rangeCoarse = rangeCoarse(1:nmax);
n = n(1:nmax);
phiref = 2*pi*fc*n./(B.*p) - (K*n.^2)/(2*B.^2*p.^2); % eq 17: phase for each range bin centre (measured at t=T/2), given that tau = n/(B*p)
comp = exp(-1i*phiref); % unit phasor with conjugate of above phase
[specRaw,specRel] = deal(zeros(nchirps,nmax)); % preallocate
for chirp = 1:nchirps
    vif = vdat.vif(chirp,:);
    vif = vif-mean(vif); % de-mean
    vif = win.*vif.'; % windowed
    %vif = [vif; zeros((p-1)*N,1)]; % zero padded to length p*N
    vifpad = zeros(p*N,1);
    vifpad(1:length(vif)) = vif;
    vifpad = circshift(vifpad,-xn); % signal time shifted so phase centre at start
    %plot(vifpad), keyboard
    fftvif = (sqrt(2*p)/length(vifpad)).*fft(vifpad); % fft and scale for padding 
    fftvif = fftvif./rms(win); % scale for window
    specRaw(chirp,:) = fftvif(1:nmax); % positive frequency half of spectrum up to (nyquist minus deltaf)
    specRel(chirp,:) = comp.*fftvif(1:nmax); % positive frequency half of spectrum with ref phase subtracted
end
%rangeFine = lambdac*angle(specRel)/(4*pi); % Distance from centre of range bin to effective reflector: eq 15
%rangeFine = angle(specRel)./((4*pi/lambdac) - (4*rangeCoarse*K/ci^2)); % this is the full equation including the term generated by the last term in (13)
rangeFine = fmcw_phase2range(angle(specRel),lambdac,repmat(rangeCoarse,size(specRel,1),1),K,ci);

% Structure for output
c.rangeCoarse = rangeCoarse;
c.rangeFine = rangeFine;
c.specRaw = specRaw;
c.specRel = specRel;
