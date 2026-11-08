# Resort / spa well discharge: share of the creek thermal-water budget

Working notes (2026-11-08). Purpose: bracket how much of the thermal-water inflow measured
between SBRR and SBBV could be pumped resort water rather than natural spring or seep
discharge. The pumping rate is not known, so this is a sensitivity table, not an estimate.

## Inputs

| Quantity | Value | Source |
|---|---|---|
| Date of paired creek chloride and discharge | 2026-05-01 | `data/derived/chloride_mass_balance/chloride_mass_balance.csv` |
| Cl flux at SBRR (upstream) | 5.423 g/s | same file |
| Cl flux at SBBV (downstream) | 53.519 g/s | same file |
| Cl flux difference | 48.096 g/s | 53.519 - 5.423 |
| Thermal end-member Cl | 820 mg/L | Sorey and Colvard (1992) convention, same as the poster |
| Thermal inflow, Q_TW | 58.65 L/s | 48.096 / 0.820 |
| Resort tank Cl (SBW_0002, sample 815, same day) | 849 mg/L | `Lab_Analyses` |

## Arithmetic

For a resort discharge Q (L/s) that reaches the creek between SBRR and SBBV:

- Resort Cl flux (g/s) = Q x 0.849
- Thermal-equivalent flow (L/s) = Cl flux / 0.820 = Q x 1.0354
- Share of the budget = Cl flux / 48.096 (the same number as thermal-equivalent / 58.65)
- Remainder from other sources = 58.65 - thermal-equivalent

Conversion: 1 gpm = 0.0631 L/s.

## Sensitivity table

| Resort discharge reaching the creek | Cl flux (g/s) | Thermal-equivalent (L/s) | Share of 58.65 L/s | Remainder (L/s) |
|---|---|---|---|---|
| 0.5 L/s | 0.42 | 0.52 | 0.9% | 58.1 |
| 1.0 L/s | 0.85 | 1.04 | 1.8% | 57.6 |
| 1.9 L/s (30 gpm, 1985 driller test yield, log 26097) | 1.61 | 1.96 | 3.3% | 56.7 |
| **3.8 L/s (60 gpm, historical average)** | 3.21 | 3.92 | 6.7% | 54.7 |
| 5 L/s | 4.25 | 5.18 | 8.8% | 53.5 |
| **9.8 L/s (155 gpm, historical peak)** | 8.30 | 10.13 | 17.3% | 48.5 |
| 10 L/s | 8.49 | 10.35 | 17.7% | 48.3 |
| 20 L/s | 16.98 | 20.71 | 35.3% | 38.0 |

Worked example, 60 gpm: 60 x 0.0631 = 3.785 L/s; 3.785 x 0.849 = 3.21 g/s of chloride;
3.21 / 48.096 = 6.7%; 3.21 / 0.820 = 3.92 L/s; 58.65 - 3.92 = 54.7 L/s.

## Where the historical rows come from

| Row | Period | Source |
|---|---|---|
| 60 gpm average, 155 gpm peak | 1945-52, individual or combined spa wells | White (1968), as cited by Collar (1990) |
| About 60 gpm peak measured | 1989 | Collar (1990), operator's measurement; Sorey and Colvard (1992) give the same maximum |
| 30 gpm | 1985 | Driller's test on NDWR log 26097 (Collar App. B). A test yield, not an operating rate |

## Caveats

- The historical rows are decades old. Collar describes the 1989 well as induced to flow on weekday
  mornings until evening and not on weekends, so a time-averaged rate would be well below the 60 gpm
  peak. The current well is air-lift pumped and intermittent (field confirmation, 2026-10-25).
- The table assumes all resort discharge reaches the creek above SBBV and that the tank chemistry
  (Cl 849 mg/L) matches what is discharged. Neither is confirmed. The resort's own site says water goes
  from the ground into the tubs without extended time in tanks, which should be checked against the
  tank-and-overflow picture in the thermal imagery.
- The Cl-based budget counts any resort water as part of the 58.65 L/s. Subtracting it only changes the
  natural-source remainder; it does not change the total thermal inflow at SBBV.
- The 2026-05-01 value is one date. The poster's averaged ~27 L/s is not reproduced here.

## A009 (SBW_0002 tank) logger: does 2026 operation look like Collar's weekday cycle?

Record: 5-minute readings, 29 Apr to 27 Sep 2026 with a gap from late May to mid July; 95 complete days used.
The logger is in the tank, so it shows tank temperature, not flow. Tank temperature stays at 73-77 C. A single
62.8 C excursion in early August was dropped.

