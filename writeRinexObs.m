function summary = writeRinexObs(filename, observations, metadata)
    % WRITERINEXOBS Writes simulated observations as a RINEX 3.05 OBS file.
    %
    % Standard RINEX systems supported by this simulator are GPS, GLONASS,
    % and Galileo. LEO observations remain in T_obs because RINEX 3.05 has
    % no generic constellation identifier for a custom LEO system.

    arguments
        filename {mustBeTextScalar}
        observations table
        metadata struct
    end

    metadata = applyMetadataDefaults(metadata, observations);
    validateObservations(observations);

    supported_systems = [1, 2, 3];
    output_rows = observations(ismember(observations.System, supported_systems) & ...
        logical(observations.Is_Valid), :);
    output_rows = sortrows(output_rows, {'Time_s', 'System', 'Sat_ID'});

    if isempty(output_rows)
        error('GPSsimulator:NoRinexObservations', ...
            'No valid GPS, GLONASS, or Galileo observations are available.');
    end

    [output_folder, ~, ~] = fileparts(char(filename));
    if ~isempty(output_folder) && ~isfolder(output_folder)
        error('GPSsimulator:RinexFolderMissing', ...
            'Output folder does not exist: %s', output_folder);
    end

    fid = fopen(filename, 'wt');
    if fid < 0
        error('GPSsimulator:RinexOpenFailed', ...
            'Unable to open RINEX output file: %s', filename);
    end
    cleanup = onCleanup(@() fclose(fid));

    system_ids = unique(output_rows.System, 'stable').';
    system_chars = ['G', 'R', 'E'];
    system_names = ["GPS", "GLONASS", "Galileo"];
    if isscalar(system_ids)
        file_system = system_chars(system_ids);
    else
        file_system = 'M';
    end

    writeHeaderLine(fid, sprintf('%9.2f%11s%-20s%-20s', ...
        3.05, '', 'OBSERVATION DATA', file_system), 'RINEX VERSION / TYPE');
    creation_time = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyyMMdd HHmmss ''UTC'''));
    writeHeaderLine(fid, sprintf('%-20.20s%-20.20s%-20.20s', ...
        metadata.program, metadata.run_by, creation_time), 'PGM / RUN BY / DATE');
    writeHeaderLine(fid, metadata.marker_name, 'MARKER NAME');
    writeHeaderLine(fid, metadata.marker_number, 'MARKER NUMBER');
    writeHeaderLine(fid, 'GEODETIC', 'MARKER TYPE');
    writeHeaderLine(fid, sprintf('%-20.20s%-40.40s', ...
        metadata.observer, metadata.agency), 'OBSERVER / AGENCY');
    writeHeaderLine(fid, sprintf('%-20.20s%-20.20s%-20.20s', ...
        metadata.receiver_number, metadata.receiver_type, metadata.receiver_version), ...
        'REC # / TYPE / VERS');
    writeHeaderLine(fid, sprintf('%-20.20s%-40.40s', ...
        metadata.antenna_number, metadata.antenna_type), 'ANT # / TYPE');
    writeHeaderLine(fid, sprintf('%14.4f%14.4f%14.4f', ...
        metadata.approx_position_xyz), 'APPROX POSITION XYZ');
    writeHeaderLine(fid, sprintf('%14.4f%14.4f%14.4f', ...
        metadata.antenna_delta_hen), 'ANTENNA: DELTA H/E/N');

    for sys_id = system_ids
        tracking_code = trackingCodeForSystem(output_rows, sys_id);
        obs_types = ["C", "L", "D", "S"] + tracking_code;
        content = sprintf('%c  %3d', system_chars(sys_id), numel(obs_types));
        for obs_type = obs_types
            content = [content, sprintf(' %-3s', obs_type)]; %#ok<AGROW>
        end
        writeHeaderLine(fid, content, 'SYS / # / OBS TYPES');
    end

    writeHeaderLine(fid, 'DBHZ', 'SIGNAL STRENGTH UNIT');
    writeHeaderLine(fid, sprintf('%10.3f', metadata.interval_s), 'INTERVAL');
    first_time = metadata.start_time + seconds(min(output_rows.Time_s));
    writeTimeHeader(fid, first_time, metadata.time_system, 'TIME OF FIRST OBS');
    last_time = metadata.start_time + seconds(max(output_rows.Time_s));
    writeTimeHeader(fid, last_time, metadata.time_system, 'TIME OF LAST OBS');

    for sys_id = system_ids
        tracking_code = trackingCodeForSystem(output_rows, sys_id);
        writeHeaderLine(fid, sprintf('%c L%s', system_chars(sys_id), tracking_code), ...
            'SYS / PHASE SHIFT');
    end

    if any(system_ids == 2)
        glonass_ids = unique(output_rows.Sat_ID(output_rows.System == 2)).';
        writeGlonassSlots(fid, glonass_ids);
        writeHeaderLine(fid, '', 'GLONASS COD/PHS/BIS');
    end

    writeHeaderLine(fid, sprintf('%-60.60s', ...
        'Simulated observations; LEO rows are not included.'), 'COMMENT');
    writeHeaderLine(fid, '', 'END OF HEADER');

    epoch_times = unique(output_rows.Time_s, 'stable');
    written_observations = 0;
    for epoch_index = 1:numel(epoch_times)
        epoch_s = epoch_times(epoch_index);
        epoch_rows = output_rows(output_rows.Time_s == epoch_s, :);
        epoch_time = metadata.start_time + seconds(epoch_s);
        writeEpochRecord(fid, epoch_time, height(epoch_rows));

        for row_index = 1:height(epoch_rows)
            row = epoch_rows(row_index, :);
            sys_char = system_chars(row.System);
            ssi = min(max(fix(row.CN0_dBHz ./ 6), 1), 9);

            code_field = observationField(row.Code_m, [], []);
            phase_field = observationField(row.Carrier_Phase_cycles, row.LLI, ssi);
            doppler_field = observationField(row.Doppler_Hz, [], []);
            strength_field = observationField(row.CN0_dBHz, [], []);
            fprintf(fid, '%c%02d%s%s%s%s\n', sys_char, row.Sat_ID, ...
                code_field, phase_field, doppler_field, strength_field);
            written_observations = written_observations + 1;
        end
    end

    summary.filename = string(filename);
    summary.rinex_version = 3.05;
    summary.epochs_written = numel(epoch_times);
    summary.observations_written = written_observations;
    summary.systems_written = system_names(system_ids);
    summary.leo_rows_skipped = sum(observations.System == 4);
    summary.invalid_rows_skipped = sum(~logical(observations.Is_Valid) & ...
        ismember(observations.System, supported_systems));
end

function metadata = applyMetadataDefaults(metadata, observations)
    defaults.program = 'GNSS_LEO_SIM';
    defaults.run_by = 'NCU';
    defaults.marker_name = 'NCU_SIM';
    defaults.marker_number = 'SIM0001';
    defaults.observer = 'SIMULATOR';
    defaults.agency = 'NCU';
    defaults.receiver_number = 'SIM0001';
    defaults.receiver_type = 'SOFTWARE RECEIVER';
    defaults.receiver_version = '1.0';
    defaults.antenna_number = 'SIM0001';
    defaults.antenna_type = 'SIMULATED';
    defaults.antenna_delta_hen = [0, 0, 0];
    defaults.time_system = 'GPS';
    defaults.interval_s = median(diff(unique(observations.Time_s)));

    default_names = fieldnames(defaults);
    for index = 1:numel(default_names)
        name = default_names{index};
        if ~isfield(metadata, name) || isempty(metadata.(name))
            metadata.(name) = defaults.(name);
        end
    end

    required_names = {'start_time', 'approx_position_xyz'};
    for index = 1:numel(required_names)
        name = required_names{index};
        if ~isfield(metadata, name) || isempty(metadata.(name))
            error('GPSsimulator:MissingRinexMetadata', ...
                'RINEX metadata.%s is required.', name);
        end
    end

    metadata.approx_position_xyz = reshape(metadata.approx_position_xyz, 1, 3);
    metadata.antenna_delta_hen = reshape(metadata.antenna_delta_hen, 1, 3);
end

function validateObservations(observations)
    required_variables = {'Time_s', 'System', 'Sat_ID', 'Code_m', ...
        'Carrier_Phase_cycles', 'Doppler_Hz', 'CN0_dBHz', 'LLI', ...
        'Is_Valid', 'RINEX_Tracking_Code'};
    missing_variables = setdiff(required_variables, observations.Properties.VariableNames);
    if ~isempty(missing_variables)
        error('GPSsimulator:MissingObservationColumns', ...
            'T_obs is missing required columns: %s', strjoin(missing_variables, ', '));
    end

    valid_rows = logical(observations.Is_Valid) & ismember(observations.System, [1, 2, 3]);
    numeric_values = [observations.Time_s(valid_rows), observations.Sat_ID(valid_rows), ...
        observations.Code_m(valid_rows), observations.Carrier_Phase_cycles(valid_rows), ...
        observations.Doppler_Hz(valid_rows), observations.CN0_dBHz(valid_rows), ...
        observations.LLI(valid_rows)];
    if any(~isfinite(numeric_values), 'all')
        error('GPSsimulator:InvalidRinexObservation', ...
            'Valid RINEX observation rows must contain finite numeric values.');
    end
    if any(observations.Sat_ID(valid_rows) < 1 | observations.Sat_ID(valid_rows) > 99)
        error('GPSsimulator:InvalidSatelliteId', ...
            'RINEX 3.05 satellite IDs must be between 1 and 99.');
    end
end

function tracking_code = trackingCodeForSystem(observations, sys_id)
    codes = unique(string(observations.RINEX_Tracking_Code(observations.System == sys_id)));
    if numel(codes) ~= 1 || strlength(codes) ~= 2
        error('GPSsimulator:AmbiguousTrackingCode', ...
            'System %d must have exactly one two-character tracking code.', sys_id);
    end
    tracking_code = codes;
end

function writeHeaderLine(fid, content, label)
    content = char(string(content));
    label = char(string(label));
    content = content(1:min(numel(content), 60));
    label = label(1:min(numel(label), 20));
    fprintf(fid, '%-60s%-20s\n', content, label);
end

function writeTimeHeader(fid, epoch_time, time_system, label)
    time_parts = datevec(epoch_time);
    content = sprintf('%6d%6d%6d%6d%6d%13.7f%5s%-3s', ...
        time_parts(1), time_parts(2), time_parts(3), time_parts(4), ...
        time_parts(5), time_parts(6), '', time_system);
    writeHeaderLine(fid, content, label);
end

function writeGlonassSlots(fid, satellite_ids)
    for first_index = 1:8:numel(satellite_ids)
        last_index = min(first_index + 7, numel(satellite_ids));
        if first_index == 1
            content = sprintf('%3d ', numel(satellite_ids));
        else
            content = '    ';
        end
        for sat_id = satellite_ids(first_index:last_index)
            content = [content, sprintf('R%02d %2d ', sat_id, 0)]; %#ok<AGROW>
        end
        writeHeaderLine(fid, content, 'GLONASS SLOT / FRQ #');
    end
end

function writeEpochRecord(fid, epoch_time, satellite_count)
    time_parts = datevec(epoch_time);
    fprintf(fid, '> %4d %02d %02d %02d %02d%11.7f  0%3d\n', ...
        time_parts(1), time_parts(2), time_parts(3), time_parts(4), ...
        time_parts(5), time_parts(6), satellite_count);
end

function field = observationField(value, lli, ssi)
    if isempty(value) || ~isfinite(value)
        field = repmat(' ', 1, 16);
        return;
    end

    if abs(value) >= 1e10
        error('GPSsimulator:RinexFieldOverflow', ...
            'Observation value %.3f does not fit in RINEX F14.3 format.', value);
    end

    if isempty(lli) || lli == 0
        lli_char = ' ';
    else
        lli_char = sprintf('%1d', min(max(round(lli), 0), 7));
    end
    if isempty(ssi) || ssi == 0
        ssi_char = ' ';
    else
        ssi_char = sprintf('%1d', min(max(round(ssi), 1), 9));
    end
    field = sprintf('%14.3f%c%c', value, lli_char, ssi_char);
end
