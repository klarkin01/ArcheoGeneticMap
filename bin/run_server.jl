#!/usr/bin/env julia
"""
ArcheoGeneticMap Server - Command Line Interface

Usage:
    julia run_server.jl <geopackage_file> [port]

Arguments:
    geopackage_file  Path to the GeoPackage file to serve
    port             Port number (default: 8000)

Examples:
    julia run_server.jl samples.gpkg
    julia run_server.jl data/ancient_dna.gpkg 8080
"""

# Add the src directory to the load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using ArcheoGeneticMap

function main()
    # Parse command line arguments
    if length(ARGS) < 1
        println("""
ArcheoGeneticMap Server - Archaeological Sample Visualization

Usage:
    julia run_server.jl <geopackage_file> [port]

Arguments:
    geopackage_file  Path to the GeoPackage file to serve
    port             Port number (default: 8000)

Examples:
    julia run_server.jl samples.gpkg
    julia run_server.jl data/ancient_dna.gpkg 8080

Tile variants available at:
    /       - OpenStreetMap (default)
    /topo   - OpenTopoMap  
    /humanitarian - Humanitarian OSM
""")
        exit(1)
    end
    
    gpkg_file = ARGS[1]
    port = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 8000
    
    # Verify file exists
    if !isfile(gpkg_file)
        println("Error: File not found: $gpkg_file")
        exit(1)
    end
    
    # Start the server
    println("=" ^ 50)
    println("ArcheoGeneticMap Server")
    println("=" ^ 50)
    serve_map(gpkg_file, port=port)
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
