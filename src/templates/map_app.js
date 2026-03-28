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
 * 
 * Selection filter semantics:
 *   Each categorical filter (culture, Y-haplogroup, mtDNA, source) has an
 *   independent on/off toggle (filterActive flag).
 *
 *   Filter OFF:
 *     - selected array is empty; backend receives active=false → all pass
 *     - cascading: new options from other filters auto-pass (no tracking needed)
 *
 *   Filter ON, all selected:
 *     - selected array contains all available options
 *     - backend receives active=true + full list → all pass (same result as OFF)
 *     - cascading: new available options are auto-added to selected
 *
 *   Filter ON, partial selection:
 *     - selected array contains a subset of available options
 *     - backend receives active=true + subset → only those pass
 *     - cascading: new available options are NOT auto-added (explicit selection preserved)
 *
 *   Filter ON, none selected:
 *     - selected array is empty; backend receives active=true + [] → nothing passes
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
        map = L.map('map', { preferCanvas: true, worldCopyJump: true }).setView(config.map.center, config.map.zoom);
        
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
 * Fetch full properties for a single sample by id.
 * Returns a Promise that resolves to popup HTML.
 */
function fetchPopupContent(id) {
    return fetch('/api/sample/' + encodeURIComponent(id))
        .then(function (r) { return r.json(); })
        .then(function (props) {
            if (props.error) return PopupBuilder.buildError(props.message);
            return PopupBuilder.build(props);
        });
}

/**
 * Update the map layer with slim features from server.
 * Each feature is { id, lon, lat, color }.
 */
