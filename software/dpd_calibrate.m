clear; clc; close all;
rng(42);

% Plot behavior: 'both' (show windows + save PNGs), 'save' (PNGs only),
% 'show' (windows only), or 'none'
% PA distortion mode: 'low_dist' (mild) or 'high_dist' (strong, default)
% Pass as CLI args: octave dpd_calibrate.m [plot_mode] [pa_mode]
plot_mode = 'both';
pa_mode  = 'high_dist';
if exist('OCTAVE_VERSION', 'builtin')
    a = argv();
    if numel(a) >= 1
        plot_mode = a{1};
    end
    if numel(a) >= 2
        pa_mode = a{2};
    end
end
if ~any(strcmp(plot_mode, {'both','save','show','none'}))
    warning('Invalid plot_mode "%s"; using "both".', plot_mode);
    plot_mode = 'both';
end

% PA distortion presets: low_dist = mild linear+cubic memory (the original
% golden reference), high_dist = stronger memory terms so the distorted
% waveform is clearly distinguishable from the clean input while still being
% fully invertible by the 4-tap predistorter.
pa_presets = struct( ...
    'low_dist', [1.00; -0.10+0.05j; -0.25-0.10j; 0.05+0.02j], ...
    'high_dist', [1.00; -0.35+0.15j; -0.25-0.10j; 0.20+0.06j]);
if ~isfield(pa_presets, pa_mode)
    warning('Invalid pa_mode "%s"; using "high_dist".', pa_mode);
    pa_mode = 'high_dist';
end

% Qt renders hidden figures for PNG-only export (fltk cannot)
try
    graphics_toolkit('qt');
catch
end

% ----------------------------------------------------------------------
% Helper functions (defined before use; required for Octave scripts)
% ----------------------------------------------------------------------

function d = nmse_db(x, ref)
    d = 10*log10(sum(abs(x - ref).^2) / sum(abs(ref).^2));
end

function y = add_noise(x, sigma)
    y = x + sigma*(randn(numel(x),1) + 1j*randn(numel(x),1));
end

% Quantize to signed fixed point: round(v*2^FL), clip to WL bits
function q = qfix(v, WL, FL)
    q = int32(max(min(round(v*2^FL), 2^(WL-1)-1), -2^(WL-1)));
end

function s = ok_str(v)
    if v == 0, s = '(OK)'; else, s = '(WARNING: should be 0)'; end
end

function ensure_dirs()
    for d = {fullfile('results','reports'), fullfile('results','plots')}
        if ~exist(d{1}, 'dir'), mkdir(d{1}); end
    end
end

