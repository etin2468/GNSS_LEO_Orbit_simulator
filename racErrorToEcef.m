function error_ecef_m = racErrorToEcef(satXYZ, satVel, rac_error_m)
    % RACERRORTOECEF Converts radial/along/cross-track errors to ECEF.

    position = satXYZ(:);
    velocity = satVel(:);
    rac_error_m = rac_error_m(:);

    radial_unit = position ./ norm(position);
    along_unit = velocity - radial_unit .* dot(velocity, radial_unit);
    if norm(along_unit) < eps
        error('GPSsimulator:InvalidOrbitFrame', ...
            'Cannot construct the along-track direction from this state.');
    end
    along_unit = along_unit ./ norm(along_unit);

    cross_unit = cross(radial_unit, along_unit);
    cross_unit = cross_unit ./ norm(cross_unit);

    error_ecef_m = radial_unit .* rac_error_m(1) + ...
        along_unit .* rac_error_m(2) + cross_unit .* rac_error_m(3);
end
