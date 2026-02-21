"""
    ArcheoGeneticMap.Server

Web server routes and startup using Genie.
"""

using Genie, Genie.Router, Genie.Renderer.Html, Genie.Renderer.Json
using Genie.Requests: jsonpayload
using Genie.Responses

export setup_routes, start_server, serve_map, configure_data_source

# Global reference to the data file path
const DATA_SOURCE = Ref{String}("")

# Cache for loaded GeoJSON data
const GEOJSON_CACHE = Ref{Union{Dict{String, Any}, Nothing}}(nothing)

#Mapsettings
const ACTIVE_SETTINGS = Ref{MapSettings}(MapSettings())

"""
    configure_data_source(filepath::String)

Set the GeoPackage file to serve.
"""
function configure_data_source(filepath::String)
    DATA_SOURCE[] = filepath
    GEOJSON_CACHE[] = nothing
end

"""
    get_data_source() -> String

Get the currently configured data source path.
"""
function get_data_source()
    if isempty(DATA_SOURCE[])
        error("No data source configured. Call configure_data_source() first.")
    end
    return DATA_SOURCE[]
end

"""
    get_cached_geojson() -> Dict

Get the GeoJSON data, loading from file if not cached.
"""
function get_cached_geojson()
    if GEOJSON_CACHE[] === nothing
        filepath = get_data_source()
        GEOJSON_CACHE[] = read_geopackage(filepath)
    end
    return GEOJSON_CACHE[]
end

"""
    clear_geojson_cache()

Clear the cached GeoJSON data. Useful for development.
"""
function clear_geojson_cache()
    GEOJSON_CACHE[] = nothing
end

# =============================================================================
# Request Parsing
# =============================================================================

"""
    parse_filter_request(payload::Dict) -> FilterRequest

Parse a JSON payload into a FilterRequest struct.
"""
function parse_filter_request(payload::Dict)
    # Parse date bounds
    date_min = get(payload, "dateMin", nothing)
    date_max = get(payload, "dateMax", nothing)
    
    date_min = date_min === nothing ? nothing : Float64(date_min)
    date_max = date_max === nothing ? nothing : Float64(date_max)
    
    # Normalize date range if inverted
    if date_min !== nothing && date_max !== nothing && date_min > date_max
        date_min, date_max = date_max, date_min
    end
    
    # Parse include flags
    include_undated = get(payload, "includeUndated", true)
    include_no_culture = get(payload, "includeNoCulture", true)
    include_no_y_haplogroup = get(payload, "includeNoYHaplogroup", true)
    include_no_mtdna = get(payload, "includeNoMtdna", true)
    
    # Parse culture filter
    selected_cultures_raw = get(payload, "selectedCultures", [])
    selected_cultures = String[string(s) for s in selected_cultures_raw]
    culture_filter = CultureFilter(selected_cultures)
    
    # Parse Y-haplogroup filter
    y_search_text = get(payload, "yHaplogroupSearchText", "")
    selected_y_haplogroups_raw = get(payload, "selectedYHaplogroups", [])
    selected_y_haplogroups = String[string(s) for s in selected_y_haplogroups_raw]
    y_haplogroup_filter = HaplogroupFilter(y_search_text, selected_y_haplogroups)
    
    # Parse mtDNA filter
    mtdna_search_text = get(payload, "mtdnaSearchText", "")
    selected_mtdna_raw = get(payload, "selectedMtdna", [])
    selected_mtdna = String[string(s) for s in selected_mtdna_raw]
    mtdna_filter = HaplogroupFilter(mtdna_search_text, selected_mtdna)

    # Parse Y-haplotree filter
    y_haplotree_terms_raw = get(payload, "yHaplotreeTerms", [])
    y_haplotree_terms = String[string(s) for s in y_haplotree_terms_raw]
    y_haplotree_filter = YHaplotreeFilter(y_haplotree_terms)

    # Parse color settings
    color_by_str = get(payload, "colorBy", nothing)
    color_by = if color_by_str === nothing || color_by_str == ""
        nothing
    else
        Symbol(color_by_str)
    end

    color_ramp = get(payload, "colorRamp", "viridis")
    culture_color_ramp = get(payload, "cultureColorRamp", "viridis")
    y_haplogroup_color_ramp = get(payload, "yHaplogroupColorRamp", "viridis")
    mtdna_color_ramp = get(payload, "mtdnaColorRamp", "viridis")
    y_haplotree_color_ramp = get(payload, "yHaplotreeColorRamp", "viridis")

    return FilterRequest(
        date_min = date_min,
        date_max = date_max,
        include_undated = include_undated,
        culture_filter = culture_filter,
        include_no_culture = include_no_culture,
        y_haplogroup_filter = y_haplogroup_filter,
        include_no_y_haplogroup = include_no_y_haplogroup,
        mtdna_filter = mtdna_filter,
        include_no_mtdna = include_no_mtdna,
        y_haplotree_filter = y_haplotree_filter,
        color_by = color_by,
        color_ramp = color_ramp,
        culture_color_ramp = culture_color_ramp,
        y_haplogroup_color_ramp = y_haplogroup_color_ramp,
        mtdna_color_ramp = mtdna_color_ramp,
        y_haplotree_color_ramp = y_haplotree_color_ramp
    )
