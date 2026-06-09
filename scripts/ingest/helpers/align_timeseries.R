align_timeseries <- function(
    left_df,
    right_df,
    left_time,
    right_time,
    group_col = NULL,
    max_diff_minutes = 60,
    verbose = TRUE
) {
  
  library(data.table)
  
  left_dt  <- as.data.table(copy(left_df))
  right_dt <- as.data.table(copy(right_df))
  
  # -------------------------------
  # Safe parse
  # -------------------------------
  safe_parse_time <- function(x) {
    
    # ✅ already POSIX → return immediately
    if (inherits(x, "POSIXct")) return(x)
    
    # ✅ numeric epoch
    if (is.numeric(x)) {
      return(as.POSIXct(x, origin = "1970-01-01", tz = "UTC"))
    }
    
    # ✅ character ISO
    if (is.character(x)) {
      return(as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
    }
    
    # ✅ fallback (prevents NULL failure)
    return(rep(NA, length(x)))
  }
  
  
  message("  → Removed bad temp rows: ", sum(is.na(left_dt$left_time)))
  message("  → Removed bad USGS rows: ", sum(is.na(right_dt$right_time)))
  
  left_dt[, left_time := safe_parse_time(get(left_time))]
  right_dt[, right_time := safe_parse_time(get(right_time))]
  
  left_dt  <- left_dt[!is.na(left_time)]
  right_dt <- right_dt[!is.na(right_time)]
  
  # -------------------------------
  # Grouped rolling join (FIXED)
  # -------------------------------
  if (!is.null(group_col)) {
    
    left_dt  <- left_dt[!is.na(get(group_col))]
    right_dt <- right_dt[!is.na(get(group_col))]
    
    setorderv(left_dt,  c(group_col, "left_time"))
    setorderv(right_dt, c(group_col, "right_time"))
    
    # ✅ preserve left_time explicitly BEFORE join
    # preserve left time BEFORE join
    left_dt[, join_time := left_time]
    
    result <- right_dt[
      left_dt,
      on = .(right_time = left_time),
      roll = "nearest"
    ]
    
    # restore AFTER join
    result[, left_time := join_time]
    result[, join_time := NULL]
  } else {
    
    setorderv(left_dt,  "left_time")
    setorderv(right_dt, "right_time")
    
    # ✅ preserve BOTH times
    left_dt[, join_left_time := left_time]
    right_dt[, join_right_time := right_time]
    
    # ✅ perform join (left-preserving)
    result <- left_dt[
      right_dt,
      on = .(left_time = right_time),
      roll = "nearest"
    ]
    
    # ✅ restore BOTH safely
    if (!"join_left_time" %in% names(result) ||
        !"join_right_time" %in% names(result)) {
      stop("Join failed to preserve time columns")
    }
    
    result[, left_time  := join_left_time]
    result[, right_time := join_right_time]
    
    result[, c("join_left_time", "join_right_time") := NULL]
  }
  
  # -------------------------------
  # Time diff
  # -------------------------------
  message("  → Rows after join (pre-clean): ", nrow(result))
  
  # ✅ remove unmatched rows safely
  result <- result[!is.na(right_time) & !is.na(left_time)]
  
  message("  → Rows after removing unmatched: ", nrow(result))
  
  bad_left  <- result[is.na(left_time)]
  bad_right <- result[is.na(right_time)]
  
  str(result$left_time)
  str(result$right_time)
  
  cat("Bad left_time rows:", nrow(bad_left), "\n")
  cat("Bad right_time rows:", nrow(bad_right), "\n")
  
  if (nrow(bad_left) > 0) {
    print(head(bad_left$left_time, 10))
  }
  
  if (nrow(bad_right) > 0) {
    print(head(bad_right$right_time, 10))
  }
  
  if (any(is.na(result$left_time)) || any(is.na(result$right_time))) {
    stop("NA values detected in time columns after join")
  }
  
  stopifnot(inherits(result$left_time, "POSIXct"))
  stopifnot(inherits(result$right_time, "POSIXct"))
  
  
  cat("left_time class:\n")
  print(class(result$left_time))
  
  cat("right_time class:\n")
  print(class(result$right_time))
  
  
  # ✅ compute diff
  result[, time_diff_min := abs(
    as.numeric(difftime(right_time, left_time, units = "mins"))
  )]
  
  if (verbose) {
    message("  → Rows before filtering: ", nrow(result))
    print(summary(result$time_diff_min))
  }
  
  filtered <- result[time_diff_min <= max_diff_minutes]
  
  if (verbose) {
    message("  → Rows after filtering: ", nrow(filtered))
  }
  
  return(filtered)
}