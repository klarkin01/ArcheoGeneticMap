"""
    ArcheoMap.Templates

Template loading, assembly, and rendering for the web interface.
"""

using JSON3

export render_map_html, clear_template_cache

# Cache for loaded template files
const TEMPLATE_CACHE = Dict{String, String}()

"""
    template_dir()

Get the path to the templates directory.
"""
function template_dir()
    return joinpath(@__DIR__)
end

"""
    load_template(filename::String; cache::Bool=true) -> String

Load a template file from the templates directory.
Caches loaded files by default for performance.
"""
function load_template(filename::String; cache::Bool=true)
    if cache && haskey(TEMPLATE_CACHE, filename)
        return TEMPLATE_CACHE[filename]
    end
    
    filepath = joinpath(template_dir(), filename)
    content = read(filepath, String)
    
    if cache
        TEMPLATE_CACHE[filename] = content
    end
    
    return content
end

"""
    clear_template_cache()

Clear the template cache. Useful during development.
"""
function clear_template_cache()
    empty!(TEMPLATE_CACHE)
end

"""
    build_config_json(config::MapConfig) -> String

Build the JSON configuration object for the frontend.
"""
function build_config_json(config)
    config_dict = Dict{String, Any}(
        "center" => [config.center_lat, config.center_lon],
        "zoom" => config.zoom,
        "dateRange" => Dict(
            "min" => config.min_age,
            "max" => config.max_age
        ),
        "style" => Dict(
            "pointColor" => config.settings.point_color,
            "pointRadius" => config.settings.point_radius,
            "tileUrl" => config.settings.tile_url,
            "tileAttribution" => config.settings.tile_attribution
        )
    )
    
    return JSON3.write(config_dict)
end

"""
    render_map_html(config::MapConfig) -> String

Render the complete map HTML by assembling templates and injecting configuration.

# Arguments
- `config::MapConfig`: Complete map configuration including center, zoom, and settings

# Returns
Complete HTML string ready to serve
"""
function render_map_html(config)
    # Load template components
    html_template = load_template("map_base.html")
    css_content = load_template("map_styles.css")
    js_content = load_template("map_app.js")
    
    # Build configuration JSON
    config_json = build_config_json(config)
    
    # Assemble the final HTML
    html = replace(html_template,
        "{{CONFIG}}" => config_json,
        "{{STYLES}}" => css_content,
        "{{SCRIPTS}}" => js_content
    )
    
    return html
end

"""
    render_map_html(; center_lat, center_lon, zoom, min_age, max_age, settings) -> String

Convenience method to render map HTML from individual parameters.
"""
function render_map_html(;
    center_lat::Float64,
    center_lon::Float64,
    zoom::Int,
    min_age::Float64,
    max_age::Float64,
    settings::MapSettings
)
    config = MapConfig(center_lat, center_lon, zoom, min_age, max_age, settings)
    return render_map_html(config)
end
