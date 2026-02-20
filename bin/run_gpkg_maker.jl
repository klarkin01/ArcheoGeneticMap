"""
Command-line interface for converting archaeological CSV files to GeoPackage format.

Usage:
    julia run_gpkg_maker.jl <input.csv> [output.gpkg]

If output.gpkg is not specified, it is derived from the input filename.

Examples:
    julia run_gpkg_maker.jl samples.csv
    julia run_gpkg_maker.jl samples.csv output_data.gpkg
"""

include(joinpath(@__DIR__, "..", "src", "gpkg_maker.jl"))

function main(args)
    if length(args) == 2
        process_csv_to_geopackage(args[1], args[2])
    elseif length(args) == 1
        output_gpkg = replace(args[1], r"\.csv$"i => ".gpkg")
        process_csv_to_geopackage(args[1], output_gpkg)
    else
        println("Usage: julia run_gpkg_maker.jl <input.csv> [output.gpkg]")
        println("")
        println("Arguments:")
        println("  input.csv   - Path to the input CSV file")
        println("  output.gpkg - Path for the output GeoPackage (optional)")
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
