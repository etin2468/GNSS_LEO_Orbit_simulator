function summary = writeSp3Product(filename, product_table, metadata)
    % WRITESP3PRODUCT Writes a mixed-system SP3-d position/clock product.

    required_variables = {'Time_s', 'System', 'Sat_ID', 'Satellite_ID', ...
        'X_m', 'Y_m', 'Z_m', 'Clock_s'};
    if ~all(ismember(required_variables, product_table.Properties.VariableNames))
        error('GPSsimulator:InvalidSP3Table', ...
            'The product table does not contain all required variables.');
    end

    epoch_offsets = unique(product_table.Time_s, 'sorted');
    satellite_ids = unique(product_table.Satellite_ID, 'stable');
    num_epochs = numel(epoch_offsets);
    num_sats = numel(satellite_ids);
    expected_rows = num_epochs * num_sats;
    if height(product_table) ~= expected_rows
        error('GPSsimulator:IncompleteSP3Product', ...
            'SP3 requires one record per listed satellite at every epoch.');
    end

    fid = fopen(filename, 'w');
    if fid < 0
        error('GPSsimulator:SP3OpenFailed', 'Cannot open %s for writing.', filename);
    end
    close_file = onCleanup(@() fclose(fid));

    start_time = metadata.start_time;
    start_parts = datevec(start_time);
    gps_epoch = datetime(1980, 1, 6, 0, 0, 0);
    gps_seconds = seconds(start_time - gps_epoch);
    gps_week = floor(gps_seconds / 604800);
    gps_sow = mod(gps_seconds, 604800);
    mjd_value = days(start_time - datetime(1858, 11, 17, 0, 0, 0));
    mjd_integer = floor(mjd_value);
    mjd_fraction = mjd_value - mjd_integer;

    first_line = sprintf(['#dP%4d %2d %2d %2d %2d %11.8f %7d ', ...
        '%-5s %-5s %-3s %-4s'], start_parts(1), start_parts(2), ...
        start_parts(3), start_parts(4), start_parts(5), start_parts(6), ...
        num_epochs, metadata.data_used, metadata.coordinate_system, ...
        metadata.orbit_type, metadata.agency);
    writeLine(fid, first_line);
    second_line = sprintf('## %4d %15.8f %14.8f %5d %15.13f', ...
        gps_week, gps_sow, metadata.interval_s, mjd_integer, mjd_fraction);
    writeLine(fid, second_line);

    satellite_header_lines = max(5, ceil(num_sats / 17));
    for line_idx = 1:satellite_header_lines
        if line_idx == 1
            line = sprintf('+  %3d   ', num_sats);
        else
            line = '+        ';
        end
        for slot = 1:17
            satellite_index = (line_idx - 1) * 17 + slot;
            if satellite_index <= num_sats
                line = [line, char(satellite_ids(satellite_index))]; %#ok<AGROW>
            else
                line = [line, '  0']; %#ok<AGROW>
            end
        end
        writeLine(fid, line);
    end

    for line_idx = 1:satellite_header_lines
        line = '++       ';
        for slot = 1:17
            satellite_index = (line_idx - 1) * 17 + slot;
            if satellite_index <= num_sats
                sat_code = char(satellite_ids(satellite_index));
                exponent = metadata.accuracy_exponents( ...
                    systemCodeIndex(sat_code(1)));
            else
                exponent = 0;
            end
            line = [line, sprintf('%3d', exponent)]; %#ok<AGROW>
        end
        writeLine(fid, line);
    end

    writeLine(fid, '%c M  cc GPS ccc cccc cccc cccc cccc ccccc ccccc ccccc ccccc');
    writeLine(fid, '%c cc cc ccc ccc cccc cccc cccc cccc ccccc ccccc ccccc ccccc');
    writeLine(fid, '%f  1.2500000  1.025000000  0.00000000000  0.000000000000000');
    writeLine(fid, '%f  0.0000000  0.000000000  0.00000000000  0.000000000000000');
    writeLine(fid, '%i    0    0    0    0      0      0      0      0         0');
    writeLine(fid, '%i    0    0    0    0      0      0      0      0         0');

    comments = string(metadata.comments);
    while numel(comments) < 4
        comments(end + 1) = ""; %#ok<AGROW>
    end
    for comment_idx = 1:numel(comments)
        comment = char(comments(comment_idx));
        writeLine(fid, ['/* ', comment(1:min(numel(comment), 77))]);
    end

    for epoch_idx = 1:num_epochs
        epoch_offset = epoch_offsets(epoch_idx);
        epoch_time = start_time + seconds(epoch_offset);
        epoch_parts = datevec(epoch_time);
        epoch_line = sprintf('*  %4d %2d %2d %2d %2d %11.8f', ...
            epoch_parts(1), epoch_parts(2), epoch_parts(3), epoch_parts(4), ...
            epoch_parts(5), epoch_parts(6));
        writeLine(fid, epoch_line);

        epoch_rows = product_table(product_table.Time_s == epoch_offset, :);
        for sat_idx = 1:num_sats
            row = epoch_rows(epoch_rows.Satellite_ID == satellite_ids(sat_idx), :);
            if height(row) ~= 1
                error('GPSsimulator:InvalidSP3Epoch', ...
                    'Satellite %s is missing or duplicated at t=%g s.', ...
                    satellite_ids(sat_idx), epoch_offset);
            end
            position_line = sprintf('P%s%14.6f%14.6f%14.6f%14.6f', ...
                char(row.Satellite_ID), row.X_m / 1000, row.Y_m / 1000, ...
                row.Z_m / 1000, row.Clock_s * 1e6);
            writeLine(fid, position_line);
        end
    end
    fprintf(fid, 'EOF\n');

    summary.filename = string(filename);
    summary.solution_type = string(metadata.solution_type);
    summary.epochs_written = num_epochs;
    summary.satellites_written = num_sats;
    summary.position_clock_records_written = expected_rows;
    summary.start_time = start_time;
    summary.interval_s = metadata.interval_s;
end

function writeLine(fid, line)
    if numel(line) > 80
        error('GPSsimulator:SP3LineTooLong', ...
            'SP3 line is %d characters long: %s', numel(line), line);
    end
    fprintf(fid, '%-80s\n', line);
end

function index = systemCodeIndex(code)
    switch code
        case 'G'
            index = 1;
        case 'R'
            index = 2;
        case 'E'
            index = 3;
        case 'L'
            index = 4;
        otherwise
            error('GPSsimulator:UnsupportedSP3System', ...
                'Unsupported SP3 system code: %s', code);
    end
end
