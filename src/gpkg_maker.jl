using CSV
using DataFrames
using ArchGDAL
using GeoDataFrames
using Printf

include(joinpath(@__DIR__, "..", "config", "maker_config.jl"))

"""
Structure to hold parsed sample data
"""
struct ArcheoSample
    sample_number::String
    sample_id::String
    latitude::Float64
    longitude::Float64
    y_haplogroup::String
    mtdna::String
    culture::String
    average_age_calbp::Union{Float64, Missing}
    y_haplotree::String
end

"""
Find the best matching column name from a list of candidates.
Tries exact matches first, then case-insensitive matches.
"""
function find_column(df::DataFrame, candidates::Vector{String})::Union{String, Nothing}
    df_cols = names(df)

    for candidate in candidates
        if candidate in df_cols
            return candidate
        end
    end

    for candidate in candidates
        for col in df_cols
            if lowercase(candidate) == lowercase(col)
                return col
            end
        end
    end

    return nothing
end

"""
Read a CSV file into a DataFrame, retrying with CP1252 encoding on failure.
"""
function read_csv_with_encoding(filepath::String)::DataFrame
    println("Reading CSV file: $filepath")
    df = try
        CSV.read(filepath, DataFrame)
    catch
        println("  Retrying with CP1252 encoding...")
        CSV.read(filepath, DataFrame, encoding="CP1252")
    end
    println("Found $(nrow(df)) rows and $(ncol(df)) columns")
    return df
end

"""
Resolve actual column names in a DataFrame against the DEFAULT_CONFIGS candidates.
Returns a NamedTuple of resolved column names (Nothing if optional columns not found).
Errors if required columns (sample_id, latitude, longitude) cannot be resolved.
"""
function resolve_columns(df::DataFrame)
    sample_id_col    = nothing
    latitude_col     = nothing
    longitude_col    = nothing
    y_haplogroup_col = nothing
    mtdna_col        = nothing
    culture_col      = nothing
    average_age_col  = nothing
    y_haplotree_col  = nothing

    for config in DEFAULT_CONFIGS
        sample_id_col    = find_column(df, config.sample_id_cols)
        latitude_col     = find_column(df, config.latitude_cols)
        longitude_col    = find_column(df, config.longitude_cols)
        y_haplogroup_col = find_column(df, config.y_haplogroup_cols)
        mtdna_col        = find_column(df, config.mtdna_cols)
        culture_col      = find_column(df, config.culture_cols)
        average_age_col  = find_column(df, config.average_age_cols)
        y_haplotree_col  = find_column(df, config.y_haplotree_cols)

        if !isnothing(sample_id_col) && !isnothing(latitude_col) && !isnothing(longitude_col)
            break
        end
    end

    isnothing(sample_id_col) && error("Could not find sample ID column. Available columns: $(names(df))")
    isnothing(latitude_col)  && error("Could not find latitude column. Available columns: $(names(df))")
    isnothing(longitude_col) && error("Could not find longitude column. Available columns: $(names(df))")

    cols = (
        sample_id    = sample_id_col,
        latitude     = latitude_col,
        longitude    = longitude_col,
        y_haplogroup = y_haplogroup_col,
        mtdna        = mtdna_col,
        culture      = culture_col,
        average_age  = average_age_col,
        y_haplotree  = y_haplotree_col
    )

    println("Using columns:")
    println("  Sample ID:    $(cols.sample_id)")
    println("  Latitude:     $(cols.latitude)")
    println("  Longitude:    $(cols.longitude)")
    println("  Y haplogroup: $(cols.y_haplogroup)")
    println("  mtDNA:        $(cols.mtdna)")
    println("  Culture:      $(cols.culture)")
    println("  Average age:  $(cols.average_age)")
    println("  Y haplotree:  $(cols.y_haplotree)")

    return cols
end

