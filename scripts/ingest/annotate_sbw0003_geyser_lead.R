# Adds the Lindsey et al. (2026) pipe parameters and the NBMG No. 32 Geyser Well
# remark to SBW_0003 and its lead. Appends once (marker-guarded), never overwrites.
library(DBI)
annotate_sbw0003_geyser_lead <- function(con) {
  wid <- dbGetQuery(con, "SELECT well_id FROM Wells WHERE well_name = 'SBW_0003'")$well_id
  if (length(wid) != 1) return(invisible(NULL))
  m1 <- "[Lindsey 2026 / NBMG remark]"
  n <- dbExecute(con, "UPDATE Wells SET notes = COALESCE(notes || ' ', '') || ? WHERE well_id = ? AND COALESCE(notes,'') NOT LIKE ?",
    params = list(paste0(m1, " Lindsey et al. (2026): uncapped shallow pipe of unclear origin, about 15-20 m deep; on 3 June 2025 it threw boiling water and steam about 30 m, then discharged episodically before being capped; sample SBG001 was taken from it during discharge. Construction, driller and lithology are not given. NBMG lists a nearby abandoned 'No. 32 Geyser Well' (API 27-031-80032, TD 13 m, 115 C) with the remark: reported geysering 70 ft at nearly one-week intervals 1945-1952. No lithology is assigned to this well; use nearby logs as a labelled proxy."),
                  wid, paste0("%", m1, "%")))
  n2 <- dbExecute(con, "UPDATE Well_Identity_Leads SET rationale = rationale || ' ' || ? WHERE well_id = ? AND lead_source = 'nbmg_geothermal_wells' AND lead_ref = '27-031-80032' AND rationale NOT LIKE ?",
    params = list("NBMG compilation remark: reported geysering 70 ft at nearly one-week intervals between 1945 and 1952; TD temperature 115 C (documented geyser well).", wid, "%one-week intervals%"))
  message("  -> SBW_0003 annotated (", n, " note, ", n2, " lead rationale updated)")
  invisible(TRUE)
}
