library(DiagrammeR)

grViz("
digraph geochem_db {

  graph [layout = dot, rankdir = TB, nodesep = 0.6, ranksep = 0.8]

  node [shape = box, style = filled, fontname = Helvetica]

  # Data sources
  \"NDEP DATA\" [fillcolor=\"#C7E9C0\"]
  \"FIELD DATA\" [fillcolor=\"#C7E9C0\"]

  # Staging
  \"STAGING_NDEP_WQ\" [fillcolor=\"#FFF7BC\"]

  # Core tables
  \"Locations\" [fillcolor=\"#BDD7E7\"]
  \"Sampling_Events\" [fillcolor=\"#BDD7E7\"]
  \"Samples\" [fillcolor=\"#BDD7E7\"]
  \"Field_Measurements\" [fillcolor=\"#BDD7E7\"]
  \"Lab_Analyses\" [fillcolor=\"#BDD7E7\"]
  \"Data_Sources\" [fillcolor=\"#BDD7E7\"]

  # Derived modeling layer
  \"PHREEQC_Solutions\" [fillcolor=\"#FDD0A2\"]
  \"PHREEQC (Speciation)\" [fillcolor=\"#FC9272\"]
  \"PHREEQC Inverse Models\" [fillcolor=\"#FC9272\"]

  # Flows
  \"NDEP DATA\" -> \"STAGING_NDEP_WQ\"
  \"STAGING_NDEP_WQ\" -> \"Locations\"
  \"STAGING_NDEP_WQ\" -> \"Sampling_Events\"
  \"STAGING_NDEP_WQ\" -> \"Samples\"
  \"STAGING_NDEP_WQ\" -> \"Lab_Analyses\"

  \"FIELD DATA\" -> \"Samples\"
  \"FIELD DATA\" -> \"Field_Measurements\"
  \"FIELD DATA\" -> \"Lab_Analyses\"

  \"Lab_Analyses\" -> \"PHREEQC_Solutions\"
  \"Field_Measurements\" -> \"PHREEQC_Solutions\"

  \"PHREEQC_Solutions\" -> \"PHREEQC (Speciation)\"
  \"PHREEQC (Speciation)\" -> \"PHREEQC Inverse Models\"
}
")