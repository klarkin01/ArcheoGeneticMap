/**
 * ArcheoGeneticMap - Archaeological Sample Visualization
 * 
 * Frontend application using Alpine.js for state management
 * and Leaflet for map rendering.
 * 
 * This is a "thin client" that delegates filtering and color assignment
 * to the backend via /api/query. The frontend handles:
 *   - UI state (sidebar, dropdowns, sections)
 *   - Slider position tracking and conversion
 *   - Map rendering with server-provided colors
 *   - Debounced server requests
 * 
 * Dependencies (loaded before this file):
 *   - PiecewiseScale: Slider-to-value conversion with outlier compression
 *   - PopupBuilder: HTML popup generation for map markers
 */

// =============================================================================
// Utilities
// =============================================================================

let mapInitialized = false;

/**
 * Simple debounce function
 */
function debounce(func, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
    };
}

// =============================================================================
// Map Layer Management (Leaflet)
// =============================================================================

let map = null;
let dataLayer = null;

/**
 * Initialize the Leaflet map
 */
function initMap(config) {
    
    if (mapInitialized) {
        console.log('Map already initialized, skipping...');
        return;
    }
    
    console.log('Initializing map...', config);
    
    try {
        map = L.map('map').setView(config.map.center, config.map.zoom);
        
        L.tileLayer(config.map.tileUrl, {
            attribution: config.map.tileAttribution
        }).addTo(map);
        
        mapInitialized = true;
        console.log('Map initialized successfully');
        
        // Force a resize after a short delay to handle any layout issues
        setTimeout(() => {
            map.invalidateSize();
        }, 100);
        
    } catch (e) {
        console.error('Error initializing map:', e);
    }
}

/**
 * Update the map layer with features from server
 * Colors are already assigned by the server in feature.properties._color
 */
function updateMapLayer(features, defaultColor, pointRadius) {
    // Remove existing layer
    if (dataLayer) {
        map.removeLayer(dataLayer);
    }
    
    // Create new layer
    const geojson = {
        type: 'FeatureCollection',
        features: features
    };
    
    dataLayer = L.geoJSON(geojson, {
        pointToLayer: function(feature, latlng) {
            // Use server-assigned color, fall back to default
            const color = feature.properties._color || defaultColor;
            
            return L.circleMarker(latlng, {
                radius: pointRadius,
                fillColor: color,
                color: color,
                weight: 1,
                opacity: 1,
                fillOpacity: 0.7
            });
        },
        onEachFeature: function(feature, layer) {
            layer.bindPopup(PopupBuilder.build(feature.properties));
        }
    }).addTo(map);
}

// =============================================================================
// Alpine.js Filter Controller
// =============================================================================

/**
 * Alpine.js component for filter management
 */