| Quantity | Weekday | Weekend | Wilcoxon p |
|---|---|---|---|
| Days | 68 | 27 | |
| Mean tank temperature (C) | 75.5 | 75.2 | 0.18 |
| Daily range (C) | 2.4 | 3.1 | 0.11 |
| Time of daily minimum (median, PDT) | 09:10 | 08:15 | |
| Morning minimum (C) | 74.1 | 73.5 | 0.15 |
| Share of day at or above 75.5 C | 64% | 58% | 0.30 |
| Overnight cooling, 00:00-08:00 (C/h) | -0.13 | -0.17 | 0.44 |
| Daytime warming, 09:00-18:00 (C/h) | +0.13 | +0.16 | |

What the record shows:
- A smooth daily cycle, not discrete on/off pulses. The tank cools from midnight to about 09:00, turns at a
  sharp minimum, warms through the day, and plateaus near 75.9 C from about 18:00 to midnight.
- Five-minute variability is about 0.2-0.3 C at every hour of day and on both day types, so there is no
  pump-pulse signature at that scale.
- Weekends show the same daily shape as weekdays. Weekend minima are about 0.6 C cooler and the daily range is
  larger, but none of the differences is statistically significant. Collar's 1989 pattern (flow induced on
  weekday mornings, none on weekends) would show no daytime warming on weekends. It does here.
- Inferred state: the tank is in a warming or plateau state for about 13-14 of the 23 hourly steps, roughly
  58% of the day (about 14 h), on both weekdays and weekends. That is the best proxy for pump-on time, and it
  is an inference from heat balance, not a measurement. Air temperature cannot reheat a 75 C tank, so the
  daytime warming has to be hot inflow.

Conclusion: operation in 2026 looks daily, not weekday-only. The logger cannot give a flow rate.

Illustrative scaling only (duty cycle of 58% times a historical rate while running; not an estimate of the
2026 rate):

| Rate while running | Time-averaged | Thermal-equivalent (L/s) | Share of 58.65 L/s |
|---|---|---|---|
| 30 gpm | 17 gpm (1.1 L/s) | 1.14 | 1.9% |
| 60 gpm | 35 gpm (2.2 L/s) | 2.27 | 3.9% |
| 155 gpm | 90 gpm (5.7 L/s) | 5.87 | 10.0% |

Files: `output/figures/resort_tank/a009_hourly_profile_weekday_weekend.png`,
`data/derived/resort_tank/a009_daily_summary.csv`, `data/derived/resort_tank/a009_hourly_profile.csv`.

## Warm area (at or above 20 C) around the tanks, counted separately from the pads

Mapped from the thermal TIFF (7-44 C ramp, same assumptions as the 30 C count) in a window around the
tanks. Total at or above 20 C in the window: 597 m2 (288 m2 at or above 30 C, 309 m2 at 20-30 C).

| Patch (connected, at or above 20 C) | Area | At or above 30 C | Distance from SBW_0002 | Reading |
|---|---|---|---|---|
| 37: tank pads, pipe and immediate apron | 88.7 m2 | 76.7 m2 | 6 m | Tank complex (blob 176) |
| 83 and 40: warm ground by the three cylinders | 36.4 m2 | 2.6 m2 | 12-34 m | Warm yard or possible overflow; unresolved |
| 117: thin straight bright line | 21.2 m2 | 18.3 m2 | 54 m | Pipe or drain trace (blob 188) |
| 141: rectangular warm yard to the south | 58.7 m2 | 0 | 75 m | Probably pavement or a yard; 20-26 C |
| **Tank-adjacent total** | **205 m2** | **98 m2** | | |

- The part at 20-30 C is about 107 m2; without the warm yard (141) it is about 48 m2.
- Beyond the pads, the 20 C threshold adds only about 12 m2 to the tank patch itself.
- No continuous at-or-above 20 C path runs from the tanks to the creek. The long diagonal band
  (probably a road, ditch or paved edge) reads 15-20 C, and the creek reads 13-15 C. Any discharge band
  that reaches the creek is cooler than 20 C and cannot be separated from pavement and water at that
  threshold. The outflow path is therefore not mapped; walking the overflow (see the field task in
  `docs/action_items_for_user.md`) is what will settle it.
- Natural features in the window (for contrast): patch 31 (213 m2, the northwest-southeast channel,
  134 m2 at or above 30 C) and patches 89, 5 and 131.

Figure: `output/figures/thermal_work/tif_ge20_window.png`.