function updateMapLayer(features, defaultColor, pointRadius) {
    // Detach spiderifier before removing old layer (cleans up events and spokes)
    Spiderifier.detach();

    // Remove existing layer
    if (dataLayer) {
        map.removeLayer(dataLayer);
    }

    // Build a GeoJSON FeatureCollection from slim features so L.geoJSON can
    // place markers. We attach the slim feature as layer.feature so the
    // spiderifier can read id and color without needing full properties.
    const geojson = {
        type: 'FeatureCollection',
        features: features.map(function (f) {
            return {
                type: 'Feature',
                //geometry: { type: 'Point', coordinates: [f.lon, f.lat] },
                geometry: { type: 'Point', coordinates: [f.lon < -27 ? f.lon +360 : f.lon, f.lat] },
                // Slim properties: only what the spiderifier and renderer need
                properties: { id: f.id, color: f.color || defaultColor }
            };
        })
    };

    dataLayer = L.geoJSON(geojson, {
        pointToLayer: function (feature, latlng) {
            const color = feature.properties.color || defaultColor;
            return L.circleMarker(latlng, {
                radius     : pointRadius,
                fillColor  : color,
                color      : color,
                weight     : 1,
                opacity    : 1,
                fillOpacity: 0.7
            });
        },
        onEachFeature: function (feature, layer) {
            // Slim feature stored on layer for spiderifier access.
            // Shape matches what spiderifier expects: { id, color }
            layer.feature = feature.properties;
        }
    }).addTo(map);

    // Attach spiderifier, providing the async popup fetch function
    Spiderifier.attach(map, dataLayer, {
        pixelRadius      : 8,
        clusterThreshold : 15,
        spokeLength      : { min: 44, max: 72 },
        fetchPopupContent: fetchPopupContent
    });
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
        sourceDropdownOpen: false,
        loading: false,
        sections: {
            dateRange: false,
            culture: false,
            yHaplogroup: false,
            mtdna: false,
            yHaplotree: false,
            source: false
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
            availableSources: [],
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

        // Per-filter active toggles. When false the filter is off and the
        // backend passes everything through regardless of the selected array.
        // When toggled on, selected is initialised to all available options.
        cultureFilterActive: false,
        yHaplogroupFilterActive: false,
        mtdnaFilterActive: false,
        sourceFilterActive: false,

        // Selection arrays. Only meaningful when the corresponding filter is
        // active. Empty when filter is off.
        selectedCultures: [],
        selectedYHaplogroups: [],
        yHaplogroupSearchText: '',
        selectedMtdna: [],
        mtdnaSearchText: '',
        selectedSources: [],

        // Y-haplotree filter state (active when terms is non-empty)
        yHaplotreeTerms: [],
        yHaplotreeSearchInput: '',
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
            return this.meta.availableCultures || [];
        },

        // "All selected" means selected contains every available option.
        // Only meaningful when the filter is active.
        get allCulturesSelected() {
            return this.availableCultures.length > 0
                && this.selectedCultures.length === this.availableCultures.length;
        },
        
        get availableYHaplogroups() {
            return this.meta.filteredYHaplogroups || this.meta.availableYHaplogroups || [];
        },
        
        get allYHaplogroupsSelected() {
            return this.availableYHaplogroups.length > 0
                && this.selectedYHaplogroups.length === this.availableYHaplogroups.length;
        },
        
        get availableMtdna() {
            return this.meta.filteredMtdna || this.meta.availableMtdna || [];
        },
        
        get allMtdnaSelected() {
            return this.availableMtdna.length > 0
                && this.selectedMtdna.length === this.availableMtdna.length;
        },

        get availableSources() {
            return this.meta.availableSources || [];
        },

        get allSourcesSelected() {
            return this.availableSources.length > 0
                && this.selectedSources.length === this.availableSources.length;
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
                const configResponse = await fetch('/api/config');
                this.config = await configResponse.json();
                console.log('Config loaded:', this.config);
                
                initMap(this.config);
                
                const stats = this.config.dateStatistics;
                this.dateScale = PiecewiseScale.create(
                    stats.min,
                    stats.max,
                    stats.p2,
                    stats.p98
                );
                
                this.filters.dateMin = stats.p2;
                this.filters.dateMax = stats.p98;
                
                this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
                this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
                
                // All selection filters start inactive with empty arrays.
                this.cultureFilterActive = false;
                this.selectedCultures = [];
                this.yHaplogroupFilterActive = false;
                this.selectedYHaplogroups = [];
                this.mtdnaFilterActive = false;
                this.selectedMtdna = [];
                this.sourceFilterActive = false;
                this.selectedSources = [];

                this.filters.includeUndated = this.config.defaults.includeUndated;
                this.filters.includeNoCulture = this.config.defaults.includeNoCulture;
                this.filters.includeNoYHaplogroup = this.config.defaults.includeNoYHaplogroup;
                this.filters.includeNoMtdna = this.config.defaults.includeNoMtdna;
                this.colorRamp = this.config.defaults.colorRamp;
                this.cultureColorRamp = this.config.defaults.cultureColorRamp;
                this.yHaplogroupColorRamp = this.config.defaults.yHaplogroupColorRamp;
                this.mtdnaColorRamp = this.config.defaults.mtdnaColorRamp;
                this.yHaplotreeColorRamp = this.config.defaults.yHaplotreeColorRamp || 'viridis';
                
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
                cultureFilterActive: this.cultureFilterActive,
                selectedCultures: this.selectedCultures,
                includeNoCulture: this.filters.includeNoCulture,
                yHaplogroupFilterActive: this.yHaplogroupFilterActive,
                yHaplogroupSearchText: this.yHaplogroupSearchText,
                selectedYHaplogroups: this.selectedYHaplogroups,
                includeNoYHaplogroup: this.filters.includeNoYHaplogroup,
                mtdnaFilterActive: this.mtdnaFilterActive,
                mtdnaSearchText: this.mtdnaSearchText,
                selectedMtdna: this.selectedMtdna,
                includeNoMtdna: this.filters.includeNoMtdna,
                yHaplotreeTerms: this.yHaplotreeTerms,
                sourceFilterActive: this.sourceFilterActive,
                selectedSources: this.selectedSources,
                colorBy: this.colorBy,
                colorRamp: this.colorRamp,
                cultureColorRamp: this.cultureColorRamp,
                yHaplogroupColorRamp: this.yHaplogroupColorRamp,
                mtdnaColorRamp: this.mtdnaColorRamp,
                yHaplotreeColorRamp: this.yHaplotreeColorRamp
            };
        },

        /**
         * Cascade helper: return the updated selected array after a response.
         *
         * Rules:
         *   - Filter inactive → return [] (irrelevant; backend ignores selection)
         *   - Filter active + was all-selected → expand to full new available set
         *   - Filter active + partial selection → prune options no longer available,
         *     but do NOT add newly available options
         *
         * "Was all-selected" is evaluated against oldAvailableCount, captured
         * before this.meta is overwritten with the new response.
         */
        cascadeSelection(filterActive, selected, oldAvailableCount, newAvailable) {
            if (!filterActive) {
                return [];
            }
            const wasAllSelected = oldAvailableCount > 0
                && selected.length === oldAvailableCount;
            if (wasAllSelected) {
                return [...newAvailable];
            }
            // Partial selection: prune items that are no longer available
            return selected.filter(s => newAvailable.includes(s));
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

                // Capture old available counts before overwriting meta,
                // so cascadeSelection can detect "was all selected".
                const oldCultureCount    = this.availableCultures.length;
                const oldYHaplogroupCount = this.availableYHaplogroups.length;
                const oldMtdnaCount       = this.availableMtdna.length;
                const oldSourceCount      = this.availableSources.length;

                this.features = data.features;
                this.meta = data.meta;

                // Cascade each selection filter independently.
                this.selectedCultures = this.cascadeSelection(
                    this.cultureFilterActive,
                    this.selectedCultures,
                    oldCultureCount,
                    this.availableCultures
                );
                this.selectedYHaplogroups = this.cascadeSelection(
                    this.yHaplogroupFilterActive,
                    this.selectedYHaplogroups,
                    oldYHaplogroupCount,
                    this.availableYHaplogroups
                );
                this.selectedMtdna = this.cascadeSelection(
                    this.mtdnaFilterActive,
                    this.selectedMtdna,
                    oldMtdnaCount,
                    this.availableMtdna
                );
                this.selectedSources = this.cascadeSelection(
                    this.sourceFilterActive,
                    this.selectedSources,
                    oldSourceCount,
                    this.availableSources
                );
                
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
            
            this.filters.dateMin = stats.p2;
            this.filters.dateMax = stats.p98;
            this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
            this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
            
            // Reset all selection filters to inactive with empty arrays
            this.cultureFilterActive = false;
            this.selectedCultures = [];
            this.yHaplogroupFilterActive = false;
            this.selectedYHaplogroups = [];
            this.yHaplogroupSearchText = '';
            this.mtdnaFilterActive = false;
            this.selectedMtdna = [];
            this.mtdnaSearchText = '';
            this.sourceFilterActive = false;
            this.selectedSources = [];
            this.yHaplotreeTerms = [];
            this.yHaplotreeSearchInput = '';
            
            this.filters.includeUndated = this.config.defaults.includeUndated;
            this.filters.includeNoCulture = this.config.defaults.includeNoCulture;
            this.filters.includeNoYHaplogroup = this.config.defaults.includeNoYHaplogroup;
            this.filters.includeNoMtdna = this.config.defaults.includeNoMtdna;
            
            this.colorBy = null;
            this.colorRamp = this.config.defaults.colorRamp;
            this.cultureColorRamp = this.config.defaults.cultureColorRamp;
            this.yHaplogroupColorRamp = this.config.defaults.yHaplogroupColorRamp;
            this.mtdnaColorRamp = this.config.defaults.mtdnaColorRamp;
            this.yHaplotreeColorRamp = this.config.defaults.yHaplotreeColorRamp || 'viridis';
            
            this.applyFilters();
        },
        
        // ---------------------------------------------------------------------
        // Date Range Methods
        // ---------------------------------------------------------------------
        
        onSliderInput(which) {
            if (!this.dateScale) return;
            if (which === 'min') {
                this.filters.dateMax = Math.round(this.dateScale.toValue(1000-this.sliderPositions.min));
            } else {
                this.filters.dateMin = Math.round(this.dateScale.toValue(1000-this.sliderPositions.max));
            }
            this.applyFiltersDebounced();
        },
        
        onDateChange() {
            if (!this.dateScale) return;
            this.filters.dateMin = this.dateScale.clamp(this.filters.dateMin);
            this.filters.dateMax = this.dateScale.clamp(this.filters.dateMax);
            this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
            this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
            this.applyFilters();
        },
        
        sliderRangeStyle() {
            if (!this.dateScale) {
                return { left: '0%', width: '100%' };
            }
            return this.dateScale.rangeStyle(this.sliderPositions.min, this.sliderPositions.max);
        },
        
        // ---------------------------------------------------------------------
        // Color Methods
        // ---------------------------------------------------------------------
        
        onColorByAgeChange() {
            this.colorBy = this.colorBy === 'age' ? null : 'age';
            this.applyFilters();
        },
        
        onColorRampChange() {
            if (this.colorBy === 'age') this.applyFilters();
        },
        
        onColorByCultureChange() {
            this.colorBy = this.colorBy === 'culture' ? null : 'culture';
            this.applyFilters();
        },
        
        onCultureColorRampChange() {
            if (this.colorBy === 'culture') this.applyFilters();
        },
        
        // ---------------------------------------------------------------------
        // Culture Filter Methods
        // ---------------------------------------------------------------------

        /**
         * Toggle the culture filter on/off.
         * Turning on: initialise selected to all currently available options.
         * Turning off: clear selected (backend ignores it when inactive).
         */
        toggleCultureFilter() {
            this.cultureFilterActive = !this.cultureFilterActive;
            if (this.cultureFilterActive) {
                this.selectedCultures = [...this.availableCultures];
            } else {
                this.selectedCultures = [];
            }
            this.applyFilters();
        },

        selectedCulturesSummary() {
            if (!this.cultureFilterActive) return 'Filter off';
            const count = this.selectedCultures.length;
            if (count === 0) return 'None selected';
            if (this.allCulturesSelected) return 'All cultures';
            if (count === 1) return this.selectedCultures[0];
            return count + ' cultures selected';
        },

        toggleCulture(culture) {
            const index = this.selectedCultures.indexOf(culture);
            if (index === -1) {
                this.selectedCultures.push(culture);
            } else {
                this.selectedCultures.splice(index, 1);
            }
            this.applyFilters();
        },

        toggleAllCultures() {
            if (this.allCulturesSelected) {
                this.selectedCultures = [];
            } else {
                this.selectedCultures = [...this.availableCultures];
            }
            this.applyFilters();
        },
        
        isCultureSelected(culture) {
            return this.selectedCultures.includes(culture);
        },

        cultureLegendItems() {
            return this.meta.cultureLegend || [];
        },
        
        // ---------------------------------------------------------------------
        // Y-Haplogroup Filter Methods
        // ---------------------------------------------------------------------

        toggleYHaplogroupFilter() {
            this.yHaplogroupFilterActive = !this.yHaplogroupFilterActive;
            if (this.yHaplogroupFilterActive) {
                this.selectedYHaplogroups = [...this.availableYHaplogroups];
            } else {
                this.selectedYHaplogroups = [];
            }
            this.applyFilters();
        },
        
        selectedYHaplogroupsSummary() {
            if (!this.yHaplogroupFilterActive) return 'Filter off';
            const count = this.selectedYHaplogroups.length;
            if (count === 0) return 'None selected';
            if (this.allYHaplogroupsSelected) return 'All haplogroups';
            if (count === 1) return this.selectedYHaplogroups[0];
            return count + ' haplogroups selected';
        },
        
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
        
        toggleAllYHaplogroups() {
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
        
        isYHaplogroupSelected(haplogroup) {
            return this.selectedYHaplogroups.includes(haplogroup);
        },
        
        onYHaplogroupSearch() {
            this.applyFilters();
        },
        
        yHaplogroupLegendItems() {
            return this.meta.yHaplogroupLegend || [];
        },
        
        onColorByYHaplogroupChange() {
            this.colorBy = this.colorBy === 'y_haplogroup' ? null : 'y_haplogroup';
            this.applyFilters();
        },
        
        onYHaplogroupColorRampChange() {
            if (this.colorBy === 'y_haplogroup') this.applyFilters();
        },
        
        // ---------------------------------------------------------------------
        // mtDNA Filter Methods
        // ---------------------------------------------------------------------

        toggleMtdnaFilter() {
            this.mtdnaFilterActive = !this.mtdnaFilterActive;
            if (this.mtdnaFilterActive) {
                this.selectedMtdna = [...this.availableMtdna];
            } else {
                this.selectedMtdna = [];
            }
            this.applyFilters();
        },
        
        selectedMtdnaSummary() {
            if (!this.mtdnaFilterActive) return 'Filter off';
            const count = this.selectedMtdna.length;
            if (count === 0) return 'None selected';
            if (this.allMtdnaSelected) return 'All haplogroups';
            if (count === 1) return this.selectedMtdna[0];
            return count + ' haplogroups selected';
        },
        
        toggleMtdna(mtdna) {
            const index = this.selectedMtdna.indexOf(mtdna);
            if (index === -1) {
                this.selectedMtdna.push(mtdna);
            } else {
                this.selectedMtdna.splice(index, 1);
            }
            this.applyFilters();
        },
        
        toggleAllMtdna() {
            if (this.allMtdnaSelected) {
                this.selectedMtdna = [];
            } else {
                this.selectedMtdna = [...this.availableMtdna];
            }
            this.applyFilters();
        },
        
        isMtdnaSelected(mtdna) {
            return this.selectedMtdna.includes(mtdna);
        },
        
        onMtdnaSearch() {
            this.applyFilters();
        },
        
        mtdnaLegendItems() {
            return this.meta.mtdnaLegend || [];
        },
        
        onColorByMtdnaChange() {
            this.colorBy = this.colorBy === 'mtdna' ? null : 'mtdna';
            this.applyFilters();
        },
        
        onMtdnaColorRampChange() {
            if (this.colorBy === 'mtdna') this.applyFilters();
        },
        
        // ---------------------------------------------------------------------
        // Source Filter Methods
        // ---------------------------------------------------------------------

        toggleSourceFilter() {
            this.sourceFilterActive = !this.sourceFilterActive;
            if (this.sourceFilterActive) {
                this.selectedSources = [...this.availableSources];
            } else {
                this.selectedSources = [];
            }
            this.applyFilters();
        },

        selectedSourcesSummary() {
            if (!this.sourceFilterActive) return 'Filter off';
            const count = this.selectedSources.length;
            if (count === 0) return 'None selected';
            if (this.allSourcesSelected) return 'All studies';
            if (count === 1) return this.selectedSources[0];
            return count + ' studies selected';
        },

        toggleSource(source) {
            const index = this.selectedSources.indexOf(source);
            if (index === -1) {
                this.selectedSources.push(source);
            } else {
                this.selectedSources.splice(index, 1);
            }
            this.applyFilters();
        },

        toggleAllSources() {
            if (this.allSourcesSelected) {
                this.selectedSources = [];
            } else {
                this.selectedSources = [...this.availableSources];
            }
            this.applyFilters();
        },

        isSourceSelected(source) {
            return this.selectedSources.includes(source);
        },

        // ---------------------------------------------------------------------
        // Y-Haplotree Filter Methods
        // ---------------------------------------------------------------------

        addYHaplotreeTerm() {
            const term = this.yHaplotreeSearchInput.trim();
            if (!term || this.yHaplotreeTerms.includes(term)) {
                this.yHaplotreeSearchInput = '';
                return;
            }
            // Mutual exclusivity: turn off y_haplogroup filter
            this.yHaplogroupFilterActive = false;
            this.selectedYHaplogroups = [];
            if (this.colorBy === 'y_haplogroup') this.colorBy = null;

            this.yHaplotreeTerms.push(term);
            this.yHaplotreeSearchInput = '';
            this.applyFilters();
        },

        onYHaplotreeSearchKeydown(event) {
            if (event.key === 'Enter') {
                event.preventDefault();
                this.addYHaplotreeTerm();
            }
        },

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

        clearYHaplotreeTerms() {
            this.yHaplotreeTerms = [];
            this.yHaplotreeSearchInput = '';
            if (this.colorBy === 'y_haplotree') this.colorBy = null;
            this.applyFilters();
        },

        yHaplotreeLegendItems() {
            return this.meta.yHaplotreeLegend || [];
        },

        onColorByYHaplotreeChange() {
            this.colorBy = this.colorBy === 'y_haplotree' ? null : 'y_haplotree';
            this.applyFilters();
        },

        onYHaplotreeColorRampChange() {
            if (this.colorBy === 'y_haplotree') this.applyFilters();
        },

        // ---------------------------------------------------------------------
        // Color Ramp Utilities
        // ---------------------------------------------------------------------
        
        colorRampGradient(rampName) {
            if (!this.config || !this.config.colorRamps[rampName]) {
                return 'transparent';
            }
            const colors = this.config.colorRamps[rampName].colors;
            return 'linear-gradient(to right, ' + colors.join(', ') + ')';
        }
    };
}
