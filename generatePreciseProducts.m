function [T_fin, T_rap, product_model] = generatePreciseProducts( ...
        t_array, orbit_config, error_model)
    % GENERATEPRECISEPRODUCTS Builds truth-like FIN and degraded RAP states.

    % FIN contains the simulated truth orbit and actual satellite clock.
    % RAP contains the same physical clock plus an independent product clock
    % estimation error, and the configured RAC orbit product error.

    c_light = 299792458;
    num_systems = numel(orbit_config.sats_per_system);
    num_epochs = numel(t_array);
    total_sats = sum(orbit_config.sats_per_system);
    num_rows = num_epochs * total_sats;

    previous_rng = rng;
    restore_rng = onCleanup(@() rng(previous_rng));
    rng(27182, "twister");

    product_model.seed = 27182;
    product_model.system_names = error_model.system_names;
    product_model.rapid_clock_initial_sigma_m = [0.15, 0.25, 0.15, 0.80];
    product_model.rapid_clock_random_walk_sigma_m = [0.02, 0.03, 0.02, 0.10];
    product_model.rapid_clock_error_m = nan(num_systems, ...
        max(orbit_config.sats_per_system), num_epochs);

    for sys = 1:num_systems
        sat_count = orbit_config.sats_per_system(sys);
        initial_error = product_model.rapid_clock_initial_sigma_m(sys) .* ...
            randn(1, sat_count);
        random_walk = cumsum(product_model.rapid_clock_random_walk_sigma_m(sys) .* ...
            randn(num_epochs, sat_count), 1);
        product_model.rapid_clock_error_m(sys, 1:sat_count, :) = ...
            permute(initial_error + random_walk, [3, 2, 1]);
    end

    time_s = zeros(num_rows, 1);
    system_id = zeros(num_rows, 1);
    sat_id = zeros(num_rows, 1);
    satellite_id = strings(num_rows, 1);
    fin_xyz_m = zeros(num_rows, 3);
    rap_xyz_m = zeros(num_rows, 3);
    fin_clock_s = zeros(num_rows, 1);
    rap_clock_s = zeros(num_rows, 1);

    row = 0;
    system_codes = ["G", "R", "E", "L"];
    for epoch_idx = 1:num_epochs
        t_sim = t_array(epoch_idx);
        for sys = 1:num_systems
            semimajor_axis_m = orbit_config.semimajor_axis_m(sys);
            eccentricity = orbit_config.eccentricity(sys);
            inclination_rad = orbit_config.inclination_rad(sys);
            plane_count = orbit_config.planes(sys);
            sats_per_plane = orbit_config.sats_per_plane(sys);
            mean_motion_rad_s = orbit_config.mean_motion_rad_s(sys);

            current_sat_id = 0;
            for plane = 1:plane_count
                raan_rad = (plane - 1) * (2*pi / plane_count);
                for sat_in_plane = 1:sats_per_plane
                    current_sat_id = current_sat_id + 1;
                    true_anomaly_rad = (sat_in_plane - 1) * ...
                        (2*pi / sats_per_plane) + mean_motion_rad_s * t_sim;
                    [x, y, z, vx, vy, vz] = kepler2ecef(semimajor_axis_m, ...
                        eccentricity, inclination_rad, raan_rad, 0, ...
                        true_anomaly_rad, t_sim);

                    truth_xyz = [x, y, z];
                    truth_velocity = [vx, vy, vz];
                    rac_error = squeeze(error_model.orbit_rac_m( ...
                        sys, current_sat_id, epoch_idx, :));
                    orbit_error_ecef = racErrorToEcef( ...
                        truth_xyz, truth_velocity, rac_error).';
                    actual_clock_m = error_model.satellite_clock_m( ...
                        sys, current_sat_id, epoch_idx);
                    rapid_clock_error_m = product_model.rapid_clock_error_m( ...
                        sys, current_sat_id, epoch_idx);

                    row = row + 1;
                    time_s(row) = t_sim;
                    system_id(row) = sys;
                    sat_id(row) = current_sat_id;
                    satellite_id(row) = system_codes(sys) + ...
                        compose("%02d", current_sat_id);
                    fin_xyz_m(row, :) = truth_xyz;
                    rap_xyz_m(row, :) = truth_xyz + orbit_error_ecef;
                    fin_clock_s(row) = actual_clock_m / c_light;
                    rap_clock_s(row) = ...
                        (actual_clock_m + rapid_clock_error_m) / c_light;
                end
            end
        end
    end

    T_fin = table(time_s, system_id, sat_id, satellite_id, ...
        fin_xyz_m(:, 1), fin_xyz_m(:, 2), fin_xyz_m(:, 3), fin_clock_s, ...
        'VariableNames', {'Time_s', 'System', 'Sat_ID', 'Satellite_ID', ...
        'X_m', 'Y_m', 'Z_m', 'Clock_s'});
    T_rap = table(time_s, system_id, sat_id, satellite_id, ...
        rap_xyz_m(:, 1), rap_xyz_m(:, 2), rap_xyz_m(:, 3), rap_clock_s, ...
        'VariableNames', {'Time_s', 'System', 'Sat_ID', 'Satellite_ID', ...
        'X_m', 'Y_m', 'Z_m', 'Clock_s'});
end
