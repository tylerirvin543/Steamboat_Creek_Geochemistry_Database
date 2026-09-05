# ==========================================
# LOWER SINTER TERRACE THERMAL ANALYSIS
# Tyler Irvin
# GRC Poster Figures
# ==========================================

library(dplyr)
library(ggplot2)

# Rename loggers

fissure_temp <- fissure_temp %>%
  mutate(
    logger_name = case_when(
      logger_id == 8 ~ "Thermal Upflow",
      logger_id == 5 ~ "Thermal Outflow"
    )
  )

# Convert timestamp

fissure_temp$time <- as.POSIXct(
  as.numeric(fissure_temp$timestamp),
  origin = "1970-01-01",
  tz = "UTC"
)

range_upflow <- range(
  fissure_temp$time[
    fissure_temp$logger_name == "Thermal Upflow"
  ]
)

range_outflow <- range(
  fissure_temp$time[
    fissure_temp$logger_name == "Thermal Outflow"
  ]
)

range_upflow
range_outflow

overlap_start <- max(
  range_upflow[1],
  range_outflow[1]
)

overlap_end <- min(
  range_upflow[2],
  range_outflow[2]
)

overlap_start
overlap_end

library(tidyr)

overlap_temp <- fissure_temp %>%
  filter(
    time >= overlap_start,
    time <= overlap_end
  )

fissure_wide <- overlap_temp %>%
  select(
    time,
    logger_name,
    temperature
  ) %>%
  pivot_wider(
    names_from = logger_name,
    values_from = temperature
  )

library(lubridate)

hourly_temp <- overlap_temp %>%
  mutate(hour = floor_date(time, "hour")) %>%
  group_by(hour, logger_name) %>%
  summarize(
    temperature = mean(temperature, na.rm = TRUE),
    .groups = "drop"
  )

hourly_wide <- hourly_temp %>%
  pivot_wider(
    names_from = logger_name,
    values_from = temperature
  )

correlation_result <- cor(
  hourly_wide$`Thermal Upflow`,
  hourly_wide$`Thermal Outflow`,
  use = "complete.obs"
)

correlation_result

eq_windows <- data.frame(
  
  start = as.POSIXct(c(
    "2026-04-14",
    "2026-04-19",
    "2026-05-01"
  )),
  
  end = as.POSIXct(c(
    "2026-04-16",
    "2026-04-21",
    "2026-05-03"
  )),
  
  label = c(
    "April Swarm",
    "M4.7 Swarm",
    "M5.2 Swarm"
  )
  
)


temp_plot <-
  
  ggplot() +
  
  geom_rect(
    data = eq_windows,
    aes(
      xmin = start,
      xmax = end,
      ymin = -Inf,
      ymax = Inf
    ),
    inherit.aes = FALSE,
    alpha = 0.12,
    fill = "goldenrod"
  ) +
  
  geom_line(
    data = subset(
      fissure_temp,
      logger_name == "Thermal Upflow"
    ),
    aes(
      x = time,
      y = temperature
    ),
    color = "#2ca02c",
    linewidth = 0.45
  ) +
  
  geom_line(
    data = subset(
      fissure_temp,
      logger_name == "Thermal Outflow"
    ),
    aes(
      x = time,
      y = temperature
    ),
    color = "grey25",
    linewidth = 0.30
  ) +
  
  geom_hline(
    yintercept = 93,
    linetype = "dashed",
    color = "#2ca02c",
    linewidth = 0.8
  ) +
  
  annotate(
    "text",
    x = min(fissure_temp$time),
    y = 94.5,
    label = "Boiling Point (~93°C)",
    color = "#2ca02c",
    hjust = 0,
    size = 5
  ) +
  
  annotate(
    "label",
    x = as.POSIXct("2026-04-15"),
    y = 101,
    label = "April Swarm",
    fill = "white",
    size = 4
  ) +
  
  annotate(
    "label",
    x = as.POSIXct("2026-04-19 12:00"),
    y = 101,
    label = "M4.7 Swarm",
    fill = "white",
    size = 4
  ) +
  
  annotate(
    "label",
    x = as.POSIXct("2026-05-01 12:00"),
    y = 101,
    label = "M5.2 Swarm",
    fill = "white",
    size = 4
  ) +
  
  annotate(
    "label",
    x = max(fissure_temp$time),
    y = 98,
    label = "Thermal Upflow",
    fill = "white",
    color = "#2ca02c",
    hjust = 1
  ) +
  
  annotate(
    "label",
    x = max(fissure_temp$time),
    y = 57,
    label = "Thermal Outflow",
    fill = "white",
    color = "grey25",
    hjust = 1
  ) +
  
  annotate(
    "label",
    x = as.POSIXct("2026-05-18"),
    y = 35,
    label = paste0(
      "Pearson r = ",
      round(correlation_result,2)
    ),
    fill = "white",
    size = 5
  ) +
  
  coord_cartesian(
    ylim = c(20,100)
  ) +
  
  labs(
    title =
      "Inverse Thermal Behavior in a Lower Sinter Terrace Fissure System",
    subtitle =
      "Lower Sinter Terrace Hydrothermal Fissure System\nSteamboat Springs, Nevada",
    x = NULL,
    y = "Temperature (°C)"
  ) +
  
  theme_bw(base_size = 16) +
  
  theme(
    legend.position = "none",
    plot.title =
      element_text(face = "bold"),
    panel.grid.minor =
      element_blank()
  )

temp_plot


ggsave(
  "thermal_upflow_outflow_grc.png",
  temp_plot,
  width = 12,
  height = 6,
  dpi = 600
)


# NOTE: the isotope mixing plot previously built here has moved to its own
# standalone script: scripts/analysis/isotope_mixing_plot.R

# Flux summary

flux_summary <- poster_tbl %>%
  transmute(
    Site = name,
    Cl_mgL = round(cl_mg_L,1),
    B_mgL = round(b_mg_L,3),
    Cl_B = round(Cl_B_ratio,1),
    Q_m3s = round(discharge_m3_s,3),
    Cl_Flux_kg_day =
      round(cl_flux_kg_day),
    B_Flux_kg_day =
      round(b_flux_kg_day,1)
  )

flux_summary
