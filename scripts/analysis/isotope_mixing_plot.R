# ==========================================================
# ISOTOPE MIXING PLOT - Lower Sinter Terrace Hydrothermal System
# Steamboat Hills Geothermal System, NV
#
# Purpose:
#   delta-2H vs delta-18O plot used to evaluate whether the 2025 Lower
#   Sinter Terrace eruption represents (a) activation of a chemically
#   distinct geothermal source, or (b) redistribution of pre-existing
#   hydrothermal fluids within the existing conduit network. If the
#   reactivated fissure and downstream creek samples plot within the
#   pre-existing thermal-water field (rather than as a distinct
#   endmember), that supports (b).
#
# Data source:
#   database/geochem_demo.sqlite -> Isotope_Analyses + Samples + Locations
#   Current dataset: 8 sites, 16 measurements (d18O + dD each), no
#   replicate samples beyond one pair per site. This is the full
#   isotope dataset available as of 2026-08; re-run once more field
#   samples/isotope results are ingested (e.g. into
#   geochem_operational.sqlite) to refresh the figure.
#
# Known caveats baked into this script (flagged so they aren't silently
# assumed later):
#   1. Site grouping (Creek/Spring/Well/Fissure) shown on the poster does
#      NOT match Locations.site_type as stored in the database (SBRR/SBBV
#      are typed 'transect', SBF_0001 is 'fumarole', SBS_0002 is 'seep').
#      The mapping below is a display-only lookup for this figure; it does
#      not change the database. SBS_0002 (a seep) is grouped with Spring
#      for this legend per project convention.
#   2. No local meteoric water line (LMWL) has been measured for this
#      site, so none is drawn here - only the GMWL (Craig, 1961) is
#      shown. Add a measured/regional LMWL once one is available rather
#      than assuming a slope/intercept.
#   3. Upstream/downstream order for the creek mixing arrow (SBRR -> SBBV)
#      is set from field station identity (per the poster: SBRR is the
#      upstream Rhodes Road station, SBBV is downstream at Bella Vista),
#      not inferred from the placeholder demo lat/long values.
#   4. "Abandoned Well" (SBW_0001) and "Resort Well" (SBW_0002) are
#      narrative labels supplied for the poster, not values stored in the
#      database - update the site_map lookup below if well status changes.
#   5. The dashed "inferred" segment is drawn pointing FROM the thermal
#      field's centroid TOWARD SBBV (i.e. downstream), representing
#      thermal inflow reaching the creek - not the creek trending toward
#      the field. Direction matters here and was flipped deliberately.
# ==========================================================

library(DBI)
library(RSQLite)
library(dplyr)
library(tidyr)
library(ggplot2)
library(ggrepel)

# -------------------------
# 1. Pull isotope data from the database
# -------------------------

con <- dbConnect(RSQLite::SQLite(), "database/geochem_demo.sqlite")

