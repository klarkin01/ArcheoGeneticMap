/**
 * Piecewise Scale Module
 * 
 * Creates bidirectional mappings between a slider and data values,
 * with piecewise linear scaling to handle outliers gracefully.
 * 
 * Dependencies:
 *   - Config: Must be loaded first (provides slider.min, slider.max, slider.segments)
 * 
 * Usage:
 *   const scale = PiecewiseScale.create(dataMin, dataMax, p2, p98);
 *   const sliderPos = scale.toSlider(dataValue);
 *   const dataValue = scale.toValue(sliderPos);
 *   const style = scale.rangeStyle(sliderMin, sliderMax);
 */

const PiecewiseScale = (function() {
    
    // =========================================================================
    // Scale Factory
    // =========================================================================
    
    /**
     * Create a piecewise scale for a data range
     * 
     * @param {number} dataMin - Absolute minimum of data
     * @param {number} dataMax - Absolute maximum of data
     * @param {number|null} p2 - 2nd percentile value (or null for linear scale)
     * @param {number|null} p98 - 98th percentile value (or null for linear scale)
     * @param {Object} [segments] - Optional custom segment boundaries
     * @returns {Object} Scale object with toSlider, toValue, and utility methods
     */
    function create(dataMin, dataMax, p2 = null, p98 = null, segments = null) {
        // Use Config values as defaults
        const SLIDER_MIN = Config.slider.min;
        const SLIDER_MAX = Config.slider.max;
        const { leftBreak, rightBreak } = segments || Config.slider.segments;
        
        /**
         * Convert a data value to slider position
         */
        function toSlider(value) {
            // Fallback to linear if percentiles not available
            if (p2 === null || p98 === null) {
                if (dataMax === dataMin) return SLIDER_MAX / 2;
                return ((value - dataMin) / (dataMax - dataMin)) * SLIDER_MAX;
            }
            
            if (value <= p2) {
                // Left segment: dataMin to p2 -> 0 to leftBreak
                if (p2 === dataMin) return leftBreak;
                const t = (value - dataMin) / (p2 - dataMin);
                return t * leftBreak;
            } else if (value <= p98) {
                // Middle segment: p2 to p98 -> leftBreak to rightBreak
                if (p98 === p2) return (leftBreak + rightBreak) / 2;
                const t = (value - p2) / (p98 - p2);
                return leftBreak + t * (rightBreak - leftBreak);
            } else {
                // Right segment: p98 to dataMax -> rightBreak to SLIDER_MAX
                if (dataMax === p98) return rightBreak;
                const t = (value - p98) / (dataMax - p98);
                return rightBreak + t * (SLIDER_MAX - rightBreak);
            }
        }
        
        /**
         * Convert a slider position to data value
         */
        function toValue(sliderPos) {
            // Fallback to linear if percentiles not available
            if (p2 === null || p98 === null) {
                return dataMin + (sliderPos / SLIDER_MAX) * (dataMax - dataMin);
            }
            
            if (sliderPos <= leftBreak) {
                // Left segment: 0 to leftBreak -> dataMin to p2
                const t = sliderPos / leftBreak;
                return dataMin + t * (p2 - dataMin);
            } else if (sliderPos <= rightBreak) {
                // Middle segment: leftBreak to rightBreak -> p2 to p98
                const t = (sliderPos - leftBreak) / (rightBreak - leftBreak);
                return p2 + t * (p98 - p2);
            } else {
                // Right segment: rightBreak to SLIDER_MAX -> p98 to dataMax
                const t = (sliderPos - rightBreak) / (SLIDER_MAX - rightBreak);
                return p98 + t * (dataMax - p98);
            }
        }
        
        /**
         * Calculate CSS style object for a range highlight between two slider positions
         * @param {number} sliderLow - Lower slider position
         * @param {number} sliderHigh - Higher slider position
         * @returns {{left: string, width: string}}
         */
        function rangeStyle(sliderLow, sliderHigh) {
            const leftPercent = (sliderLow / SLIDER_MAX) * 100;
            const rightPercent = (sliderHigh / SLIDER_MAX) * 100;
            return {
                left: leftPercent + '%',
                width: (rightPercent - leftPercent) + '%'
            };
        }
        
        /**
         * Clamp a value to the data range
         */
        function clamp(value) {
            return Math.min(dataMax, Math.max(dataMin, value));
        }
        
        // Return the scale object
        return {
            toSlider,
            toValue,
            rangeStyle,
            clamp,
            // Expose bounds for reference
            bounds: { dataMin, dataMax, p2, p98 },
            sliderBounds: { min: SLIDER_MIN, max: SLIDER_MAX }
        };
    }
    
    // =========================================================================
    // Percentile Calculation Utility
    // =========================================================================
    
    /**
     * Calculate percentiles from an array of numbers
     * @param {number[]} values - Array of numeric values
     * @param {number[]} percentiles - Array of percentiles to calculate (0-100)
     * @returns {Object} Object mapping percentile to value
     */
    function calculatePercentiles(values, percentiles = [2, 98]) {
        if (!values || values.length === 0) {
            return null;
        }
        
        const sorted = [...values].sort((a, b) => a - b);
        const result = {
            min: sorted[0],
            max: sorted[sorted.length - 1]
        };
        
        for (const p of percentiles) {
            const key = 'p' + p;
            const index = Math.floor(sorted.length * (p / 100));
            result[key] = sorted[Math.min(index, sorted.length - 1)];
        }
        
        return result;
    }
    
    /**
     * Create a scale from an array of values, automatically calculating percentiles
     * @param {number[]} values - Array of numeric values
     * @param {Object} [segments] - Optional custom segment boundaries
     * @returns {Object} Scale object
     */
    function fromValues(values, segments = null) {
        const stats = calculatePercentiles(values, [2, 98]);
        if (!stats) {
            // Return a degenerate scale
            return create(0, 1, null, null, segments);
        }
        return create(stats.min, stats.max, stats.p2, stats.p98, segments);
    }
    
    // =========================================================================
    // Export Public API
    // =========================================================================
    
    return {
        create,
        fromValues,
        calculatePercentiles,
        // Expose config values for external reference (read from Config)
        get SLIDER_MIN() { return Config.slider.min; },
        get SLIDER_MAX() { return Config.slider.max; },
        get DEFAULT_SEGMENTS() { return Config.slider.segments; }
    };
    
})();
