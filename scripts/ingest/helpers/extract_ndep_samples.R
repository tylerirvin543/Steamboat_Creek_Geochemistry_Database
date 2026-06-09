# --------------------------------------------------
# Extract Sampling_Events and Samples from
# NDEP NormalizedData.csv
# --------------------------------------------------

library(dplyr)
library(lubridate)

# --------------------------------------------------
# 1. Extract Sampling_Events
# --------------------------------------------------

extract_ndep_events <- function(norm_df) {
  
  events <- norm_df |>
    mutate(
      external_event_id = paste(
        STATIONCODE,
        as.Date(SAMPLEDATETIME),
        sep = "_"
      )
    ) |>
    group_by(external_event_id) |>
    reframe(
      external_event_id = first(external_event_id),
      date = as.Date(min(SAMPLEDATETIME, na.rm = TRUE)),
      observer = first(ORGANIZATION[!is.na(ORGANIZATION)]),
      purpose = "historical",
      weather_conditions = NA_character_,
      notes = "NDEP sampling event"
    )
  
  events
}


# --------------------------------------------------
# 2. Extract Samples
# --------------------------------------------------

extract_ndep_samples <- function(norm_df) {
  
  samples <- norm_df |>
    mutate(
      external_event_id = paste(
        STATIONCODE,
        as.Date(SAMPLEDATETIME),
        sep = "_"
      ),
      collection_time = as.POSIXct(SAMPLEDATETIME, tz = "UTC")
    ) |>
    distinct(
      external_event_id,
      STATIONCODE,
      collection_time,
      .keep_all = TRUE
    ) |>
    transmute(
      external_event_id,
      external_station_code = STATIONCODE,
      collection_time,
      sample_type = "water",
      filtered = NA_integer_,
      preservation_method = ACTIVITYTYPE,
      depth_m = SAMPLEDEPTH,
      notes = SAMPLECOMMENT,
      external_sample_id = SOURCESAMPLEID
    )
  
  samples
}