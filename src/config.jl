"""
    ArcheoGeneticMap.Config

Centralized configuration values for the application.
This module contains only constants and default values, no logic.
"""

# =============================================================================
# Map Display Defaults
# =============================================================================

"Default padding around data bounds (degrees)"
const DEFAULT_PADDING = 5.0

"Default initial zoom level (1-18)"
const DEFAULT_ZOOM = 6

"Default marker color (CSS hex)"
const DEFAULT_POINT_COLOR = "#e41a1c"

"Default marker radius (pixels)"
const DEFAULT_POINT_RADIUS = 4

# =============================================================================
# Date Range Defaults
# =============================================================================

"Default minimum age when no dated samples exist (cal BP)"
const DEFAULT_MIN_AGE = 0.0

"Default maximum age when no dated samples exist (cal BP)"
const DEFAULT_MAX_AGE = 50000.0

# =============================================================================
# Tile Layer Defaults
# =============================================================================

"Default tile layer URL template"
const DEFAULT_TILE_URL = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"

"Default tile layer attribution"
const DEFAULT_TILE_ATTRIBUTION = "© OpenStreetMap contributors"
