function [pseudorange_m, satXYZ_with_error, terms] = applyMeasurementErrors(error_model, sys_id, sat_id, epoch_idx, satXYZ, satVel, receiverXYZ, true_range_m)
    % APPLYMEASUREMENTERRORS Adds orbit, clock, DCB, and noise terms.
    %
    % The satellite orbit error is generated in the radial/along/cross-track
    % frame, then projected into the receiver line of sight through the
    % perturbed satellite position.

    if ~error_model.enabled
        satXYZ_with_error = satXYZ;
        terms = emptyTerms();
        pseudorange_m = true_range_m;
        return;
    end

    satXYZ_col = satXYZ(:);
    satVel_col = satVel(:);
    receiverXYZ_col = receiverXYZ(:);

    radial_unit = satXYZ_col ./ norm(satXYZ_col);
    along_unit = satVel_col ./ norm(satVel_col);
    cross_unit = cross(radial_unit, along_unit);
    cross_norm = norm(cross_unit);

    if cross_norm < eps
        cross_unit = [0; 0; 1];
    else
        cross_unit = cross_unit ./ cross_norm;
    end

    along_unit = cross(cross_unit, radial_unit);
    along_unit = along_unit ./ norm(along_unit);

    rac_error = squeeze(error_model.orbit_rac_m(sys_id, sat_id, epoch_idx, :));
    orbit_error_vec = radial_unit .* rac_error(1) + ...
        along_unit .* rac_error(2) + ...
        cross_unit .* rac_error(3);

    satXYZ_with_error_col = satXYZ_col + orbit_error_vec;
    satXYZ_with_error = satXYZ_with_error_col.';

    range_with_orbit_error_m = norm(satXYZ_with_error_col - receiverXYZ_col);
    orbit_error_m = range_with_orbit_error_m - true_range_m;

    terms.orbit_error_m = orbit_error_m;
    terms.receiver_clock_error_m = error_model.receiver_clock_m(epoch_idx);
    terms.satellite_clock_error_m = error_model.satellite_clock_m(sys_id, sat_id, epoch_idx);
    terms.dcb_m = error_model.dcb_m(sys_id, sat_id);
    terms.noise_m = error_model.noise_m(sys_id, sat_id, epoch_idx);

    terms.total_error_m = terms.orbit_error_m + ...
        terms.receiver_clock_error_m - ...
        terms.satellite_clock_error_m + ...
        terms.dcb_m + ...
        terms.noise_m;

    pseudorange_m = true_range_m + terms.total_error_m;
end

function terms = emptyTerms()
    terms.orbit_error_m = 0;
    terms.receiver_clock_error_m = 0;
    terms.satellite_clock_error_m = 0;
    terms.dcb_m = 0;
    terms.noise_m = 0;
    terms.total_error_m = 0;
end