end

"""
    query_response_to_dict(response::QueryResponse) -> Dict

Convert a QueryResponse to a Dict for JSON serialization.
"""
function query_response_to_dict(response::QueryResponse)
    return Dict(
        "features" => response.features,
        "meta" => Dict(
            "totalCount" => response.meta.total_count,
            "filteredCount" => response.meta.filtered_count,
            "availableCultures" => response.meta.available_cultures,
            "availableYHaplogroups" => response.meta.available_y_haplogroups,
            "availableMtdna" => response.meta.available_mtdna,
            "filteredYHaplogroups" => response.meta.filtered_y_haplogroups,
            "filteredMtdna" => response.meta.filtered_mtdna,
            "availableDateRange" => Dict(
                "min" => response.meta.available_date_range[1],
                "max" => response.meta.available_date_range[2]
            ),
            "dateStatistics" => Dict(
                "min" => response.meta.date_statistics.min,
                "max" => response.meta.date_statistics.max,
                "p2" => response.meta.date_statistics.p2,
                "p98" => response.meta.date_statistics.p98
            ),
            "cultureLegend" => [
                Dict("name" => name, "color" => color)
                for (name, color) in response.meta.culture_legend
            ],
            "yHaplogroupLegend" => [
                Dict("name" => name, "color" => color)
                for (name, color) in response.meta.y_haplogroup_legend
            ],
            "mtdnaLegend" => [
                Dict("name" => name, "color" => color)
                for (name, color) in response.meta.mtdna_legend
            ],
            "yHaplotreeLegend" => [
                Dict("name" => name, "color" => color)
                for (name, color) in response.meta.y_haplotree_legend
            ]
        )
    )
end

# =============================================================================
# Configuration Endpoint
# =============================================================================

"""
    build_config_response() -> Dict

Build the configuration response for GET /api/config.
"""
function build_config_response()
    geojson = get_cached_geojson()
    
    date_stats = calculate_date_statistics(geojson)
    culture_stats = calculate_culture_statistics(geojson)
    bounds = calculate_bounds(geojson, DEFAULT_PADDING)
    center_lat, center_lon = calculate_center(bounds)
    
    # Extract all haplogroups for initial display
    all_y_haplogroups = extract_y_haplogroups(geojson["features"])
    all_mtdna = extract_mtdna(geojson["features"])
    
    return Dict(
        "colorRamps" => get_color_ramp_info(),
        "culturePalette" => CULTURE_PALETTE,
        "slider" => Dict(
            "min" => 0,
            "max" => 1000,
            "segments" => Dict(
                "leftBreak" => 50,
                "rightBreak" => 950
            )
        ),
        "defaults" => Dict(
            "includeUndated" => true,
            "includeNoCulture" => true,
            "includeNoYHaplogroup" => true,
            "includeNoMtdna" => true,
            "colorRamp" => "viridis",
            "cultureColorRamp" => "viridis",
            "yHaplogroupColorRamp" => "viridis",
            "mtdnaColorRamp" => "viridis",
            "yHaplotreeColorRamp" => "viridis",
            "pointColor" => DEFAULT_POINT_COLOR,
            "pointRadius" => DEFAULT_POINT_RADIUS
        ),
        "map" => Dict(
            "center" => [center_lat, center_lon],
            "zoom" => DEFAULT_ZOOM,
            "tileUrl" => ACTIVE_SETTINGS[].tile_url,
            "tileAttribution" => ACTIVE_SETTINGS[].tile_attribution
        ),
        "dateStatistics" => Dict(
            "min" => date_stats.min,
            "max" => date_stats.max,
            "p2" => date_stats.p2,
            "p98" => date_stats.p98
        ),
        "allCultures" => culture_stats.culture_names,
        "allYHaplogroups" => all_y_haplogroups,
        "allMtdna" => all_mtdna
    )
