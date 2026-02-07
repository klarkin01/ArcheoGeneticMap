"""
    ArcheoGeneticMap.Templates

Template loading, assembly, and rendering for the web interface.

The frontend fetches configuration via /api/config (Strategy B),
so this module only assembles HTML, CSS, and JS without injecting config.
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

# JavaScript modules to load, in dependency order
# Note: color_ramps.js removed - colors now computed server-side
# Note: config.js removed - config now fetched via /api/config
const JS_MODULES = [
    "piecewise_scale.js",  # Slider scaling (uses config from server)
    "popup_builder.js",    # Popup HTML generation
    "map_app.js"           # Main application
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

Render the complete map HTML by assembling templates.

Note: Configuration is no longer injected - the frontend fetches it via /api/config.
The config parameter is kept for API compatibility but only used minimally.

# Arguments
- `config::MapConfig`: Map configuration (kept for compatibility)

# Returns
Complete HTML string ready to serve
"""
function render_map_html(config::MapConfig)
    # Load template components
    html_template = load_template("map_base.html")
    css_content = load_template("map_styles.css")
    
    # Load and concatenate JavaScript modules
    js_content = load_javascript_modules()
    
    # Assemble the final HTML (no config injection needed)
    html = replace(html_template,
        "{{STYLES}}" => css_content,
        "{{SCRIPTS}}" => js_content
    )
    
    return html
end

"""
    render_map_html() -> String

Render the map HTML without any configuration.
Configuration is fetched by the frontend via /api/config.
"""
function render_map_html()
    # Load template components
    html_template = load_template("map_base.html")
    css_content = load_template("map_styles.css")
    
    # Load and concatenate JavaScript modules
    js_content = load_javascript_modules()
    
    # Assemble the final HTML
    html = replace(html_template,
        "{{STYLES}}" => css_content,
        "{{SCRIPTS}}" => js_content
    )
    
    return html
end