iso_raw <- dbGetQuery(con, "
  SELECT
    l.name,
    l.site_type,
    i.analyte,
    i.value
  FROM Isotope_Analyses i
  JOIN Samples s   ON i.sample_id = s.sample_id
  JOIN Locations l ON s.location_id = l.location_id
  WHERE i.value IS NOT NULL
")

dbDisconnect(con)

iso_wide <- iso_raw %>%
  mutate(
    analyte_clean = case_when(
      grepl("18", analyte)                            ~ "d18O",
      grepl("d2|deuter", analyte, ignore.case = TRUE)  ~ "d2H",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(analyte_clean)) %>%
  select(name, analyte_clean, value) %>%
  pivot_wider(names_from = analyte_clean, values_from = value)

# -------------------------
# 2. Display-only site grouping / labeling (see caveats #1, #4 above)
# -------------------------

site_map <- tribble(
  ~name,      ~group,    ~label,                  ~stream_position,
  "SBRR",     "Creek",   "SBRR (upstream)",        1,
  "SBBV",     "Creek",   "SBBV (downstream)",      2,
  "SBS_0001", "Spring",  "Spring 1",                NA,
  "SBS_0002", "Spring",  "Spring 2 (seep)",         NA,
  "SBS_0003", "Spring",  "Spring 3",                NA,
  "SBW_0001", "Well",    "Abandoned Well",          NA,
  "SBW_0002", "Well",    "Resort Well",             NA,
  "SBF_0001", "Fissure", "Reactivated Fissure",     NA
)

iso_wide <- iso_wide %>%
  inner_join(site_map, by = "name") %>%
  filter(!is.na(d18O), !is.na(d2H))

# -------------------------
# 3. Thermal-water envelope (Spring/Well/Fissure, i.e. non-Creek)
# -------------------------

thermal_pts <- iso_wide %>% filter(group != "Creek")

hull <- thermal_pts[chull(thermal_pts$d18O, thermal_pts$d2H), ]

thermal_centroid <- thermal_pts %>%
  summarise(d18O = mean(d18O), d2H = mean(d2H))

fissure_pt <- thermal_pts %>% filter(group == "Fissure")

# -------------------------
# 4. Creek mixing trajectory (data-driven, not hardcoded coordinates)
# -------------------------

creek_pts <- iso_wide %>%
  filter(group == "Creek") %>%
  arrange(stream_position)

# Observed trajectory: upstream (SBRR) -> downstream (SBBV)
mixing_observed <- creek_pts %>% select(d18O, d2H)

# Inferred segment: drawn FROM the thermal-water field TOWARD SBBV
# (downstream), representing thermal inflow reaching the creek rather
# than the creek "reaching into" the field. Origin is the field centroid,
# nudged up off the Reactivated Fissure point; destination is SBBV. This
# is an inference/extrapolation (not an observed path), styled dashed to
# keep that distinction visually clear, and labeled below.
inferred_origin <- data.frame(
  d18O = thermal_centroid$d18O,
  d2H  = thermal_centroid$d2H + 1.0
)
mixing_inferred <- bind_rows(
  inferred_origin,
  creek_pts %>% slice_tail(n = 1) %>% select(d18O, d2H)
)

# -------------------------
# 5. Meteoric water line
# -------------------------

# Global Meteoric Water Line (Craig, 1961). No measured local meteoric
# water line (LMWL) exists for this site (see caveat #2 above), so only
# the GMWL is drawn - we do not assume/plot an LMWL.
gmwl <- list(slope = 8, intercept = 10)

# -------------------------
# 6. Plot
# -------------------------

group_colors <- c(
  Creek   = "#1f78b4",
  Spring  = "#33a02c",
  Well    = "#ff7f00",
  Fissure = "#e31a1c"
)

# Generous axis padding so annotations have room without overlapping points.
x_range <- range(iso_wide$d18O)
y_range <- range(iso_wide$d2H)
x_pad <- diff(x_range) * 0.30
y_pad <- diff(y_range) * 0.30
xlim <- c(x_range[1] - x_pad, x_range[2] + x_pad * 0.9)
ylim <- c(y_range[1] - y_pad * 0.5, y_range[2] + y_pad)

# Output size, used for arrow-shortening (gap) calculations below.
plot_width_in  <- 10
plot_height_in <- 7

# theme_bw(base_size = 15) with a top legend, title/subtitle, and caption
# leaves a panel that is noticeably smaller than the full figure - using
# the raw figure dimensions to convert data-space angles to on-screen
# angles overestimates the vertical scale. These values were measured
# directly from the rendered panel border (pixel-detected at 600 dpi),
# used only for the "parallel to the line" label angle below.
panel_width_in  <- 9.008  # measured from rendered panel border (600 dpi, 6000x4200 px)
panel_height_in <- 4.688 # measured from rendered panel border (600 dpi, 6000x4200 px)

# The 6 thermal points sit in a tight cluster -> let ggrepel resolve their
# label overlaps. The 2 creek points are well-separated, so their labels
# are placed by hand for a cleaner, more predictable layout.
thermal_labels <- iso_wide %>% filter(group != "Creek")
creek_labels   <- iso_wide %>% filter(group == "Creek")

# -------------------------
# 6a. Geometry helpers
# -------------------------

# Converts a data-space vector to device inches given the axis limits and
# output size set above, so on-screen arrow-gap sizes come out consistent
# regardless of the data's own units/range.
to_inches <- function(dx, dy) {
  c(
    dx / diff(xlim) * plot_width_in,
    dy / diff(ylim) * plot_height_in
  )
}

# Same idea, but scaled to the actual plotting panel (see panel_width_in/
# panel_height_in above) rather than the full figure - used for the
# on-screen angle of the "Downstream Isotopic Shift" label so it reads as
# parallel to the mixing arrow.
to_inches_panel <- function(dx, dy) {
  c(
    dx / diff(xlim) * panel_width_in,
    dy / diff(ylim) * panel_height_in
  )
}

# Pulls an arrow's endpoint back along its own line by a fixed on-screen
# distance, so the arrowhead lands just short of the target point/label
# instead of being drawn underneath it (point markers and text are drawn
# in later layers and would otherwise hide the arrowhead completely).
shorten_end <- function(x0, y0, x1, y1, gap_in = 0.11) {
  v_in <- to_inches(x1 - x0, y1 - y0)
  len_in <- sqrt(sum(v_in^2))
  frac <- if (len_in > gap_in) (len_in - gap_in) / len_in else 0
  data.frame(d18O = x0 + frac * (x1 - x0), d2H = y0 + frac * (y1 - y0))
}

mixing_observed_draw <- bind_rows(
  mixing_observed[1, ],
  shorten_end(
    mixing_observed$d18O[1], mixing_observed$d2H[1],
    mixing_observed$d18O[2], mixing_observed$d2H[2]
  )
)

# Arrowhead now falls at the SBBV end - shorten that end so it clears the
# point marker instead of being hidden underneath it.
mixing_inferred_draw <- bind_rows(
  mixing_inferred[1, ],
  shorten_end(
    mixing_inferred$d18O[1], mixing_inferred$d2H[1],
    mixing_inferred$d18O[2], mixing_inferred$d2H[2],
    gap_in = 0.11
  )
)

# Angle (in on-screen degrees) of the observed creek mixing line, so the
# "Downstream Isotopic Shift" label can be drawn parallel to it.
dx_data <- diff(mixing_observed$d18O)
dy_data <- diff(mixing_observed$d2H)
v_in <- to_inches_panel(dx_data, dy_data)
shift_label_angle <- atan2(v_in[2], v_in[1]) * 180 / pi

# Positioned close to the line itself (small perpendicular offset) rather
# than well above it.
shift_label_pos <- list(
  x = mixing_observed$d18O[1] + 0.45 * dx_data,
  y = mixing_observed$d2H[1] + 0.45 * dy_data + 0.8
)

# Label for the inferred/dashed segment: placed a third of the way along
# it (near the field end) and to the right, which keeps it clear of both
# the "SBRR (upstream)" label near the line's upper end and the arrowhead
# near SBBV.
inferred_pt <- list(
  x = mixing_inferred$d18O[1] + 0.4 * diff(mixing_inferred$d18O),
  y = mixing_inferred$d2H[1] + 0.4 * diff(mixing_inferred$d2H)
)
inferred_label_pos <- list(
  x = inferred_pt$x + 0.15,
  y = inferred_pt$y
)

# "Thermal Water Field" label sits just below the envelope, roughly
# centered above the Reactivated Fissure point so the leader arrow reads
# as pointing at the field generally (not at any one sample). The arrow
# itself is short, nearly vertical, and drawn with partial transparency
# so it doesn't compete visually with the fill/points beneath it.
field_label_pos <- list(
  x = fissure_pt$d18O + 0.15,
  y = min(hull$d2H) - y_pad * 0.45
)
field_leader_target <- data.frame(
  d18O = field_label_pos$x,
  d2H  = thermal_centroid$d2H + 1.6
)
field_leader_start <- data.frame(
  d18O = field_label_pos$x,
  d2H  = field_label_pos$y + y_pad * 0.22
)

iso_plot <- ggplot(iso_wide, aes(x = d18O, y = d2H)) +

  # Thermal-water field
  geom_polygon(
    data = hull,
    aes(x = d18O, y = d2H),
    inherit.aes = FALSE,
    fill = "red",
    alpha = 0.12
  ) +

  # GMWL
  geom_abline(
    slope = gmwl$slope,
    intercept = gmwl$intercept,
    linetype = "dashed",
    color = "grey50",
    linewidth = 0.7
  ) +

  # Observed creek mixing trajectory (upstream -> downstream), shortened
  # so the arrowhead is visible next to the SBBV point rather than
  # hidden underneath it.
  geom_path(
    data = mixing_observed_draw,
    aes(x = d18O, y = d2H),
    inherit.aes = FALSE,
    color = "#1f78b4",
    linewidth = 1,
    arrow = arrow(length = unit(0.25, "cm"))
  ) +

  # Inferred thermal-inflow segment, pointing downstream toward SBBV;
  # shortened so the arrowhead doesn't sit under the SBBV point.
  geom_path(
    data = mixing_inferred_draw,
    aes(x = d18O, y = d2H),
    inherit.aes = FALSE,
    color = "#1f78b4",
    linewidth = 1,
    linetype = 2,
    arrow = arrow(length = unit(0.20, "cm"))
  ) +

  geom_point(aes(color = group), size = 4) +

  # Thermal cluster: let ggrepel resolve label overlaps among themselves
  # and with the points.
  geom_text_repel(
    data = thermal_labels,
    aes(label = label, color = group),
    size = 4.2,
    box.padding = 0.6,
    point.padding = 0.5,
    max.overlaps = Inf,
    seed = 4871,
    show.legend = FALSE
  ) +

  # Creek labels: only two, well-separated from the cluster, placed by
  # hand rather than repelled so they read cleanly next to the mixing
  # arrow.
  geom_text(
    data = creek_labels,
    aes(label = label, color = group),
    size = 4.2,
    hjust = 0,
    nudge_x = 0.12,
    nudge_y = c(-0.9, 1.0),
    show.legend = FALSE
  ) +

  # Leader arrow from the "Thermal Water Field" label into the envelope's
  # interior, directly above the Reactivated Fissure point. Short,
  # nearly vertical, and semi-transparent so it stays subordinate to the
  # data.
  geom_segment(
    data = data.frame(
      x = field_leader_start$d18O, y = field_leader_start$d2H,
      xend = field_leader_target$d18O, yend = field_leader_target$d2H
    ),
    aes(x = x, y = y, xend = xend, yend = yend),
    inherit.aes = FALSE,
    color = "indianred3",
    alpha = 0.55,
    linewidth = 0.7,
    arrow = arrow(length = unit(0.16, "cm"))
  ) +

  annotate(
    "text",
    x = field_label_pos$x,
    y = field_label_pos$y,
    label = "Thermal Water Field",
    size = 5
  ) +

  annotate(
    "text",
    x = shift_label_pos$x,
    y = shift_label_pos$y,
    label = "Downstream Isotopic Shift",
    color = "#1f78b4",
    angle = shift_label_angle,
    size = 4.3
  ) +

  annotate(
    "text",
    x = inferred_label_pos$x,
    y = inferred_label_pos$y,
    label = "Inferred Trend Toward\nThermal Endmember",
    color = "#1f78b4",
    hjust = 0,
    size = 3.6
  ) +

  annotate(
    "text",
    x = xlim[1] + x_pad * 0.15,
    y = gmwl$slope * (xlim[1] + x_pad * 0.15) + gmwl$intercept - 0.8,
    label = "GMWL",
    color = "grey40",
    angle = 35,
    size = 4,
    hjust = 0
  ) +

  scale_color_manual(values = group_colors) +

  coord_cartesian(xlim = xlim, ylim = ylim) +

  labs(
    title = "Steamboat Creek Acquires a Hydrothermal Isotopic Signature",
    subtitle = "Lower Sinter Terrace Hydrothermal System",
    caption = paste0(
      "n = ", nrow(iso_wide), " sites, single sample pair each (2026 dataset)."
    ),
    x = expression(delta^18*O~"(\u2030 VSMOW)"),
    y = expression(delta^2*H~"(\u2030 VSMOW)"),
    color = NULL
  ) +

  theme_bw(base_size = 15) +

  theme(
    plot.title = element_text(face = "bold"),
    plot.caption = element_text(size = 8, color = "grey40"),
    legend.position = "top",
    panel.grid.minor = element_blank()
  )

iso_plot

# -------------------------
# 7. Export
# -------------------------

ggsave(
  "Figures/isotope_mixing_plot.png",
  iso_plot,
  width = plot_width_in,
  height = plot_height_in,
  dpi = 600
)
