library(DiagrammeR)

g <- grViz("
digraph steamboat_poster {

graph [
  layout = dot,
  rankdir = TB,
  nodesep = 1.1,
  ranksep = 1.8,
  label = 'Integrated Hydrothermal Database\nSupporting Geothermal Investigations at Steamboat Springs\n\n',
  labelloc = t,
  fontsize = 54,
  fontname = 'Helvetica-Bold',
  pad = 1.8
]

node [
  fontname = 'Helvetica-Bold',
  fontsize = 28,
  penwidth = 2,
  width = 5,
  height = 2
]

edge [
  color = '#666666',
  penwidth = 1.8,
  arrowsize = 0.8
]

# ==================================================
# DATA SOURCES
# ==================================================

node [shape=folder, style=filled, fillcolor='#C7E9C0']

Field [
  label='Field\nSampling'
]

Laboratory [
  label='Laboratory\nAnalyses'
]

Loggers [
  label='Temperature\nLoggers'
]
NDWR       [label='NDWR Wells']
USGS       [label='USGS Streamflow']

# ==================================================
# DATABASE
# ==================================================

Locations [
  shape=box,
  style=filled,
  fillcolor='#BDD7E7',
  label='Locations'
]

Samples [
  shape=box,
  style=filled,
  fillcolor='#BDD7E7',
  label='Samples'
]

FieldMeas [
  shape=box,
  style=filled,
  fillcolor='#FDAE6B',
  label='Field Measurements'
]

TempObs [
  shape=box,
  style=filled,
  fillcolor='#FDAE6B',
  label='Temperature\nTime Series'
]

Chemistry [
  shape=box,
  style=filled,
  fillcolor='#74C476',
  label='Water Chemistry'
]

Isotopes [
  shape=box,
  style=filled,
  fillcolor='#74C476',
  label='Stable Isotopes'
]

WaterLevels [
  shape=box,
  style=filled,
  fillcolor='#6BAED6',
  label='Groundwater Levels'
]

Streamflow [
  shape=box,
  style=filled,
  fillcolor='#6BAED6',
  label='Streamflow'
]

# ==================================================
# ANALYSES
# ==================================================

Thermal [
  shape=ellipse,
  style=filled,
  fillcolor='#FDAE6B',
  fontsize=32,
  width=5,
  height=2,
  label='Thermal\\nMonitoring'
]

Geochem [
  shape=ellipse,
  style=filled,
  fillcolor='#74C476',
  fontsize=32,
  width=5,
  height=2,
  label='Geochemical\\nInterpretation'
]

Hydrology [
  shape=ellipse,
  style=filled,
  fillcolor='#6BAED6',
  fontsize=32,
  width=5,
  height=2,
  label='Hydrogeologic\nAnalysis'
]

# ==================================================
# SYNTHESIS
# ==================================================

Research [
  shape=ellipse,
  style=filled,
  fillcolor='#E69F00',
  fontsize=38,
  penwidth=5,
  width=8,
  height=3,
  label='Heat Flux\nGeothermal Discharge\nConceptual Models'
]

# ==================================================
# QA/QC
# ==================================================

QC [
  shape=ellipse,
  style=filled,
  fillcolor='#F4B183',
  fontsize=24,
  width=4,
  height=1.8,
  penwidth=2,
  label='Data\nQA/QC'
]

# ==================================================
# OUTPUTS
# ==================================================

GeoPkg [
  shape=folder,
  style=filled,
  fillcolor='#D9D9D9',
  width=5,
  label='Geospatial Products'
]

Website [
  shape=folder,
  style=filled,
  fillcolor='#D9D9D9',
  width=5,
  label='Interactive Website'
]

# ==================================================
# MODELING
# ==================================================

ModelInputs [
  shape=ellipse,
  style=filled,
  fillcolor='#FFE699',
  width=5,
  label='Model Inputs'
]

PHREEQC [
  shape=ellipse,
  style=filled,
  fillcolor='#FFE699',
  width=5,
  label='PHREEQC Modeling'
]

# ==================================================
# RANKS
# ==================================================

{rank=same; Field Laboratory Loggers NDWR USGS}

{rank=same;
 Locations Samples
 Chemistry TempObs
 WaterLevels Streamflow}

{rank=same;
 Thermal Geochem Hydrology}

# ==================================================
# DATA FLOW
# ==================================================

Field -> Locations
Field -> Samples
Field -> FieldMeas

Laboratory -> Chemistry
Laboratory -> Isotopes

Loggers -> TempObs

NDWR -> WaterLevels
USGS -> Streamflow

Locations -> Samples

Samples -> Chemistry
Samples -> Isotopes

FieldMeas -> Thermal
TempObs   -> Thermal

Chemistry -> Geochem
Isotopes  -> Geochem

WaterLevels -> Hydrology
Streamflow  -> Hydrology

Thermal   -> Research
Geochem   -> Research
Hydrology -> Research

Research -> QC

QC -> GeoPkg
QC -> Website
QC -> ModelInputs

ModelInputs -> PHREEQC

}
")

g

library(DiagrammeRsvg)
library(rsvg)

svg_txt <- export_svg(g)

rsvg_png(
  charToRaw(svg_txt),
  file = "steamboat_poster_workflow.png",
  width = 9000,
  height = 6000
)