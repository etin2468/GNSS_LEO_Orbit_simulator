function [pseudorange_m, satXYZ_with_error, terms] = applyMeasurementErrors(error_model, sys_id, sat_id, epoch_idx, satXYZ, satVel, receiverXYZ, true_range_m)
    % APPLYMEASUREMENTERRORS Builds orbit, clock, DCB, and noise terms.
    %
    % The satellite orbit error is generated in the radial/along/cross-track
    % frame, then projected into the receiver line of sight through the
    % perturbed satellite position. It is only applied to the observation
    % when apply_orbit_error_to_observation is enabled; otherwise it belongs
    % to the RAP orbit product.

    if ~error_model.enabled
        satXYZ_with_error = satXYZ;
        terms = emptyTerms();
        pseudorange_m = true_range_m;
        return;
    end

    satXYZ_col = satXYZ(:);
    receiverXYZ_col = receiverXYZ(:);

    rac_error = squeeze(error_model.orbit_rac_m(sys_id, sat_id, epoch_idx, :));
    orbit_error_vec = racErrorToEcef(satXYZ, satVel, rac_error);

    satXYZ_with_error_col = satXYZ_col + orbit_error_vec;
    satXYZ_with_error = satXYZ_with_error_col.';

    range_with_orbit_error_m = norm(satXYZ_with_error_col - receiverXYZ_col);
    orbit_error_m = range_with_orbit_error_m - true_range_m;

    terms.orbit_error_m = orbit_error_m;
    if isfield(error_model, 'apply_orbit_error_to_observation') && ...
            error_model.apply_orbit_error_to_observation
        terms.applied_orbit_error_m = orbit_error_m;
    else
        terms.applied_orbit_error_m = 0;
    end
    terms.receiver_clock_error_m = error_model.receiver_clock_m(epoch_idx);
    terms.satellite_clock_error_m = error_model.satellite_clock_m(sys_id, sat_id, epoch_idx);
    terms.dcb_m = error_model.dcb_m(sys_id, sat_id);
    terms.noise_m = error_model.noise_m(sys_id, sat_id, epoch_idx);

    terms.total_error_m = terms.applied_orbit_error_m + ...
        terms.receiver_clock_error_m - ...
        terms.satellite_clock_error_m + ...
        terms.dcb_m + ...
        terms.noise_m;

    pseudorange_m = true_range_m + terms.total_error_m;
end

function terms = emptyTerms()
    terms.orbit_error_m = 0;
    terms.applied_orbit_error_m = 0;
    terms.receiver_clock_error_m = 0;
    terms.satellite_clock_error_m = 0;
    terms.dcb_m = 0;
    terms.noise_m = 0;
    terms.total_error_m = 0;
end
