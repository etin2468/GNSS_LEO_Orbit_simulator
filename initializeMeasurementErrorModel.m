function error_model = initializeMeasurementErrorModel(t_array, sats_per_system)
    % INITIALIZEMEASUREMENTERRORMODEL Builds reproducible GNSS/LEO error states.
    %
    % Error terms are expressed in meters so they can be added directly to
    % the geometric range when generating pseudorange-like measurements.

    rng(42, "twister");

    error_model.enabled = true;
    error_model.seed = 42;
    error_model.system_names = ["GPS", "GLONASS", "Galileo", "LEO"];
    % Orbit errors describe the RAP orbit product. Keep this false when the
    % observations will be evaluated with FIN/RAP SP3 products.
    error_model.apply_orbit_error_to_observation = false;

    % 1-sigma values by system: GPS, GLONASS, Galileo, LEO.
    error_model.orbit_radial_sigma_m = [0.5, 0.8, 0.5, 3.0];
    error_model.orbit_along_sigma_m = [1.2, 1.5, 1.0, 8.0];
    error_model.orbit_cross_sigma_m = [0.8, 1.0, 0.8, 5.0];
    error_model.orbit_random_walk_sigma_m = [0.02, 0.03, 0.02, 0.12];

    error_model.receiver_clock_initial_m = 25.0;
    error_model.receiver_clock_random_walk_sigma_m = 0.15;
    error_model.satellite_clock_bias_sigma_m = [1.0, 1.5, 1.0, 2.5];
    error_model.satellite_clock_random_walk_sigma_m = [0.04, 0.05, 0.04, 0.10];

    error_model.dcb_sigma_ns = [0.8, 1.2, 0.8, 1.5];
    error_model.noise_sigma_m = [0.5, 0.7, 0.5, 1.5];

    c_light = 299792458;
    num_systems = numel(sats_per_system);
    num_epochs = numel(t_array);
    max_sats = max(sats_per_system);

    error_model.receiver_clock_m = error_model.receiver_clock_initial_m + ...
        cumsum(error_model.receiver_clock_random_walk_sigma_m .* randn(num_epochs, 1));

    error_model.satellite_clock_m = nan(num_systems, max_sats, num_epochs);
    error_model.dcb_m = nan(num_systems, max_sats);
    error_model.noise_m = nan(num_systems, max_sats, num_epochs);
    error_model.orbit_rac_m = nan(num_systems, max_sats, num_epochs, 3);

    for sys = 1:num_systems
        sat_count = sats_per_system(sys);

        sat_clock_initial = error_model.satellite_clock_bias_sigma_m(sys) .* randn(1, sat_count);
        sat_clock_walk = cumsum(error_model.satellite_clock_random_walk_sigma_m(sys) .* ...
            randn(num_epochs, sat_count), 1);
        error_model.satellite_clock_m(sys, 1:sat_count, :) = ...
            permute(sat_clock_initial + sat_clock_walk, [3, 2, 1]);

        dcb_ns = error_model.dcb_sigma_ns(sys) .* randn(1, sat_count);
        error_model.dcb_m(sys, 1:sat_count) = c_light .* dcb_ns .* 1e-9;

        error_model.noise_m(sys, 1:sat_count, :) = ...
            permute(error_model.noise_sigma_m(sys) .* randn(num_epochs, sat_count), [3, 2, 1]);

        radial = error_model.orbit_radial_sigma_m(sys) .* randn(1, sat_count);
        along = error_model.orbit_along_sigma_m(sys) .* randn(1, sat_count);
        cross = error_model.orbit_cross_sigma_m(sys) .* randn(1, sat_count);

        for epoch = 1:num_epochs
            if epoch > 1
                radial = radial + error_model.orbit_random_walk_sigma_m(sys) .* randn(1, sat_count);
                along = along + error_model.orbit_random_walk_sigma_m(sys) .* randn(1, sat_count);
                cross = cross + error_model.orbit_random_walk_sigma_m(sys) .* randn(1, sat_count);
            end

            error_model.orbit_rac_m(sys, 1:sat_count, epoch, 1) = radial;
            error_model.orbit_rac_m(sys, 1:sat_count, epoch, 2) = along;
            error_model.orbit_rac_m(sys, 1:sat_count, epoch, 3) = cross;
        end
    end
end
