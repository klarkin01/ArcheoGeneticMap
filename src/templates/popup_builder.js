/**
 * Popup Builder Module
 * 
 * Builds HTML popup content for map features with configurable field display.
 * Supports custom formatting, conditional display, and extensible field definitions.
 * 
 * Usage:
 *   // Simple usage with defaults
 *   const html = PopupBuilder.build(feature.properties);
 * 
 *   // Custom field configuration
 *   const html = PopupBuilder.build(props, [
 *       { key: 'sample_id', label: 'Sample ID', bold: true },
 *       { key: 'average_age_calbp', label: 'Age', suffix: ' cal BP' }
 *   ]);
 */

const PopupBuilder = (function() {
    
    // =========================================================================
    // Default Field Configuration
    // =========================================================================
    
    /**
     * Default fields for archaeological sample popups
     * Each field can have:
     *   - key: property name in the feature
     *   - label: display label
     *   - bold: whether to bold the value (default: false, first field is often bold)
     *   - prefix: text before value
     *   - suffix: text after value
     *   - format: function to format the value
     *   - show: function(value, props) returning boolean for conditional display
     */
    const DEFAULT_FIELDS = [
        { 
            key: 'sample_id', 
            label: 'Sample ID', 
            bold: true 
        },
        { 
            key: 'average_age_calbp', 
            label: 'Age', 
            suffix: ' cal BP',
            format: (v) => typeof v === 'number' ? v.toLocaleString() : v
        },
        { 
            key: 'culture', 
            label: 'Culture' 
        },
        { 
            key: 'y_haplogroup', 
            label: 'Y Haplogroup' 
        },
        { 
            key: 'mtdna', 
            label: 'mtDNA' 
        },
        {
            key: 'y_haplotree',
            label: 'Y Haplotree'
        }
    ];
    
    // =========================================================================
    // Formatting Utilities
    // =========================================================================
    
    /**
     * Escape HTML special characters to prevent XSS
     * @param {string} text - Raw text
     * @returns {string} Escaped HTML-safe text
     */
    function escapeHtml(text) {
        if (typeof text !== 'string') {
            text = String(text);
        }
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, char => map[char]);
    }
    
    /**
     * Check if a value is empty (null, undefined, or empty string)
     * @param {*} value 
     * @returns {boolean}
     */
    function isEmpty(value) {
        return value === null || value === undefined || value === '';
    }
    
    // =========================================================================
    // Public API
    // =========================================================================
    
    /**
     * Build HTML popup content from feature properties
     * 
     * @param {Object} props - Feature properties object
     * @param {Array} [fields] - Field configuration array (uses defaults if not provided)
     * @param {Object} [options] - Additional options
     * @param {string} [options.className] - CSS class for the popup container
     * @param {boolean} [options.escape] - Whether to escape HTML (default: true)
     * @returns {string} HTML string for popup content
     */
    function build(props, fields = DEFAULT_FIELDS, options = {}) {
        const { className = null, escape = true } = options;
        
        const lines = [];
        
        for (const field of fields) {
            const value = props[field.key];
            
            // Skip empty values
            if (isEmpty(value)) {
                continue;
            }
            
            // Check conditional display
            if (field.show && !field.show(value, props)) {
                continue;
            }
            
            // Format the value
            let displayValue = field.format ? field.format(value, props) : value;
            
            // Escape if needed
            if (escape) {
                displayValue = escapeHtml(displayValue);
            }
            
            // Add prefix/suffix
            if (field.prefix) {
                displayValue = field.prefix + displayValue;
            }
            if (field.suffix) {
                displayValue = displayValue + field.suffix;
            }
            
            // Build the line
            const label = field.label || field.key;
            if (field.bold) {
                lines.push('<b>' + escapeHtml(label) + ':</b> ' + displayValue);
            } else {
                lines.push('<b>' + escapeHtml(label) + ':</b> ' + displayValue);
            }
        }
        
        // Join with line breaks
        let html = lines.join('<br>');
        
        // Wrap in container if className specified
        if (className) {
            html = '<div class="' + escapeHtml(className) + '">' + html + '</div>';
        }
        
        return html;
    }
    
    /**
     * Create a custom builder with preset field configuration
     * Useful for creating specialized popup builders for different contexts
     * 
     * @param {Array} fields - Field configuration array
     * @param {Object} [defaultOptions] - Default options for this builder
     * @returns {Function} Builder function that takes (props, options?)
     */
    function createBuilder(fields, defaultOptions = {}) {
        return function(props, options = {}) {
            return build(props, fields, { ...defaultOptions, ...options });
        };
    }
    
    /**
     * Get the default field configuration
     * Useful for extending or modifying defaults
     * @returns {Array}
     */
    function getDefaultFields() {
        // Return a copy to prevent mutation
        return JSON.parse(JSON.stringify(DEFAULT_FIELDS));
    }
    
    // =========================================================================
    // Predefined Formatters
    // =========================================================================
    
    const formatters = {
        /**
         * Format a number with locale-specific separators
         */
        number: (v) => typeof v === 'number' ? v.toLocaleString() : v,
        
        /**
         * Format a number with fixed decimal places
         */
        decimal: (places) => (v) => typeof v === 'number' ? v.toFixed(places) : v,
        
        /**
         * Format coordinates as lat, lon
         */
        coords: (lat, lon) => lat.toFixed(4) + ', ' + lon.toFixed(4),
        
        /**
         * Format a date from various formats
         */
        date: (v) => {
            if (v instanceof Date) {
                return v.toLocaleDateString();
            }
            const d = new Date(v);
            return isNaN(d.getTime()) ? v : d.toLocaleDateString();
        }
    };
    
    // =========================================================================
    // Export Public API
    // =========================================================================
    
    return {
        build,
        createBuilder,
        getDefaultFields,
        formatters,
        // Expose utilities for custom use
        escapeHtml,
        isEmpty
    };
    
})();
