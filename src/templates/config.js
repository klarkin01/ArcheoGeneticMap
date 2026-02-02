/**
 * ArcheoGeneticMap Configuration
 * 
 * Centralized configuration values for the frontend application.
 * This file contains only data/constants, no logic.
 * 
 * Must be loaded before other modules that depend on it:
 *   - ColorRamps (uses Config.colorRamps, Config.colorRampLabels)
 *   - PiecewiseScale (uses Config.slider)
 *   - map_app.js (uses Config.defaults)
 */

const Config = (function() {
    
    // =========================================================================
    // Color Ramp Definitions
    // =========================================================================
    
    /**
     * Color ramp arrays for data visualization.
     * Each ramp is an array of hex colors from low to high values.
     */
    const colorRamps = {
        viridis: [
            '#440154', '#482777', '#3e4a89', '#31688e', '#26838f',
            '#1f9d8a', '#6cce5a', '#b6de2b', '#fee825'
        ],
        plasma: [
            '#0d0887', '#46039f', '#7201a8', '#9c179e', '#bd3786',
            '#d8576b', '#ed7953', '#fb9f3a', '#fdca26'
        ],
        warm: [
            '#4575b4', '#74add1', '#abd9e9', '#e0f3f8', '#ffffbf',
            '#fee090', '#fdae61', '#f46d43', '#d73027'
        ],
        cool: [
            '#d73027', '#f46d43', '#fdae61', '#fee090', '#ffffbf',
            '#e0f3f8', '#abd9e9', '#74add1', '#4575b4'
        ],
        spectral: [
            '#9e0142', '#d53e4f', '#f46d43', '#fdae61', '#fee08b',
            '#e6f598', '#abdda4', '#66c2a5', '#3288bd'
        ],
        turbo: [
            '#30123b', '#4662d7', '#36aaf9', '#1ae4b6', '#72fe5e',
            '#c8ef34', '#fcce2e', '#f38b20', '#ca3e13'
        ]
    };
    
    /**
     * Human-readable labels for color ramps (used in dropdown menus)
     */
    const colorRampLabels = {
        viridis: 'Viridis (purple → yellow)',
        plasma: 'Plasma (purple → orange)',
        warm: 'Warm (blue → red)',
        cool: 'Cool (red → blue)',
        spectral: 'Spectral (red → blue)',
        turbo: 'Turbo (rainbow)'
    };
    
    // =========================================================================
    // Piecewise Slider Configuration
    // =========================================================================
    
    /**
     * Slider range and segment configuration for outlier compression.
     * 
     * The slider uses a normalized 0-1000 scale internally, divided into
     * three segments:
     *   - Left segment (0 to leftBreak): Maps to data below p2
     *   - Middle segment (leftBreak to rightBreak): Maps to p2-p98 range
     *   - Right segment (rightBreak to max): Maps to data above p98
     * 
     * Default allocates 5% / 90% / 5% of slider space to these segments,
     * giving fine control over the main data range while still allowing
     * access to outliers.
     */
    const slider = {
        min: 0,
        max: 1000,
        segments: {
            leftBreak: 50,    // 0-50 (5%) for outliers below p2
            rightBreak: 950   // 950-1000 (5%) for outliers above p98
        }
    };
    
    // =========================================================================
    // Default Filter Values
    // =========================================================================
    
    const defaults = {
        colorRamp: 'viridis',
        colorRampEnabled: false,
        includeUndated: true
    };
    
    // =========================================================================
    // Export Public API
    // =========================================================================
    
    return Object.freeze({
        colorRamps: colorRamps,
        colorRampLabels: colorRampLabels,
        slider: slider,
        defaults: defaults
    });
    
})();
