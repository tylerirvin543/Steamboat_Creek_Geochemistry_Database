# White (1968) Plate 2 section export: pixel anchors -> elevations.
# Inputs are hand-checked pixel measurements (rows = y, cols = x of the plate raster);
# the plate is not georeferenced, so only elevation is converted here.
# Elevation model per scale group: elev_ft ~ (y - slope * x), where slope is the
# common scan tilt fitted from the box-bottom lines.
# Stated surface altitude and drilled depth (White 1964, 1968) are kept in a separate
# table and used only to check the plate, never to overwrite what was measured.

build_white_plate2_export <- function(
    anchors_csv = "data/raw/arcgis/white_plate2/white_plate2_anchors.csv",
    scales_csv  = "data/raw/arcgis/white_plate2/white_plate2_box_scales.csv",
    stated_csv  = "data/raw/arcgis/white_plate2/white_plate2_stated_values.csv",
    out_dir     = "data/derived/white_plate2") {
  a  <- utils::read.csv(anchors_csv, stringsAsFactors = FALSE)
  sc <- utils::read.csv(scales_csv, stringsAsFactors = FALSE)
  st <- utils::read.csv(stated_csv, stringsAsFactors = FALSE)
  slope <- unique(a$tilt_slope_px_per_px)
  stopifnot(length(slope) == 1)

  group_of <- c(low_terrace_gs1 = "gs1_row", south_steamboat_well = "gs1_row",
                high_terrace_gs2 = "gs2", main_terrace_gs5 = "gs5_row",
                main_terrace_gs3 = "gs5_row", main_terrace_gs4 = "gs5_row",
                main_terrace_gs8 = "gs5_row", sinter_hill_gs6 = "gs6")

  fits <- lapply(split(sc, sc$scale_group), function(d) {
    d$y_norm <- d$tick_y_px - slope * d$tick_x_px
    f <- stats::lm(elev_ft ~ y_norm, data = d)
    list(fit = f, inv = stats::lm(y_norm ~ elev_ft, data = d),
         ft_per_px = -unname(stats::coef(f)["y_norm"]),
         resid_ft = stats::sd(stats::resid(f)), n = nrow(d))
  })
  to_elev <- function(grp, x, y) {
    if (is.na(x) || is.na(y)) return(NA_real_)
    unname(stats::predict(fits[[grp]]$fit, data.frame(y_norm = y - slope * x)))
  }
  to_y <- function(grp, x, elev) {
    if (is.na(x) || is.na(elev)) return(NA_real_)
    unname(stats::predict(fits[[grp]]$inv, data.frame(elev_ft = elev))) + slope * x
  }

  a <- merge(a, st[, c("anchor_id", "collar_px", "collar_method", "stated_surface_ft", "stated_depth_ft")],
             by = "anchor_id", all.x = TRUE, sort = FALSE)
  a$scale_group <- unname(group_of[a$anchor_id])
  xref <- ifelse(is.na(a$x_px), 1803, a$x_px)
  a$ft_per_px <- round(sapply(a$scale_group, function(g) fits[[g]]$ft_per_px), 3)
  a$bottom_line_elev_ft <- round(mapply(to_elev, a$scale_group, xref, a$y_bottom_fit_px))
  a$collar_elev_ft <- round(mapply(to_elev, a$scale_group, a$x_px, a$collar_px))
  a$collar_elev_m <- round(a$collar_elev_ft * 0.3048, 1)
  a$hole_bottom_elev_ft <- round(mapply(to_elev, a$scale_group, a$x_px, a$hole_bottom_px))
  a$hole_bottom_elev_m <- round(a$hole_bottom_elev_ft * 0.3048, 1)
  a$drawn_depth_ft <- a$collar_elev_ft - a$hole_bottom_elev_ft

  # Plate vs stated values (difference = plate minus stated, ft)
  a$surface_diff_ft <- a$collar_elev_ft - a$stated_surface_ft
  a$stated_bottom_elev_ft <- round(a$stated_surface_ft - a$stated_depth_ft, 1)
  a$stated_bottom_px <- round(mapply(to_y, a$scale_group, a$x_px, a$stated_bottom_elev_ft), 1)
  a$bottom_diff_ft <- a$hole_bottom_elev_ft - a$stated_bottom_elev_ft
  a$depth_diff_ft <- a$drawn_depth_ft - a$stated_depth_ft

  # bottom_line_elev_ft is the fitted tilted bottom line: the geologic box bottom for gs5_row and gs2
  # (4000 ft), but the plate-frame line for gs1_row and gs6, so do not read it as box bottom there.
  # A hole whose stated bottom lies below the printed box bottom is clipped by the box on the plate
  a$clipped_by_box <- !is.na(a$stated_bottom_elev_ft) & a$scale_group %in% c("gs5_row", "gs2") & a$stated_bottom_elev_ft < a$bottom_line_elev_ft
  a$hole_flag <- ifelse(is.na(a$hole_bottom_px), "no hole line",
    ifelse(abs(a$hole_bottom_px - a$y_bottom_fit_px) < 8 | (a$scale_group == "gs1_row" & a$hole_bottom_elev_ft < 4230 & a$hole_bottom_elev_ft > 4190),
           "ends at box bottom", "ends inside box"))
  out <- a[, c("anchor_id", "status", "scale_group", "x_px", "collar_px", "collar_elev_ft", "collar_elev_m",
               "hole_bottom_px", "hole_bottom_elev_ft", "hole_bottom_elev_m", "drawn_depth_ft",
               "stated_surface_ft", "surface_diff_ft", "stated_depth_ft", "depth_diff_ft",
               "stated_bottom_elev_ft", "stated_bottom_px", "bottom_diff_ft",
               "ft_per_px", "bottom_line_elev_ft", "hole_flag", "clipped_by_box", "collar_method", "notes")]
  out <- out[match(utils::read.csv(anchors_csv)$anchor_id, out$anchor_id), ]
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(out, file.path(out_dir, "white_plate2_section_export.csv"), row.names = FALSE)
  scales <- do.call(rbind, lapply(names(fits), function(g)
    data.frame(scale_group = g, n_ticks = fits[[g]]$n, ft_per_px = round(fits[[g]]$ft_per_px, 3),
               resid_sd_ft = round(fits[[g]]$resid_ft, 1))))
  utils::write.csv(scales, file.path(out_dir, "white_plate2_scale_fit.csv"), row.names = FALSE)
  message("Wrote ", file.path(out_dir, "white_plate2_section_export.csv"))
  invisible(list(export = out, scales = scales))
}
