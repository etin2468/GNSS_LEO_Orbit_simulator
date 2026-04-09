function [x, y, z, vx, vy, vz] = kepler2ecef(a, e, i, RAAN0, omega, true_anomaly, t)
    % KEPLER2ECEF Computes the ECEF coordinates and velocities from Keplerian elements.
    %
    % Inputs:
    %   a: Semi-major axis [m]
    %   e: Eccentricity
    %   i: Inclination [rad]
    %   RAAN0: Right Ascension of Ascending Node at reference epoch [rad]
    %   omega: Argument of perigee [rad]
    %   true_anomaly: True anomaly [rad] (can be array)
    %   t: Time since epoch [s]
    %
    % Outputs:
    %   [x, y, z]: ECEF coordinates in meters 
    %   [vx, vy, vz]: ECEF velocities in meters/second (optional)
    
    GM = 3.986004418e14; % Earth's standard gravitational parameter [m^3/s^2]
    omega_e = 7.2921151467e-5; % Earth rotation rate [rad/s]
    
    % Radius in orbital plane
    p = a * (1 - e^2);
    r = p ./ (1 + e .* cos(true_anomaly));
    
    % Position in orbital plane
    xp = r .* cos(true_anomaly);
    yp = r .* sin(true_anomaly);
    % zp = 0
    
    % The RAAN in ECEF frame rotates with the Earth
    RAAN = RAAN0 - omega_e * t;
    
    % Trigonometric components
    cw = cos(omega); sw = sin(omega);
    ci = cos(i);     si = sin(i);
    cO = cos(RAAN);  sO = sin(RAAN);
    
    % Combined rotation matrix components from orbital plane to ECEF
    % R = Rz(-RAAN) * Rx(-i) * Rz(-omega)
    R11 =  cO.*cw - sO.*ci.*sw;
    R12 = -cO.*sw - sO.*ci.*cw;
    R13 =  sO.*si;
    
    R21 =  sO.*cw + cO.*ci.*sw;
    R22 = -sO.*sw + cO.*ci.*cw;
    R23 = -cO.*si;
    
    R31 =  si.*sw;
    R32 =  si.*cw;
    R33 =  ci;
    
    % Evaluate ECEF positional coordinates
    x = xp .* R11 + yp .* R12;
    y = xp .* R21 + yp .* R22;
    z = xp .* R31 + yp .* R32;
    
    % Output velocities if requested
    if nargout > 3
        % Specific angular momentum
        h = sqrt(GM * p);
        
        % Velocity components in the 2D orbital plane
        vx_p = -(GM / h) .* sin(true_anomaly);
        vy_p =  (GM / h) .* (e + cos(true_anomaly));
        
        % Rotate velocities to inertial framework (ECI)
        vx_eci = vx_p .* R11 + vy_p .* R12;
        vy_eci = vx_p .* R21 + vy_p .* R22;
        vz_eci = vx_p .* R31 + vy_p .* R32;
        
        % Convert ECI velocity to ECEF velocity (v_ECEF = v_ECI - omega_e x r_ECEF)
        vx = vx_eci + omega_e .* y;
        vy = vy_eci - omega_e .* x;
        vz = vz_eci;
    end
end
