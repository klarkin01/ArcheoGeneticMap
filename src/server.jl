"""
    ArcheoGeneticMap.Server

Web server routes and startup using Genie.
"""

using Genie, Genie.Router, Genie.Renderer.Html, Genie.Renderer.Json

export setup_routes, start_server, serve_map, configure_data_source

# Global reference to the data file path
# Set via serve_map() or configure_data_source()
const DATA_SOURCE = Ref{String}("")

"""
    configure_data_source(filepath::String)

Set the GeoPackage file to serve.
"""
function configure_data_source(filepath::String)
    DATA_SOURCE[] = filepath
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
    setup_routes(; settings::MapSettings = MapSettings())

Configure all HTTP routes for the mapping application.
"""
function setup_routes(; default_settings::MapSettings = MapSettings())
    
    # Main map view with default settings
    route("/") do
        serve_map_response(default_settings)
    end
    
    # Topographic map variant
    route("/topo") do
        serve_map_response(MapSettings(:topo))
    end
    
    # Humanitarian map variant  
    route("/humanitarian") do
        serve_map_response(MapSettings(:humanitarian))
    end
    
    # GeoJSON API endpoint
    route("/api/samples") do
        filepath = get_data_source()
        geojson = read_geopackage(filepath)
        json(geojson)
    end
    
    # Health check endpoint
    route("/health") do
        json(Dict("status" => "ok", "data_source" => get_data_source()))
    end
end

"""
    serve_map_response(settings::MapSettings) -> HTTP Response

Generate and serve the map HTML for a given settings configuration.
"""
function serve_map_response(settings::MapSettings)
    filepath = get_data_source()
    
    # Load and analyze data
    geojson = read_geopackage(filepath)
    bounds = calculate_bounds(geojson, settings.padding)
    center_lat, center_lon = calculate_center(bounds)
    min_age, max_age = calculate_date_range(geojson)
    
    # Build configuration
    config = MapConfig(
        center_lat,
        center_lon,
        settings.initial_zoom,
        min_age,
        max_age,
        settings
    )
    
    # Render and return HTML
    html_content = render_map_html(config)
    return html(html_content)
end

"""
    start_server(port::Int = 8000; async::Bool = false)

Start the Genie web server.

# Arguments
- `port`: Port number to listen on (default: 8000)
- `async`: If true, start server in background (default: false)
"""
function start_server(port::Int = 8000; async::Bool = false)
    # Configure Genie
    Genie.config.run_as_server = true
    
    # CORS configuration for API access
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

# Arguments
- `filepath`: Path to the GeoPackage file to serve
- `port`: Port number (default: 8000)
- `settings`: Default map settings
"""
function serve_map(filepath::String; port::Int = 8000, settings::MapSettings = MapSettings())
    configure_data_source(filepath)
    setup_routes(default_settings = settings)
    start_server(port)
end
