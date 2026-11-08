# ------------------------------------------------------------
# ingest_collar_spring_observations.R
#
# Loads data/raw/historical/collar1990_appendixA_spring_observations.csv (made
# by scripts/ingest/helpers/parse_collar_appendix_a.R and reviewable by hand)
# into Spring_Observations and links each row to a Locations row whose name
# carries the same spring number ('spring 12, 12sw', 'Hot spring 6, main
# terrace ACEC', 'spring 25ss', ...). Idempotent on obs_key; rows still without
# a location are re-linked on every run, so new spring points join up as soon as
# they are ingested. Writes data/derived/collar_appendixA_spring_coverage.csv.
# ------------------------------------------------------------
suppressPackageStartupMessages({library(DBI); library(readr)})

.spring_location_lookup <- function(con) {
  loc <- dbGetQuery(con, "SELECT location_id, name FROM Locations")
  rows <- lapply(seq_len(nrow(loc)), function(i) {
    n <- tolower(loc$name[i])
    m <- regmatches(n, regexec("^(?:hot )?spring ([0-9]+[a-z]{0,2}(?:\\s*,\\s*[0-9]+[a-z]{0,2})*)(?:[ ,].*)?$", n, perl = TRUE))[[1]]
    if (!length(m)) return(NULL)
    ids <- trimws(strsplit(m[2], ",")[[1]])
    data.frame(spring_id = ids[nzchar(ids)], location_id = loc$location_id[i], stringsAsFactors = FALSE)
  })
  lk <- do.call(rbind, rows)
  if (is.null(lk)) return(data.frame(spring_id = character(), location_id = integer()))
  dup <- lk$spring_id[duplicated(lk$spring_id)]
  if (length(dup)) warning("Spring number(s) on more than one Locations row, using the lowest location_id: ", paste(unique(dup), collapse = ", "))
  lk[order(lk$location_id), ][!duplicated(lk$spring_id[order(lk$location_id)]), ]
}

ingest_collar_spring_observations <- function(con, csv_path = "data/raw/historical/collar1990_appendixA_spring_observations.csv",
                                              coverage_csv = "data/derived/collar_appendixA_spring_coverage.csv") {
  message("---- Ingesting Collar (1990) Appendix A spring observations ----")
  if (!file.exists(csv_path)) { message("  no file at ", csv_path); return(invisible(NULL)) }
  d <- read_csv(csv_path, show_col_types = FALSE, col_types = cols(.default = col_character(), temperature_c = col_double(),
         depth_to_water_ft = col_double(), depth_alt_ft = col_double(), flow_lpm = col_double(), depth_estimated = col_logical()))
  lk <- .spring_location_lookup(con)
  d$location_id <- lk$location_id[match(d$spring_id, lk$spring_id)]
  have <- dbGetQuery(con, "SELECT obs_key FROM Spring_Observations")$obs_key
  new <- d[!(d$obs_key %in% have), ]
  if (nrow(new)) {
    dbWriteTable(con, "Spring_Observations", data.frame(
      obs_key = new$obs_key, location_id = new$location_id, spring_id = new$spring_id, id_range_end = new$id_range_end, terrace = new$terrace,
      obs_date = new$obs_date, date_note = new$date_note, source_code = new$source_code, source_name = new$source_name, status = new$status,
      temperature_c = new$temperature_c, depth_to_water_ft = new$depth_to_water_ft, depth_basis = new$depth_basis,
      depth_estimated = as.integer(new$depth_estimated), depth_alt_ft = new$depth_alt_ft, depth_alt_source = new$depth_alt_source,
      flow_lpm = new$flow_lpm, raw_text = new$raw_text, source_document = new$source_document, stringsAsFactors = FALSE), append = TRUE)
  }
  relinked <- 0L
  open <- dbGetQuery(con, "SELECT DISTINCT spring_id FROM Spring_Observations WHERE location_id IS NULL")$spring_id
  for (s in intersect(open, lk$spring_id))
    relinked <- relinked + dbExecute(con, "UPDATE Spring_Observations SET location_id = ? WHERE spring_id = ? AND location_id IS NULL", params = list(lk$location_id[lk$spring_id == s], s))
  all <- dbGetQuery(con, "SELECT spring_id, terrace, location_id, obs_date, status FROM Spring_Observations")
  cov <- do.call(rbind, lapply(split(all, all$spring_id), function(g) data.frame(spring_id = g$spring_id[1], terrace = g$terrace[1], n_obs = nrow(g),
           first = min(g$obs_date), last = max(g$obs_date), n_dates = length(unique(g$obs_date)), has_location = any(!is.na(g$location_id)), stringsAsFactors = FALSE)))
  cov <- cov[order(-cov$n_obs), ]
  dir.create(dirname(coverage_csv), showWarnings = FALSE, recursive = TRUE); write.csv(cov, coverage_csv, row.names = FALSE)
  message("  -> ", nrow(new), " new observation(s); ", relinked, " re-linked; ", sum(cov$has_location), " of ", nrow(cov), " spring IDs have a location (",
          sum(cov$n_obs[cov$has_location]), " of ", sum(cov$n_obs), " observations).")
  invisible(list(inserted = nrow(new), relinked = relinked, coverage = cov))
}