end

# =============================================================================
# Route Setup
# =============================================================================

"""
    setup_routes(; settings::MapSettings = MapSettings())

Configure all HTTP routes for the mapping application.
"""
function setup_routes(; default_settings::MapSettings = MapSettings())
    
    # Main map view with default settings
    route("/") do
        ACTIVE_SETTINGS[] = default_settings
        serve_map_response(default_settings)
    end
    
    # Topographic map variant
    route("/topo") do
        settings = MapSettings(:topo)
        ACTIVE_SETTINGS[] = settings
        serve_map_response(MapSettings(:settings))
    end
    
    # Humanitarian map variant  
    route("/humanitarian") do
        settings = MapSettings(:humanitarian)
        ACTIVE_SETTINGS[] = settings
        serve_map_response(MapSettings(:settings))
    end
    
    # Dark map variant  
    route("/dark") do
        settings = MapSettings(:dark)
        ACTIVE_SETTINGS[] = settings
        serve_map_response(MapSettings(:settings))
    end
    
    # Configuration endpoint
    route("/api/config") do
        json(build_config_response())
    end
    
    # Query endpoint
    route("/api/query", method = POST) do
        try
            payload = jsonpayload()
            if payload === nothing
                payload = Dict()
            end
            
            request = parse_filter_request(payload)
            geojson = get_cached_geojson()
            response = process_query(geojson, request)
            
            return json(query_response_to_dict(response))
        catch e
            @error "Error processing query" exception=(e, catch_backtrace())
            return json(Dict(
                "error" => true,
                "message" => string(e)
            ))
        end
    end
    
    # Legacy endpoints
    route("/api/samples") do
        geojson = get_cached_geojson()
        json(geojson)
    end
    
    # Health check endpoint
    route("/health") do
        json(Dict(
            "status" => "ok", 
            "data_source" => get_data_source(),
            "cached" => GEOJSON_CACHE[] !== nothing
        ))
    end
end

"""
    serve_map_response(settings::MapSettings) -> HTTP Response

Generate and serve the map HTML for a given settings configuration.
"""
function serve_map_response(settings::MapSettings)
    geojson = get_cached_geojson()
    
    bounds = calculate_bounds(geojson, settings.padding)
    center_lat, center_lon = calculate_center(bounds)
    date_stats = calculate_date_statistics(geojson)
    culture_stats = calculate_culture_statistics(geojson)
    
    config = MapConfig(
        center_lat,
        center_lon,
        settings.initial_zoom,
        date_stats,
        culture_stats,
        settings
    )
    
    html_content = render_map_html(config)
    return html(html_content)
end

"""
    start_server(port::Int = 8000; async::Bool = false)

Start the Genie web server.
"""
function start_server(port::Int = 8000; async::Bool = false)
    Genie.config.run_as_server = true
    
    Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
    Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type"
    Genie.config.cors_headers["Access-Control-Allow-Methods"] = "GET,POST,PUT,DELETE,OPTIONS"
    
    println("Starting ArcheoGeneticMap server on port $port...")
    println("Data source: $(get_data_source())")
    println("Open http://localhost:$port in your browser")
    
    up(port, async = async)
end

"""
    serve_map(filepath::String; port::Int = 8000, settings::MapSettings = MapSettings())

Convenience function to configure and start the mapping server.
"""
function serve_map(filepath::String; port::Int = 8000, settings::MapSettings = MapSettings())
    configure_data_source(filepath)
    setup_routes(default_settings = settings)
    start_server(port)
end
