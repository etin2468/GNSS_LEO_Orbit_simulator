function [signal_model, observation_state] = initializeSignalObservationModel(t_array, sats_per_system, scenario)
    % INITIALIZESIGNALOBSERVATIONMODEL Defines signal-level observation states.

    if nargin < 3
        scenario = "realistic";
    end

    scenario = string(scenario);
    valid_scenarios = ["clean", "realistic", "cycle-slip"];
    if ~any(scenario == valid_scenarios)
        error('GPSsimulator:InvalidScenario', ...
            'Scenario must be clean, realistic, or cycle-slip.');
    end

    rng(31415, "twister");

    c_light = 299792458;
    num_systems = numel(sats_per_system);
    num_epochs = numel(t_array);
    max_sats = max(sats_per_system);

    signal_model.scenario = scenario;
    signal_model.seed = 31415;
    signal_model.system_names = ["GPS", "GLONASS", "Galileo", "LEO"];
    signal_model.signal_names = ["L1 C/A", "G1 C/A", "E1 B/C", "L1-like"];
    signal_model.rinex_tracking_codes = ["1C", "1C", "1C", "1X"];
    signal_model.frequency_hz = [1575.42e6, 1602.00e6, 1575.42e6, 1575.42e6];
    signal_model.wavelength_m = c_light ./ signal_model.frequency_hz;

    % GLONASS uses its nominal G1 center frequency here. FDMA channel offsets
    % can be added when channel assignments are available.
    signal_model.phase_noise_sigma_m = [0.005, 0.008, 0.005, 0.015];
    signal_model.doppler_noise_sigma_hz = [0.10, 0.15, 0.10, 0.30];
    signal_model.cn0_zenith_dbhz = [48, 47, 48, 44];
    signal_model.cn0_floor_dbhz = 22;
    signal_model.cn0_noise_sigma_dbhz = [0.8, 1.0, 0.8, 1.5];

    signal_model.enable_cycle_slips = scenario == "cycle-slip";
    signal_model.enable_outages = scenario == "cycle-slip";
    signal_model.base_slip_probability = 0.015;
    signal_model.low_elevation_slip_probability = 0.08;
    signal_model.base_outage_probability = 0.005;
    signal_model.low_elevation_outage_probability = 0.04;
    signal_model.t_array = t_array(:);

    signal_model.initial_ambiguity_cycles = nan(num_systems, max_sats);
    signal_model.phase_bias_m = nan(num_systems, max_sats);
    signal_model.phase_noise_m = nan(num_systems, max_sats, num_epochs);
    signal_model.doppler_noise_hz = nan(num_systems, max_sats, num_epochs);
    signal_model.cn0_noise_dbhz = nan(num_systems, max_sats, num_epochs);
    signal_model.slip_uniform = nan(num_systems, max_sats, num_epochs);
    signal_model.outage_uniform = nan(num_systems, max_sats, num_epochs);
    signal_model.ambiguity_jump_cycles = nan(num_systems, max_sats, num_epochs);

    for sys = 1:num_systems
        sat_count = sats_per_system(sys);
        signal_model.initial_ambiguity_cycles(sys, 1:sat_count) = ...
            randi([100000, 9999999], 1, sat_count);
        signal_model.phase_bias_m(sys, 1:sat_count) = ...
            signal_model.wavelength_m(sys) .* (rand(1, sat_count) - 0.5);
        signal_model.phase_noise_m(sys, 1:sat_count, :) = permute( ...
            signal_model.phase_noise_sigma_m(sys) .* randn(num_epochs, sat_count), [3, 2, 1]);
        signal_model.doppler_noise_hz(sys, 1:sat_count, :) = permute( ...
            signal_model.doppler_noise_sigma_hz(sys) .* randn(num_epochs, sat_count), [3, 2, 1]);
        signal_model.cn0_noise_dbhz(sys, 1:sat_count, :) = permute( ...
            signal_model.cn0_noise_sigma_dbhz(sys) .* randn(num_epochs, sat_count), [3, 2, 1]);
        signal_model.slip_uniform(sys, 1:sat_count, :) = ...
            permute(rand(num_epochs, sat_count), [3, 2, 1]);
        signal_model.outage_uniform(sys, 1:sat_count, :) = ...
            permute(rand(num_epochs, sat_count), [3, 2, 1]);

        ambiguity_jumps = randi([-100, 100], num_epochs, sat_count);
        ambiguity_jumps(ambiguity_jumps == 0) = 1;
        signal_model.ambiguity_jump_cycles(sys, 1:sat_count, :) = ...
            permute(ambiguity_jumps, [3, 2, 1]);
    end

    observation_state.ambiguity_cycles = signal_model.initial_ambiguity_cycles;
    observation_state.last_visible_epoch = zeros(num_systems, max_sats);
    observation_state.lock_time_s = zeros(num_systems, max_sats);
end