% Write an integer matrix, one line per column of rows
function write_ints(path, rows, fmt)
    fid = fopen(path, 'w');
    if fid == -1, error('Cannot open %s for writing.', path); end
    fprintf(fid, fmt, rows.');
    fclose(fid);
end

% Memory polynomial basis: Phi(n,(k-1)*M+m) = s[n-m]*|s[n-m]|^(2k-2)
function Phi = mp_basis(s, K, M)
    N = numel(s);
    Phi = zeros(N, K*M);
    for m = 1:M
        d = m - 1;
        sd = [zeros(d,1); s(1:end-d)];
        for k = 1:K
            Phi(:, (k-1)*M + m) = sd .* abs(sd).^(2*k-2);
        end
    end
end

% Memory polynomial output: y = basis(s) * model.c
function y = mp_eval(s, model)
    y = mp_basis(s, model.K, model.M) * model.c;
end

function dpd_plot(x_in, y_nodpd, y_dpd, y_ideal, idx, Nfft, tag, png, mode)
    if nargin < 9, mode = 'both'; end
    show = strcmp(mode, 'show') || strcmp(mode, 'both');
    save = strcmp(mode, 'save') || strcmp(mode, 'both');
    if ~show && ~save, return; end

    vis = 'on'; if ~show, vis = 'off'; end
    figure('Name', sprintf('DPD before vs after (%s)', tag), 'Position', [100 100 1400 750], 'Visible', vis);
    c_clean = [0.1 0.3 0.7]; c_nodpd = [0.85 0.2 0.2]; c_dpd = [0.2 0.55 0.2];

    % Time-domain before/after: clean input -> PA distorted -> DPD corrected
    nwin = min(numel(idx), 1500);
    win = idx(1:nwin);
    subplot('Position', [0.08 0.55 0.52 0.36]);
    plot(1:nwin, real(x_in(win)),    'Color', c_clean, 'LineWidth', 1.2); hold on;
    plot(1:nwin, real(y_nodpd(win)), 'Color', c_nodpd, 'LineWidth', 1.0);
    plot(1:nwin, real(y_dpd(win)),   'Color', c_dpd,   'LineWidth', 1.0);
    plot(1:nwin, real(y_ideal(win)), 'k--', 'LineWidth', 0.8);
    xlim([1 nwin]);
    xlabel('sample'); ylabel('Re{signal}');
    legend('Clean input', 'PA distorted', 'DPD corrected', 'Ideal', 'Location', 'northoutside', 'Orientation', 'horizontal');
    title(sprintf('Waveforms: clean -> PA -> DPD (%s)', tag)); grid on;

    subplot('Position', [0.62 0.55 0.34 0.36]);
    plot(abs(x_in(idx)), abs(y_nodpd(idx)), '.', 'MarkerSize', 4, 'Color', c_nodpd); hold on;
    plot(abs(x_in(idx)), abs(y_dpd(idx)),    '.', 'MarkerSize', 4, 'Color', c_dpd);
    plot(abs(x_in(idx)), abs(y_ideal(idx)),  'k--', 'LineWidth', 1.2);
    xlabel('|x|'); ylabel('|y|');
    legend('No DPD', 'DPD', 'Ideal', 'Location', 'northwest');
    title('AM-AM: gain compression'); grid on;

    subplot('Position', [0.08 0.08 0.52 0.36]);
    f = linspace(-0.5, 0.5, Nfft);
    Pn = 20*log10(abs(fftshift(fft(y_nodpd(idx), Nfft))) + eps);
    Pd = 20*log10(abs(fftshift(fft(y_dpd(idx),    Nfft))) + eps);
    Pi = 20*log10(abs(fftshift(fft(y_ideal(idx),  Nfft))) + eps);
    ref = max(Pi);
    plot(f, Pn - ref, 'Color', c_nodpd); hold on;
    plot(f, Pd - ref, 'Color', c_dpd);
    plot(f, Pi - ref, 'k--', 'LineWidth', 1.0);
    xlabel('Normalized frequency'); ylabel('dB');
    legend('No DPD', 'DPD', 'Ideal', 'Location', 'southoutside', 'Orientation', 'horizontal');
    title('Output spectrum'); grid on; ylim([-80 5]);

    subplot('Position', [0.62 0.08 0.34 0.36]);
    plot(abs(y_ideal(idx) - y_nodpd(idx)), 'Color', c_nodpd); hold on;
    plot(abs(y_ideal(idx) - y_dpd(idx)),    'Color', c_dpd);
    xlabel('sample'); ylabel('|error|');
    legend('No DPD', 'DPD');
    title('Instantaneous error vs ideal'); grid on;
    drawnow;
    if save
        try
            print(gcf, png, '-dpng');
            fprintf('Saved figure: %s\n', png);
        catch
            fprintf('Warning: could not save figure (Ghostscript missing).\n');
        end
        if ~show, close(gcf); end
    end
end

% ----------------------------------------------------------------------
% Model and PA parameters
% ----------------------------------------------------------------------
K = 2; M = 2;                   % MP nonlinear orders and memory depth
n = K*M;                        % number of taps (= 4)

pa.K = K; pa.M = M;
pa.c = pa_presets.(pa_mode);

fprintf('Memory polynomial (complex coeffs): K=%d (up to order %d), M=%d -> %d taps [PA mode: %s]\n', ...
    K, 2*K-1, M, n, pa_mode);

% ----------------------------------------------------------------------
% Input signal and (simulated) PA output
% ----------------------------------------------------------------------
Nsamp = 20000;
t = (0:Nsamp-1)';
x = zeros(Nsamp,1);
for f = [0.01 0.013 0.017 0.021]
    x = x + exp(1j*2*pi*f*t);
end
x = x/max(abs(x)) * 0.85 .* exp(1j*0.05*randn(Nsamp,1));

y_no_dpd = add_noise(mp_eval(x, pa), 0.001);

% ----------------------------------------------------------------------
% Estimate predistorter coefficients with complex least squares
% ----------------------------------------------------------------------
Phi = mp_basis(y_no_dpd, K, M);
v = M:Nsamp;                    % valid samples after delay-line settling
c = Phi(v,:) \ x(v);

fprintf('\nEstimated complex coefficients:\n');
for k = 1:K
    for m = 1:M
        i = (k-1)*M + m;
        fprintf('  c[order %d, delay %d] = %+.5f %+.5fj\n', 2*k-1, m-1, real(c(i)), imag(c(i)));
    end
end
fprintf('\nPostdistorter fit NMSE: %.2f dB\n', nmse_db(Phi(v,:)*c, x(v)));

% ----------------------------------------------------------------------
% Full-system simulation: predistorted vs undistorted
% ----------------------------------------------------------------------
x_pd   = mp_basis(x, K, M) * c; % complex predistorted signal
y_dpd  = add_noise(mp_eval(x_pd, pa), 0.001);

G = pa.c(1);
y_ideal = G * x;

nmse_nodpd = nmse_db(y_no_dpd(v), y_ideal(v));
nmse_dpd   = nmse_db(y_dpd(v),    y_ideal(v));
fprintf('\n--- Linearization result (software model) ---\n');
fprintf('NMSE no DPD : %.2f dB\n', nmse_nodpd);
fprintf('NMSE with DPD: %.2f dB\n', nmse_dpd);
fprintf('Improvement : %.2f dB\n', nmse_nodpd - nmse_dpd);

cap_file = fullfile('results','reports','cap_export.csv');
if isfile(cap_file)
    ensure_dirs();
    dpd_plot(x, y_no_dpd, y_dpd, y_ideal, v, 4096, sprintf('MATLAB (%s)', pa_mode), ...
        sprintf('results/plots/dpd_matlab_%s.png', pa_mode), plot_mode);
end

% ----------------------------------------------------------------------
% Quantize coefficients to Q2.10 fixed point (12 bits, signed)
% ----------------------------------------------------------------------
WL = 12; FL = 10;
ci = qfix(real(c), WL, FL);
cq = qfix(imag(c), WL, FL);

fprintf('\nQuantized coefficients (Q2.10, %d bits):\n', WL);
fprintf('  tap  coeff_complex        i_fixed   q_fixed\n');
for i = 1:n
    fprintf('  %3d  %+.5f%+.5fj  %8d  %8d\n', i-1, real(c(i)), imag(c(i)), ci(i), cq(i));
end

% ----------------------------------------------------------------------
% Export RTL stimulus and weights (see rtl/dpd/filter.sv)
% ----------------------------------------------------------------------
ensure_dirs();
WL_x = 16; FL_x = 12;           % Q4.12 I/Q samples, matches filter.sv
Nsamp_hw = Nsamp;
xi = qfix(real(x(1:Nsamp_hw)), WL_x, FL_x);
xq = qfix(imag(x(1:Nsamp_hw)), WL_x, FL_x);

write_ints(fullfile('results','reports','ref_stimulus.txt'), [xi xq], '%d %d\n');
write_ints(fullfile('results','reports','weights_i.txt'), ci, '%d\n');
write_ints(fullfile('results','reports','weights_q.txt'), cq, '%d\n');

fprintf('\nExported %d I/Q samples (Q%d.%d) and %d complex weights (Q%d.%d) to results/reports.\n', ...
    Nsamp_hw, WL_x-FL_x, FL_x, n, WL-FL, FL);
fprintf('Run the RTL simulation to produce results/reports/cap_export.csv (ref_i, ref_q, fb_i, fb_q), then rerun this script.\n');

% ----------------------------------------------------------------------
% Hardware validation: import RTL capture and re-evaluate linearization
% ----------------------------------------------------------------------
if ~isfile(cap_file)
    fprintf('\nStimulus and weights exported. Run the RTL simulation to generate %s, then rerun this script for plots and validation.\n', cap_file);
else
    cap = dlmread(cap_file);
    assert(size(cap,2) == 4, 'Expected 4 columns (ref_i, ref_q, fb_i, fb_q) in %s.', cap_file);

    x_hw    = (cap(:,1) + 1j*cap(:,2)) / 2^FL_x;
    x_pd_hw = (cap(:,3) + 1j*cap(:,4)) / 2^FL_x;
    Nhw = numel(x_hw);
    if Nhw ~= Nsamp_hw
        warning('Captured %d samples, expected %d.', Nhw, Nsamp_hw);
    end

    n_check = min(Nhw, Nsamp_hw);
    err_i = max(abs(cap(1:n_check,1) - double(xi(1:n_check))));
    err_q = max(abs(cap(1:n_check,2) - double(xq(1:n_check))));
    fprintf('\n--- Reference round-trip check ---\n');
    fprintf('Max |diff| ref_i (Q%d.%d): %d %s\n', WL_x-FL_x, FL_x, err_i, ok_str(err_i));
    fprintf('Max |diff| ref_q (Q%d.%d): %d %s\n', WL_x-FL_x, FL_x, err_q, ok_str(err_q));
    if err_i ~= 0 || err_q ~= 0
        fprintf('  -> Captured reference does not match this run''s stimulus (stale cap_export.csv?)\n');
    end

    y_no_dpd_hw = add_noise(mp_eval(x_hw,    pa), 0.001);
    y_dpd_hw    = add_noise(mp_eval(x_pd_hw, pa), 0.001);
    y_ideal_hw  = G * x_hw;
    v_hw = M:Nhw;

    fprintf('\n--- Linearization result (hardware x_pd) ---\n');
    fprintf('NMSE no DPD : %.2f dB\n', nmse_db(y_no_dpd_hw(v_hw), y_ideal_hw(v_hw)));
    fprintf('NMSE with DPD: %.2f dB\n', nmse_db(y_dpd_hw(v_hw),   y_ideal_hw(v_hw)));
    fprintf('Improvement : %.2f dB\n', nmse_db(y_no_dpd_hw(v_hw), y_ideal_hw(v_hw)) - ...
        nmse_db(y_dpd_hw(v_hw), y_ideal_hw(v_hw)));

    dpd_plot(x_hw, y_no_dpd_hw, y_dpd_hw, y_ideal_hw, v_hw, 2048, sprintf('hardware (%s)', pa_mode), ...
        sprintf('results/plots/dpd_hardware_%s.png', pa_mode), plot_mode);
end
