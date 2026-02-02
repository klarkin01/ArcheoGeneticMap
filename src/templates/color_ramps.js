/**
 * Color Ramps Module
 * 
 * Provides color interpolation utilities for data visualization.
 * Ramp definitions are loaded from Config.
 * 
 * Dependencies:
 *   - Config: Must be loaded first (provides colorRamps, colorRampLabels)
 * 
 * Usage:
 *   const color = ColorRamps.interpolate('viridis', 0.5);
 *   const gradient = ColorRamps.gradient('plasma');
 *   const color = ColorRamps.forValue(value, min, max, 'spectral', defaultColor);
 */

const ColorRamps = (function() {
    
    // =========================================================================
    // Color Conversion Utilities
    // =========================================================================
    
    /**
     * Convert hex color to RGB object
     * @param {string} hex - Hex color string (with or without #)
     * @returns {{r: number, g: number, b: number}}
     */
    function hexToRgb(hex) {
        hex = hex.replace('#', '');
        if (hex.length === 6) {
            return {
                r: parseInt(hex.substring(0, 2), 16),
                g: parseInt(hex.substring(2, 4), 16),
                b: parseInt(hex.substring(4, 6), 16)
            };
        }
        return { r: 0, g: 0, b: 0 };
    }
    
    /**
     * Convert RGB values to hex color string
     * @param {number} r - Red (0-255)
     * @param {number} g - Green (0-255)
     * @param {number} b - Blue (0-255)
     * @returns {string} Hex color with # prefix
     */
    function rgbToHex(r, g, b) {
        return '#' + [r, g, b].map(x => {
            const hex = x.toString(16);
            return hex.length === 1 ? '0' + hex : hex;
        }).join('');
    }
    
    // =========================================================================
    // Public API
    // =========================================================================
    
    /**
     * Get list of available ramp names
     * @returns {string[]}
     */
    function list() {
        return Object.keys(Config.colorRamps);
    }
    
    /**
     * Get ramp colors array by name
     * @param {string} name - Ramp name
     * @returns {string[]|null} Array of hex colors or null if not found
     */
    function get(name) {
        return Config.colorRamps[name] || null;
    }
    
    /**
     * Get UI label for a ramp
     * @param {string} name - Ramp name
     * @returns {string}
     */
    function label(name) {
        return Config.colorRampLabels[name] || name;
    }
    
    /**
     * Get array of {value, label} objects for dropdown menus
     * @returns {{value: string, label: string}[]}
     */
    function options() {
        return Object.keys(Config.colorRamps).map(name => ({
            value: name,
            label: Config.colorRampLabels[name] || name
        }));
    }
    
    /**
     * Interpolate a color from a ramp based on normalized value (0-1)
     * @param {string} rampName - Name of the color ramp
     * @param {number} t - Normalized value between 0 and 1
     * @returns {string} Interpolated hex color
     */
    function interpolate(rampName, t) {
        const ramp = Config.colorRamps[rampName];
        if (!ramp) {
            console.warn('ColorRamps: Unknown ramp "' + rampName + '"');
            return '#808080';
        }
        
        // Clamp t to [0, 1]
        t = Math.max(0, Math.min(1, t));
        
        // Find the two colors to interpolate between
        const numColors = ramp.length;
        const scaledT = t * (numColors - 1);
        const lowerIndex = Math.floor(scaledT);
        const upperIndex = Math.min(lowerIndex + 1, numColors - 1);
        const localT = scaledT - lowerIndex;
        
        // Parse hex colors
        const c1 = hexToRgb(ramp[lowerIndex]);
        const c2 = hexToRgb(ramp[upperIndex]);
        
        // Interpolate RGB values
        const r = Math.round(c1.r + (c2.r - c1.r) * localT);
        const g = Math.round(c1.g + (c2.g - c1.g) * localT);
        const b = Math.round(c1.b + (c2.b - c1.b) * localT);
        
        return rgbToHex(r, g, b);
    }
    
    /**
     * Get color for a value within a range
     * @param {number|null|undefined} value - The value to colorize
     * @param {number} min - Minimum of range (maps to t=0)
     * @param {number} max - Maximum of range (maps to t=1)
     * @param {string} rampName - Name of the color ramp
     * @param {string} defaultColor - Color for null/undefined values
     * @returns {string} Hex color
     */
    function forValue(value, min, max, rampName, defaultColor = '#808080') {
        if (value === null || value === undefined) {
            return defaultColor;
        }
        
        const range = max - min;
        if (range === 0) {
            return interpolate(rampName, 0.5);
        }
        
        const t = (value - min) / range;
        return interpolate(rampName, t);
    }
    
    /**
     * Generate CSS linear-gradient string for a ramp
     * @param {string} rampName - Name of the color ramp
     * @param {string} direction - CSS gradient direction (default: 'to right')
     * @returns {string} CSS linear-gradient value
     */
    function gradient(rampName, direction = 'to right') {
        const ramp = Config.colorRamps[rampName];
        if (!ramp) {
            return 'transparent';
        }
        return 'linear-gradient(' + direction + ', ' + ramp.join(', ') + ')';
    }
    
    // =========================================================================
    // Export Public API
    // =========================================================================
    
    return {
        list,
        get,
        label,
        options,
        interpolate,
        forValue,
        gradient,
        // Expose utilities for advanced use
        hexToRgb,
        rgbToHex
    };
    
})();