"""
Build a Vector{ArcheoSample} from a DataFrame and resolved column mapping.
Skips rows with missing required fields or invalid/out-of-range coordinates.
"""
function build_samples(df::DataFrame, cols)::Vector{ArcheoSample}
    samples = ArcheoSample[]
    sample_counter = 1

    for row in eachrow(df)
        if ismissing(row[cols.sample_id]) || ismissing(row[cols.latitude]) || ismissing(row[cols.longitude])
            continue
        end

        try
            lat = parse(Float64, string(row[cols.latitude]))
            lon = parse(Float64, string(row[cols.longitude]))

            if lat < -90 || lat > 90 || lon < -180 || lon > 180
                println("Warning: Invalid coordinates for sample $(row[cols.sample_id]): ($lat, $lon)")
                continue
            end

            y_hap   = isnothing(cols.y_haplogroup) || ismissing(row[cols.y_haplogroup]) ? "" : string(row[cols.y_haplogroup])
            mtdna   = isnothing(cols.mtdna)        || ismissing(row[cols.mtdna])        ? "" : string(row[cols.mtdna])
            culture = isnothing(cols.culture)      || ismissing(row[cols.culture])      ? "" : string(row[cols.culture])
            y_haplotree = isnothing(cols.y_haplotree) || ismissing(row[cols.y_haplotree]) ? "" : string(row[cols.y_haplotree])

            avg_age = missing
            if !isnothing(cols.average_age) && !ismissing(row[cols.average_age])
                try
                    avg_age = parse(Float64, string(row[cols.average_age]))
                catch
                    avg_age = missing
                end
            end

            push!(samples, ArcheoSample(
                @sprintf("%06d", sample_counter),
                string(row[cols.sample_id]),
                lat, lon,
                y_hap, mtdna, culture,
                avg_age,
                y_haplotree
            ))
            sample_counter += 1

        catch e
            println("Warning: Could not parse coordinates for sample $(row[cols.sample_id]): $e")
            continue
        end
    end

    println("Successfully parsed $(length(samples)) samples")
    return samples
end

"""
Parse a CSV file and extract archeogenetic sample data.
Orchestrates read_csv_with_encoding → resolve_columns → build_samples.
"""
function parse_archeo_csv(filepath::String)::Vector{ArcheoSample}
    df   = read_csv_with_encoding(filepath)
    cols = resolve_columns(df)
    return build_samples(df, cols)
end

"""
Convert a Vector{ArcheoSample} to a GeoDataFrame with point geometry.
"""
function samples_to_geodataframe(samples::Vector{ArcheoSample})
    isempty(samples) && error("No samples to convert")

    geometries = [ArchGDAL.createpoint(s.longitude, s.latitude) for s in samples]

    return GeoDataFrames.DataFrame(
        sample_number     = [s.sample_number     for s in samples],
        sample_id         = [s.sample_id         for s in samples],
        latitude          = [s.latitude          for s in samples],
        longitude         = [s.longitude         for s in samples],
        y_haplogroup      = [s.y_haplogroup      for s in samples],
        mtdna             = [s.mtdna             for s in samples],
        culture           = [s.culture           for s in samples],
        average_age_calbp = [s.average_age_calbp for s in samples],
        y_haplotree       = [s.y_haplotree       for s in samples],
        geometry          = geometries
    )
end

"""
Save a Vector{ArcheoSample} as a GeoPackage file in WGS84 (EPSG:4326).
"""
function save_as_geopackage(samples::Vector{ArcheoSample}, output_path::String)
    println("Creating GeoPackage: $output_path")
    gdf = samples_to_geodataframe(samples)
    GeoDataFrames.write(output_path, gdf, driver="GPKG", crs=GeoDataFrames.EPSG(4326))
    println("Successfully saved $(length(samples)) samples to $output_path")
end

"""
Parse a CSV file and write it as a GeoPackage. Top-level orchestrator.
"""
function process_csv_to_geopackage(input_csv::String, output_gpkg::String)
    try
        samples = parse_archeo_csv(input_csv)

        if isempty(samples)
            println("Warning: No valid samples found in the CSV file")
            return
        end

        save_as_geopackage(samples, output_gpkg)
        println("Processing complete!")

    catch e
        println("Error processing file: $e")
        rethrow(e)
    end
end

"""
Batch convert all CSV files in a directory to GeoPackages.
"""
function batch_process_csvs(input_directory::String, output_directory::String)
    isdir(output_directory) || mkpath(output_directory)

    csv_files = filter(f -> endswith(lowercase(f), ".csv"), readdir(input_directory))

    if isempty(csv_files)
        println("No CSV files found in $input_directory")
        return
    end

    println("Found $(length(csv_files)) CSV files to process")

    for csv_file in csv_files
        input_path = joinpath(input_directory, csv_file)
        output_path = joinpath(output_directory, replace(csv_file, r"\.csv$"i => ".gpkg"))

        println("\nProcessing: $csv_file")
        try
            process_csv_to_geopackage(input_path, output_path)
        catch e
            println("Failed to process $csv_file: $e")
            continue
        end
    end

    println("\nBatch processing complete!")
end
