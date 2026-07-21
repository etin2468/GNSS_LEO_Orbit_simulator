function [observation, observation_state] = applySignalObservationModel( ...
        signal_model, observation_state, error_model, sys_id, sat_id, ...
        epoch_idx, elevation_deg, true_range_m, range_rate_m_s, error_terms)
    % APPLYSIGNALOBSERVATIONMODEL Generates code, phase, Doppler, and C/N0.

    wavelength_m = signal_model.wavelength_m(sys_id);
    last_epoch = observation_state.last_visible_epoch(sys_id, sat_id);
    is_continuous = last_epoch > 0 && last_epoch == epoch_idx - 1;
    is_reacquisition = last_epoch > 0 && ~is_continuous;

    elevation_factor = max(0, 1 - sind(elevation_deg));
    outage_probability = signal_model.base_outage_probability + ...
        signal_model.low_elevation_outage_probability .* elevation_factor;
    is_outage = signal_model.enable_outages && ...
        signal_model.outage_uniform(sys_id, sat_id, epoch_idx) < outage_probability;

    if is_outage
        observation = emptyObservation(signal_model, sys_id);
        observation.lli = 1;
        observation.is_valid = false;
        observation_state.lock_time_s(sys_id, sat_id) = 0;
        return;
    end

    if is_reacquisition
        observation_state.ambiguity_cycles(sys_id, sat_id) = ...
            observation_state.ambiguity_cycles(sys_id, sat_id) + ...
            signal_model.ambiguity_jump_cycles(sys_id, sat_id, epoch_idx);
    end

    slip_probability = signal_model.base_slip_probability + ...
        signal_model.low_elevation_slip_probability .* elevation_factor;
    is_cycle_slip = signal_model.enable_cycle_slips && is_continuous && ...
        signal_model.slip_uniform(sys_id, sat_id, epoch_idx) < slip_probability;
    if is_cycle_slip
        observation_state.ambiguity_cycles(sys_id, sat_id) = ...
            observation_state.ambiguity_cycles(sys_id, sat_id) + ...
            signal_model.ambiguity_jump_cycles(sys_id, sat_id, epoch_idx);
    end

    if is_continuous && ~is_cycle_slip
        dt_s = signal_model.t_array(epoch_idx) - signal_model.t_array(epoch_idx - 1);
        observation_state.lock_time_s(sys_id, sat_id) = ...
            observation_state.lock_time_s(sys_id, sat_id) + dt_s;
    else
        observation_state.lock_time_s(sys_id, sat_id) = 0;
    end
    observation_state.last_visible_epoch(sys_id, sat_id) = epoch_idx;

    ambiguity_cycles = observation_state.ambiguity_cycles(sys_id, sat_id);
    common_range_m = true_range_m + error_terms.applied_orbit_error_m + ...
        error_terms.receiver_clock_error_m - error_terms.satellite_clock_error_m;

    code_m = common_range_m + error_terms.dcb_m + error_terms.noise_m;
    carrier_phase_m = common_range_m + signal_model.phase_bias_m(sys_id, sat_id) + ...
        wavelength_m .* ambiguity_cycles + ...
        signal_model.phase_noise_m(sys_id, sat_id, epoch_idx);

    receiver_clock_drift_m_s = clockDrift(error_model.receiver_clock_m, ...
        signal_model.t_array, epoch_idx);
    satellite_clock_series_m = squeeze(error_model.satellite_clock_m(sys_id, sat_id, :));
    satellite_clock_drift_m_s = clockDrift(satellite_clock_series_m, ...
        signal_model.t_array, epoch_idx);
    doppler_hz = -(range_rate_m_s + receiver_clock_drift_m_s - ...
        satellite_clock_drift_m_s) ./ wavelength_m + ...
        signal_model.doppler_noise_hz(sys_id, sat_id, epoch_idx);

    cn0_dbhz = signal_model.cn0_floor_dbhz + ...
        (signal_model.cn0_zenith_dbhz(sys_id) - signal_model.cn0_floor_dbhz) .* ...
        sqrt(max(0, sind(elevation_deg))) + ...
        signal_model.cn0_noise_dbhz(sys_id, sat_id, epoch_idx);

    observation.code_m = code_m;
    observation.carrier_phase_cycles = carrier_phase_m ./ wavelength_m;
    observation.doppler_hz = doppler_hz;
    observation.cn0_dbhz = cn0_dbhz;
    observation.lli = double(is_reacquisition || is_cycle_slip);
    observation.lock_time_s = observation_state.lock_time_s(sys_id, sat_id);
    observation.ambiguity_cycles = ambiguity_cycles;
    observation.frequency_hz = signal_model.frequency_hz(sys_id);
    observation.wavelength_m = wavelength_m;
    observation.phase_bias_m = signal_model.phase_bias_m(sys_id, sat_id);
    observation.phase_noise_m = signal_model.phase_noise_m(sys_id, sat_id, epoch_idx);
    observation.is_valid = true;
end

function drift_m_s = clockDrift(clock_m, t_array, epoch_idx)
    if numel(clock_m) < 2
        drift_m_s = 0;
    elseif epoch_idx == 1
        drift_m_s = (clock_m(2) - clock_m(1)) ./ (t_array(2) - t_array(1));
    else
        drift_m_s = (clock_m(epoch_idx) - clock_m(epoch_idx - 1)) ./ ...
            (t_array(epoch_idx) - t_array(epoch_idx - 1));
    end
end

function observation = emptyObservation(signal_model, sys_id)
    observation.code_m = nan;
    observation.carrier_phase_cycles = nan;
    observation.doppler_hz = nan;
    observation.cn0_dbhz = nan;
    observation.lli = 0;
    observation.lock_time_s = 0;
    observation.ambiguity_cycles = nan;
    observation.frequency_hz = signal_model.frequency_hz(sys_id);
    observation.wavelength_m = signal_model.wavelength_m(sys_id);
    observation.phase_bias_m = nan;
    observation.phase_noise_m = nan;
    observation.is_valid = false;
end