function filterController() {
    return {
        // ---------------------------------------------------------------------
        // UI State
        // ---------------------------------------------------------------------
        sidebarOpen: true,
        cultureDropdownOpen: false,
        yHaplogroupDropdownOpen: false,
        mtdnaDropdownOpen: false,
        loading: false,
        sections: {
            dateRange: false,
            culture: false,
            yHaplogroup: false,
            mtdna: false,
            yHaplotree: false
        },
        
        // ---------------------------------------------------------------------
        // Server-provided Configuration
        // ---------------------------------------------------------------------
        config: null,
        
        // ---------------------------------------------------------------------
        // Server-provided Metadata (updated with each query)
        // ---------------------------------------------------------------------
        meta: {
            totalCount: 0,
            filteredCount: 0,
            availableCultures: [],
            availableYHaplogroups: [],
            availableMtdna: [],
            filteredYHaplogroups: [],
            filteredMtdna: [],
            availableDateRange: { min: 0, max: 50000 },
            dateStatistics: { min: 0, max: 50000, p2: 0, p98: 50000 },
            cultureLegend: [],
            yHaplogroupLegend: [],
            mtdnaLegend: [],
            yHaplotreeLegend: []
        },
        
        // ---------------------------------------------------------------------
        // Filter State (sent to server)
        // ---------------------------------------------------------------------
        filters: {
            dateMin: null,
            dateMax: null,
            includeUndated: true,
            includeNoCulture: true,
            includeNoYHaplogroup: true,
            includeNoMtdna: true
        },
        
        // Culture filter state - just track selected cultures
        selectedCultures: [],
        
        // Y-haplogroup filter state
        selectedYHaplogroups: [],
        yHaplogroupSearchText: '',
        
        // mtDNA filter state
        selectedMtdna: [],
        mtdnaSearchText: '',

        // Y-haplotree filter state
        yHaplotreeTerms: [],       // confirmed search terms (tag list)
        yHaplotreeSearchInput: '', // current text in the search box
        yHaplotreeColorRamp: 'viridis',
        
        // Color settings
        colorBy: null,  // null, 'age', 'culture', 'y_haplogroup', 'mtdna', 'y_haplotree'
        colorRamp: 'viridis',
        cultureColorRamp: 'viridis',
        yHaplogroupColorRamp: 'viridis',
        mtdnaColorRamp: 'viridis',
        
        // Slider positions (0-1000 scale, UI concern only)
        sliderPositions: { min: 0, max: 1000 },
        
        // Piecewise scale instance
        dateScale: null,
        
        // Current features (from server)
        features: [],
        
        // ---------------------------------------------------------------------
        // Computed Properties
        // ---------------------------------------------------------------------
        get totalCount() {
            return this.meta.totalCount;
        },
        
        get filteredCount() {
            return this.meta.filteredCount;
        },
        
        get availableCultures() {
            return this.meta.availableCultures;
        },
        
        get allCulturesSelected() {
            return this.selectedCultures.length === this.availableCultures.length;
        },
        
        get availableYHaplogroups() {
            return this.meta.filteredYHaplogroups || this.meta.availableYHaplogroups || [];
        },
        
        get allYHaplogroupsSelected() {
            return this.selectedYHaplogroups.length === this.availableYHaplogroups.length;
        },
        
        get availableMtdna() {
            return this.meta.filteredMtdna || this.meta.availableMtdna || [];
        },
        
        get allMtdnaSelected() {
            return this.selectedMtdna.length === this.availableMtdna.length;
        },
        
        get availableColorRamps() {
            if (!this.config) return [];
            const defaultRamp = this.config.defaults?.colorRamp || 'viridis';
            return Object.entries(this.config.colorRamps)
                .map(([value, ramp]) => ({ value, label: ramp.label }))
                .sort((a, b) => {
                    if (a.value === defaultRamp) return -1;
                    if (b.value === defaultRamp) return 1;
                    return a.label.localeCompare(b.label);
                });
        },
        
        // ---------------------------------------------------------------------
        // Lifecycle
        // ---------------------------------------------------------------------
        async init() {
            console.log('Alpine init() starting...');
            
            try {
                // Fetch configuration from server
                console.log('Fetching config from /api/config...');
                const configResponse = await fetch('/api/config');
                this.config = await configResponse.json();
                console.log('Config loaded:', this.config);
                
                // Initialize the Leaflet map
                initMap(this.config);
                
                // Set up date scale from server-provided statistics
                const stats = this.config.dateStatistics;
                this.dateScale = PiecewiseScale.create(
                    stats.min,
                    stats.max,
                    stats.p2,
                    stats.p98
                );
                
                // Set initial filter range (p2 to p98 for better default view)
                this.filters.dateMin = stats.p2;
                this.filters.dateMax = stats.p98;
                
                // Set initial slider positions
                this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
                this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
                
                // Initialize culture selection to all
                this.selectedCultures = [...this.config.allCultures];
                
                // Initialize Y-haplogroup selection to all
                this.selectedYHaplogroups = [...this.config.allYHaplogroups];
                
                // Initialize mtDNA selection to all
                this.selectedMtdna = [...this.config.allMtdna];
                
                // Set defaults
                this.filters.includeUndated = this.config.defaults.includeUndated;
                this.filters.includeNoCulture = this.config.defaults.includeNoCulture;
                this.filters.includeNoYHaplogroup = this.config.defaults.includeNoYHaplogroup;
                this.filters.includeNoMtdna = this.config.defaults.includeNoMtdna;
                this.colorRamp = this.config.defaults.colorRamp;
                this.cultureColorRamp = this.config.defaults.cultureColorRamp;
                this.yHaplogroupColorRamp = this.config.defaults.yHaplogroupColorRamp;
                this.mtdnaColorRamp = this.config.defaults.mtdnaColorRamp;
                this.yHaplotreeColorRamp = this.config.defaults.yHaplotreeColorRamp || 'viridis';
                
                // Fetch initial data
                await this.applyFilters();
                
                console.log('Alpine init() complete');
                
            } catch (e) {
                console.error('Error in Alpine init():', e);
            }
        },
        
        // ---------------------------------------------------------------------
        // Server Communication
        // ---------------------------------------------------------------------
        
        /**
         * Build the request payload for /api/query
         */
        buildQueryPayload() {
            return {
                dateMin: this.filters.dateMin,
                dateMax: this.filters.dateMax,
                includeUndated: this.filters.includeUndated,
                selectedCultures: this.selectedCultures,
                includeNoCulture: this.filters.includeNoCulture,
                yHaplogroupSearchText: this.yHaplogroupSearchText,
                selectedYHaplogroups: this.selectedYHaplogroups,
                includeNoYHaplogroup: this.filters.includeNoYHaplogroup,
                mtdnaSearchText: this.mtdnaSearchText,
                selectedMtdna: this.selectedMtdna,
                includeNoMtdna: this.filters.includeNoMtdna,
                yHaplotreeTerms: this.yHaplotreeTerms,
                colorBy: this.colorBy,
                colorRamp: this.colorRamp,
                cultureColorRamp: this.cultureColorRamp,
                yHaplogroupColorRamp: this.yHaplogroupColorRamp,
                mtdnaColorRamp: this.mtdnaColorRamp,
                yHaplotreeColorRamp: this.yHaplotreeColorRamp
            };
        },
        
        /**
         * Send query to server and update state
         */
        async applyFilters() {
            if (!this.config) return;
            
            this.loading = true;
            
            try {
                const payload = this.buildQueryPayload();
                console.log('Sending query:', payload);
                
                const response = await fetch('/api/query', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                
                const data = await response.json();
                
                if (data.error) {
                    console.error('Query error:', data.message);
                    return;
                }
                
                // Update state from response
                this.features = data.features;
                this.meta = data.meta;
                
                // Sync selectedCultures with availableCultures
                // Keep only cultures that are both selected AND available given current filters
                this.selectedCultures = this.selectedCultures.filter(
                    culture => this.meta.availableCultures.includes(culture)
                );
                
                // Sync selectedYHaplogroups with availableYHaplogroups
                const availableY = this.meta.filteredYHaplogroups || this.meta.availableYHaplogroups || [];
                this.selectedYHaplogroups = this.selectedYHaplogroups.filter(
                    hap => availableY.includes(hap)
                );
                
                // Sync selectedMtdna with availableMtdna
                const availableMt = this.meta.filteredMtdna || this.meta.availableMtdna || [];
                this.selectedMtdna = this.selectedMtdna.filter(
                    hap => availableMt.includes(hap)
                );
                
                // Update map
                updateMapLayer(
                    this.features,
                    this.config.defaults.pointColor,
                    this.config.defaults.pointRadius
                );
                
                console.log('Query complete:', this.meta.filteredCount, 'features');
                
            } catch (e) {
                console.error('Error in applyFilters:', e);
            } finally {
                this.loading = false;
            }
        },
        
        /**
         * Debounced version for slider input
         */
        applyFiltersDebounced: debounce(function() {
            this.applyFilters();
        }, 200),
        
        /**
         * Reset all filters to initial state
         */
        resetFilters() {
            if (!this.config || !this.dateScale) return;
            
            const stats = this.config.dateStatistics;
            
            // Reset date range to p2-p98
            this.filters.dateMin = stats.p2;
            this.filters.dateMax = stats.p98;
            
            // Reset slider positions
            this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
            this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
            
            // Reset culture selection to all
            this.selectedCultures = [...this.config.allCultures];
            
            // Reset Y-haplogroup selection to all
            this.selectedYHaplogroups = [...this.config.allYHaplogroups];
            this.yHaplogroupSearchText = '';
            
            // Reset mtDNA selection to all
            this.selectedMtdna = [...this.config.allMtdna];
            this.mtdnaSearchText = '';

            // Reset Y-haplotree filter
            this.yHaplotreeTerms = [];
            this.yHaplotreeSearchInput = '';
            
            // Reset include flags to defaults
            this.filters.includeUndated = this.config.defaults.includeUndated;
            this.filters.includeNoCulture = this.config.defaults.includeNoCulture;
            this.filters.includeNoYHaplogroup = this.config.defaults.includeNoYHaplogroup;
            this.filters.includeNoMtdna = this.config.defaults.includeNoMtdna;
            
            // Reset color settings
            this.colorBy = null;
            this.colorRamp = this.config.defaults.colorRamp;
            this.cultureColorRamp = this.config.defaults.cultureColorRamp;
            this.yHaplogroupColorRamp = this.config.defaults.yHaplogroupColorRamp;
            this.mtdnaColorRamp = this.config.defaults.mtdnaColorRamp;
            this.yHaplotreeColorRamp = this.config.defaults.yHaplotreeColorRamp || 'viridis';
            
            // Apply the reset filters
            this.applyFilters();
        },
        
        // ---------------------------------------------------------------------
        // Date Range Methods
        // ---------------------------------------------------------------------
        
        /**
         * Handle slider input changes
         */
        onSliderInput(which) {
            if (!this.dateScale) return;
            
            if (which === 'min') {
                // Left slider controls the older (higher BP) values
                this.filters.dateMax = Math.round(this.dateScale.toValue(1000-this.sliderPositions.min));
            } else {
                // Right slider controls the younger (lower BP) values
                this.filters.dateMin = Math.round(this.dateScale.toValue(1000-this.sliderPositions.max));
            }
            
            // Use debounced version for slider dragging
            this.applyFiltersDebounced();
        },
        
        /**
         * Handle direct date input changes
         */
        onDateChange() {
            if (!this.dateScale) return;
            
            // Clamp to data range
            this.filters.dateMin = this.dateScale.clamp(this.filters.dateMin);
            this.filters.dateMax = this.dateScale.clamp(this.filters.dateMax);
            
            // Update slider positions
            this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
            this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
            
            this.applyFilters();
        },
        
        /**
         * Calculate CSS style for the slider range highlight
         */
        sliderRangeStyle() {
            if (!this.dateScale) {
                return { left: '0%', width: '100%' };
            }
            return this.dateScale.rangeStyle(this.sliderPositions.min, this.sliderPositions.max);
        },
        
        // ---------------------------------------------------------------------
        // Color Methods
        // ---------------------------------------------------------------------
        
        /**
         * Handle color by age toggle
         */
        onColorByAgeChange() {
            if (this.colorBy === 'age') {
                this.colorBy = null;
            } else {
                this.colorBy = 'age';
            }
            this.applyFilters();
        },
        
        /**
         * Handle color ramp selection change
         */
        onColorRampChange() {
            if (this.colorBy === 'age') {
                this.applyFilters();
            }
        },
        
        /**
         * Handle color by culture toggle
         */
        onColorByCultureChange() {
            if (this.colorBy === 'culture') {
                this.colorBy = null;
            } else {
                this.colorBy = 'culture';
            }
            this.applyFilters();
        },
        
        /**
         * Handle culture color ramp selection change
         */
        onCultureColorRampChange() {
            if (this.colorBy === 'culture') {
                this.applyFilters();
            }
        },
        
        // ---------------------------------------------------------------------
        // Culture Filter Methods
        // ---------------------------------------------------------------------

        /**
         * Get summary text for the multi-select toggle button
         */
        selectedCulturesSummary() {
            const count = this.selectedCultures.length;
            const total = this.availableCultures.length;
            
            if (count === 0) {
                return 'None selected';
            }
            if (count === total) {
                return 'All cultures';
            }
            if (count === 1) {
                return this.selectedCultures[0];
            }
            return count + ' cultures selected';
        },

        /**
         * Toggle a single culture selection
         */
        toggleCulture(culture) {
            const index = this.selectedCultures.indexOf(culture);
            if (index === -1) {
                // Add culture
                this.selectedCultures.push(culture);
            } else {
                // Remove culture
                this.selectedCultures.splice(index, 1);
            }
            this.applyFilters();
        },

        /**
         * Toggle all cultures on/off
         */
        toggleAllCultures() {
            if (this.allCulturesSelected) {
                // Deselect all
                this.selectedCultures = [];
            } else {
                // Select all
                this.selectedCultures = [...this.availableCultures];
            }
            this.applyFilters();
        },
        
        /**
         * Check if a culture is currently selected
         */
        isCultureSelected(culture) {
            return this.selectedCultures.includes(culture);
        },

        /**
         * Get cultures to show in legend (from server-provided legend)
         */
        cultureLegendItems() {
            return this.meta.cultureLegend || [];
        },
        
        // ---------------------------------------------------------------------
        // Y-Haplogroup Filter Methods
        // ---------------------------------------------------------------------
        
        /**
         * Get summary text for Y-haplogroup multi-select
         */
        selectedYHaplogroupsSummary() {
            const count = this.selectedYHaplogroups.length;
            const total = this.availableYHaplogroups.length;
            
            if (count === 0) {
                return 'None selected';
            }
            if (count === total) {
                return 'All haplogroups';
            }
            if (count === 1) {
                return this.selectedYHaplogroups[0];
            }
            return count + ' haplogroups selected';
        },
        
        /**
         * Toggle a single Y-haplogroup selection
         */
        toggleYHaplogroup(haplogroup) {
            // Mutual exclusivity: clear y_haplotree filter
            if (this.yHaplotreeTerms.length > 0) {
                this.yHaplotreeTerms = [];
                this.yHaplotreeSearchInput = '';
                if (this.colorBy === 'y_haplotree') this.colorBy = null;
            }
            const index = this.selectedYHaplogroups.indexOf(haplogroup);
            if (index === -1) {
                this.selectedYHaplogroups.push(haplogroup);
            } else {
                this.selectedYHaplogroups.splice(index, 1);
            }
            this.applyFilters();
        },
        
        /**
         * Toggle all Y-haplogroups on/off
         */
        toggleAllYHaplogroups() {
            // Mutual exclusivity: clear y_haplotree filter
            if (this.yHaplotreeTerms.length > 0) {
                this.yHaplotreeTerms = [];
                this.yHaplotreeSearchInput = '';
                if (this.colorBy === 'y_haplotree') this.colorBy = null;
            }
            if (this.allYHaplogroupsSelected) {
                this.selectedYHaplogroups = [];
            } else {
                this.selectedYHaplogroups = [...this.availableYHaplogroups];
            }
            this.applyFilters();
        },
        
        /**
         * Check if a Y-haplogroup is currently selected
         */
        isYHaplogroupSelected(haplogroup) {
            return this.selectedYHaplogroups.includes(haplogroup);
        },
        
        /**
         * Handle Y-haplogroup search
         */
        onYHaplogroupSearch() {
            // Search is applied via backend filtering
            this.applyFilters();
        },
        
        /**
         * Get Y-haplogroups to show in legend
         */
        yHaplogroupLegendItems() {
            return this.meta.yHaplogroupLegend || [];
        },
        
        /**
         * Handle color by Y-haplogroup toggle
         */
        onColorByYHaplogroupChange() {
            if (this.colorBy === 'y_haplogroup') {
                this.colorBy = null;
            } else {
                this.colorBy = 'y_haplogroup';
            }
            this.applyFilters();
        },
        
        /**
         * Handle Y-haplogroup color ramp selection change
         */
        onYHaplogroupColorRampChange() {
            if (this.colorBy === 'y_haplogroup') {
                this.applyFilters();
            }
        },
        
        // ---------------------------------------------------------------------
        // mtDNA Filter Methods
        // ---------------------------------------------------------------------
        
        /**
         * Get summary text for mtDNA multi-select
         */
        selectedMtdnaSummary() {
            const count = this.selectedMtdna.length;
            const total = this.availableMtdna.length;
            
            if (count === 0) {
                return 'None selected';
            }
            if (count === total) {
                return 'All haplogroups';
            }
            if (count === 1) {
                return this.selectedMtdna[0];
            }
            return count + ' haplogroups selected';
        },
        
        /**
         * Toggle a single mtDNA selection
         */
        toggleMtdna(mtdna) {
            const index = this.selectedMtdna.indexOf(mtdna);
            if (index === -1) {
                this.selectedMtdna.push(mtdna);
            } else {
                this.selectedMtdna.splice(index, 1);
            }
            this.applyFilters();
        },
        
        /**
         * Toggle all mtDNA on/off
         */
        toggleAllMtdna() {
            if (this.allMtdnaSelected) {
                this.selectedMtdna = [];
            } else {
                this.selectedMtdna = [...this.availableMtdna];
            }
            this.applyFilters();
        },
        
        /**
         * Check if an mtDNA is currently selected
         */
        isMtdnaSelected(mtdna) {
            return this.selectedMtdna.includes(mtdna);
        },
        
        /**
         * Handle mtDNA search
         */
        onMtdnaSearch() {
            // Search is applied via backend filtering
            this.applyFilters();
        },
        
        /**
         * Get mtDNA to show in legend
         */
        mtdnaLegendItems() {
            return this.meta.mtdnaLegend || [];
        },
        
        /**
         * Handle color by mtDNA toggle
         */
        onColorByMtdnaChange() {
            if (this.colorBy === 'mtdna') {
                this.colorBy = null;
            } else {
                this.colorBy = 'mtdna';
            }
            this.applyFilters();
        },
        
        /**
         * Handle mtDNA color ramp selection change
         */
        onMtdnaColorRampChange() {
            if (this.colorBy === 'mtdna') {
                this.applyFilters();
            }
        },
        
        // ---------------------------------------------------------------------
        // Y-Haplotree Filter Methods
        // ---------------------------------------------------------------------

        /**
         * Add the current search input as a term to the filter list.
         * Clears y_haplogroup filter (mutual exclusivity).
         * No-ops if the term is empty or already in the list.
         */
        addYHaplotreeTerm() {
            const term = this.yHaplotreeSearchInput.trim();
            if (!term || this.yHaplotreeTerms.includes(term)) {
                this.yHaplotreeSearchInput = '';
                return;
            }
            // Mutual exclusivity: clear y_haplogroup filter
            this.selectedYHaplogroups = [...(this.config ? this.config.allYHaplogroups : [])];
            if (this.colorBy === 'y_haplogroup') this.colorBy = null;

            this.yHaplotreeTerms.push(term);
            this.yHaplotreeSearchInput = '';
            this.applyFilters();
        },

        /**
         * Handle Enter key in the y_haplotree search box
         * Note: @keydown.enter.prevent in the template calls addYHaplotreeTerm() directly.
         * This method is kept for completeness but is no longer wired to the template.
         */
        onYHaplotreeSearchKeydown(event) {
            if (event.key === 'Enter') {
                event.preventDefault();
                this.addYHaplotreeTerm();
            }
        },

        /**
         * Remove a single term from the filter list
         */
        removeYHaplotreeTerm(term) {
            const idx = this.yHaplotreeTerms.indexOf(term);
            if (idx !== -1) {
                this.yHaplotreeTerms.splice(idx, 1);
            }
            if (this.yHaplotreeTerms.length === 0 && this.colorBy === 'y_haplotree') {
                this.colorBy = null;
            }
            this.applyFilters();
        },

        /**
         * Clear all y_haplotree terms
         */
        clearYHaplotreeTerms() {
            this.yHaplotreeTerms = [];
            this.yHaplotreeSearchInput = '';
            if (this.colorBy === 'y_haplotree') this.colorBy = null;
            this.applyFilters();
        },

        /**
         * Get legend items for y_haplotree coloring
         */
        yHaplotreeLegendItems() {
            return this.meta.yHaplotreeLegend || [];
        },

        /**
         * Handle color by y_haplotree toggle
         */
        onColorByYHaplotreeChange() {
            if (this.colorBy === 'y_haplotree') {
                this.colorBy = null;
            } else {
                this.colorBy = 'y_haplotree';
            }
            this.applyFilters();
        },

        /**
         * Handle y_haplotree color ramp selection change
         */
        onYHaplotreeColorRampChange() {
            if (this.colorBy === 'y_haplotree') {
                this.applyFilters();
            }
        },

        // ---------------------------------------------------------------------
        // Color Ramp Utilities
        // ---------------------------------------------------------------------
        
        /**
         * Generate a preview gradient for the selected color ramp
         */
        colorRampGradient(rampName) {
            if (!this.config || !this.config.colorRamps[rampName]) {
                return 'transparent';
            }
            const colors = this.config.colorRamps[rampName].colors;
            return 'linear-gradient(to right, ' + colors.join(', ') + ')';
        }
    };
}
