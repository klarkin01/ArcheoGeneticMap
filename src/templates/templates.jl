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
            "min" => config.date_stats.min,
            "max" => config.date_stats.max,
            "p2" => config.date_stats.p2,
            "p98" => config.date_stats.p98
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

# JavaScript modules to load, in dependency order
# Config must come first as other modules depend on it
const JS_MODULES = [
    "config.js",           # No dependencies - must be first
    "color_ramps.js",      # Depends on Config
    "piecewise_scale.js",  # Depends on Config
    "popup_builder.js",    # No dependencies
    "map_app.js"           # Depends on all above
]

"""
    load_javascript_modules(; cache::Bool=true) -> String

Load and concatenate all JavaScript modules in dependency order.
Returns a single string ready for injection into the HTML template.
"""
function load_javascript_modules(; cache::Bool=true)
    modules = String[]
    
    for filename in JS_MODULES
        content = load_template(filename; cache=cache)
        push!(modules, "// ============ $(filename) ============")
        push!(modules, content)
        push!(modules, "")  # blank line between modules
    end
    
    return join(modules, "\n")
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
    
    # Load and concatenate JavaScript modules
    js_content = load_javascript_modules()
    
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
    render_map_html(; center_lat, center_lon, zoom, date_stats, settings) -> String

Convenience method to render map HTML from individual parameters.
"""
function render_map_html(;
    center_lat::Float64,
    center_lon::Float64,
    zoom::Int,
    date_stats::DateStatistics,
    settings::MapSettings
)
    config = MapConfig(center_lat, center_lon, zoom, date_stats, settings)
    return render_map_html(config)
end
