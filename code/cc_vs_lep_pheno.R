### Comparing adult lep phenocurves to Caterpillars Count! phenology

#### Libraries ####

library(tidyverse)
library(lubridate)
library(purrr)
library(sf)
library(tmap)

#### Functions ####

# fn: lag lep data by x weeks, find R2 between y weekly caterpillar phenometric and 3 adult lep trait groups
lag_r2 <- function(weeks, cat_data, lep_data) {
  l <- weeks*7
  
  lep_data$lag_x <- lep_data$x - l
  
  lep_codes <- unique(lep_data$code)
  
  cc_lep_pheno <- cat_data %>%
    left_join(lep_data, by = c("julianweek" = "lag_x")) %>%
    filter(!is.na(code)) %>%
    pivot_wider(names_from = "code", values_from = "y")
  
  # Some hex cell/years missing some adult lep groups, only calculate R2 if those groups are present
  
  if("RE" %in% lep_codes) {
    re_r2 <- summary(lm(val ~ RE, data = cc_lep_pheno))$r.squared
  } else {re_r2 <- NA}
  
  if("RL" %in% lep_codes) {
    rl_r2 <- summary(lm(val ~ RL, data = cc_lep_pheno))$r.squared
  } else {rl_r2 <- NA}
  
  if("RP" %in% lep_codes) {
    rp_r2 <- summary(lm(val ~ RP, data = cc_lep_pheno))$r.squared
  } else {rp_r2 <- NA}
  
  return(data.frame(code = c("RE", "RL", "RP"), r2 = c(re_r2, rl_r2, rp_r2)))
}

# fn to compute lags for any hex, year, cat_data combination
output_lags <- function(cell, Year, data, ...) {
  cats <- data
  
  leps <- lep_pheno %>%
    filter(year == Year, HEXcell == cell)
  
  res <- data.frame(lag = c(), code = c(), r2 = c())
  for(w in -8:8){
    
    r2_df <- lag_r2(w, cats, leps)
    
    r2_df$lag <- w
    
    res <- rbind(res, r2_df)
    
  }
  
  res
  
}

# fn to compute lags with backcasted lep data for any hex, year, cat_data combination
output_lags_backcast <- function(cell, Year, data, ...) {
  cats <- data
  
  leps <- backcast_pheno %>%
    filter(year == Year, hex == cell) %>%
    rename(x = "doyl", y = "pdf") # match with lep_pheno colnames
  
  res <- data.frame(lag = c(), code = c(), r2 = c())
  for(w in -8:8){
    
    r2_df <- lag_r2(w, cats, leps)
    
    r2_df$lag <- w
    
    res <- rbind(res, r2_df)
    
  }
  
  res
  
}

#### Set up ####

## ggplot theme

theme_set(theme_classic(base_size = 15))

## Read in adult lep curves

lep_pheno <- read_csv("data/derived_data/simpleton_pheno_pdfs-OutlierDetection.csv")

## Read in CatCount data (weekly phenology at hex cells, sites with at least 6 good weeks)

cc_site_data <- read_csv("data/derived_data/cc_subset_trait_based_pheno.csv")

## Read in backcasted caterpillar curves

backcast_cats <- read_csv("data/derived_data/allCodes_CatCast.csv")

## CatCount data availability

cc_sample_size <- cc_site_data %>%
  group_by(cell, Year) %>%
  summarize(n_sites = n_distinct(Name))

ggplot(cc_sample_size, aes(x = Year, y = as.factor(cell), size = n_sites)) + 
  geom_point() +
  scale_x_continuous(breaks = c(seq(2010, 2020, by = 2))) +
  labs(x = "Year", y = "Hex cell", size = "CC sites")
# ggsave("figures/cc_hex_data_avail.pdf")

# Map of hex cells represented

hex_sf <- read_sf("data/maps/hex_grid_crop.shp") %>%
  mutate(cell_num = as.numeric(cell)) %>%
  st_transform("+proj=ortho +lon_0=-75 +lat_0=40")

na_map <- read_sf("data/maps/ne_50m_admin_1_states_provinces_lakes.shp") %>%
  filter(sr_adm0_a3 %in% c("USA", "CAN")) %>%
  st_crop(c(xmin = -100, ymin = 20, xmax = -59, ymax = 51)) %>%
  st_transform("+proj=ortho +lon_0=-75 +lat_0=40")

sites_sf <- hex_sf %>%
  right_join(cc_sample_size, by = c("cell_num" = "cell")) %>%
  group_by(cell) %>%
  summarize(n_sites = max(n_sites),
            first_year = min(Year))

cc_site_map <- tm_shape(na_map) + tm_polygons() +
  tm_shape(sites_sf) + tm_polygons(col = "n_sites", palette = "YlGnBu", title = "CC! sites", alpha = 0.65) +
  tm_shape(sites_sf) + tm_text(text = "first_year") +
  tm_layout(legend.text.size = 1, legend.title.size = 1.5)
# tmap_save(cc_site_map, "figures/cc_site_map.pdf")

#### Correlations of lep adult curves and CC pheno curves ####

## CC hex phenology

cc_pheno <- cc_site_data %>%
  group_by(cell, Year, julianweek) %>%
  summarize(mean_dens= mean(meanDensity),
            mean_fracsurv = mean(fracSurveys),
            mean_biomass = mean(meanBiomass))

## Indiv phenology for Coweeta, Prairie Ridge, Bot Garden sites

cc_site_pheno <- cc_site_data %>%
  filter(Name %in% c("Coweeta - BB", "Coweeta - BS", "NC Botanical Garden", "Prairie Ridge Ecostation"))

## Check lags from -8 to 8 weeks, calculate R2 by hex-year

## Lags between adult lep pheno curves and caterpillar biomass, density, and fraction of surveys

cc_lep_lags <- cc_pheno %>%
  pivot_longer(names_to = "cat_metric", values_to = "val", mean_dens:mean_biomass) %>%
  group_by(cat_metric, cell, Year) %>%
  nest() %>%
  mutate(r2 = pmap(list(cell, Year, data), output_lags)) %>%
  select(-data) %>%
  unnest(cols = c("r2"))

## Plot R2 results

pdf(paste0(getwd(), "/figures/cc_adult_correlation.pdf"), height = 8, width = 10)

for(c in unique(cc_lep_lags$cell)) {
  
  plot_df <- cc_lep_lags %>%
    filter(cell == c)
  
  plot <- ggplot(plot_df, aes(x = lag, y = r2, col = as.factor(Year), group = Year)) + geom_line() + facet_grid(code ~ cat_metric)+
    labs(x = "Lag (weeks)", y = expression(R^2), title = paste0("Hex cell ", c), col = "Year") + theme_bw(base_size = 15)
  
  print(plot)
}

dev.off()

## Single site caterpillar to adult lep hex comparisons

cc_site_lags <- cc_site_pheno %>%
  pivot_longer(names_to = "cat_metric", values_to = "val", meanDensity:meanBiomass) %>%
  select(Name, cell, Year, julianweek, cat_metric, val) %>%
  group_by(cat_metric, Name, cell, Year) %>%
  nest() %>%
  mutate(r2 = pmap(list(cell, Year, data), output_lags)) %>%
  select(-data) %>%
  unnest(cols = c("r2"))

## Plot R2 results

pdf(paste0(getwd(), "/figures/cc_adult_correlation_NCsites.pdf"), height = 8, width = 10)

for(n in unique(cc_site_lags$Name)) {
  
  plot_df <- cc_site_lags %>%
    filter(Name == n)
  
  plot <- ggplot(plot_df, aes(x = lag, y = r2, col = as.factor(Year), group = Year)) + geom_line() + facet_grid(code ~ cat_metric)+
    labs(x = "Lag (weeks)", y = expression(R^2), title = paste0("Site: ", n), col = "Year") + theme_bw(base_size = 15)
  
  print(plot)
}

dev.off()

#### Correlations of backcasted cat curves and CC pheno curves ####

## Backcast pheno PDFs for hex-years with CC data

hexes <- unique(cc_pheno$cell)
years <- unique(cc_pheno$Year)

backcast_pheno <- backcast_cats %>%
  filter(hex %in% hexes, year %in% years, code == "RL")

## Test lags with CC hexes

cc_cat_lags <- cc_pheno %>%
  pivot_longer(names_to = "cat_metric", values_to = "val", mean_dens:mean_biomass) %>%
  group_by(cat_metric, cell, Year) %>%
  nest() %>%
  mutate(r2 = pmap(list(cell, Year, data), output_lags_backcast)) %>%
  select(-data) %>%
  unnest(cols = c("r2")) %>%
  filter(code == "RL")

## Plot R2 results

pdf(paste0(getwd(), "/figures/cc_catcast_correlation.pdf"), height = 4, width = 10)

for(c in unique(cc_cat_lags$cell)) {
  
  plot_df <- cc_cat_lags %>%
    filter(cell == c)
  
  plot <- ggplot(plot_df, aes(x = lag, y = r2, col = as.factor(Year), group = Year)) + geom_line() + facet_wrap(~cat_metric) +
    labs(x = "Lag (weeks)", y = expression(R^2), title = paste0("Hex cell ", c), col = "Year") + theme_bw(base_size = 15)
  
  print(plot)
}

dev.off()

## Example plot for one site - process of getting R2 results

ex_curves <- cc_pheno %>%
  filter(cell == 703, Year == 2019) %>%
  left_join(backcast_pheno, by = c("Year" = "year", "julianweek" = "doyl", "cell" = "hex"))

coeff <- 1000

ggplot(ex_curves, aes(x = julianweek)) + geom_line(aes(y = mean_fracsurv, col = "CatCount!"), cex = 1) + 
  geom_line(aes(y = pdf*coeff, col = "Backcast"), cex = 1) +
  scale_y_continuous(
    
    # Features of the first axis
    name = "% Surveys with Cats (CatCount!)",
    
    # Add a second axis and specify its features
    sec.axis = sec_axis(~./coeff, name="PDF (Backcast)")
  ) +
  labs(x = "Day of year", col = "") +
  theme(legend.position = c(0.2, 0.2))
ggsave("figures/ex_curves_plot.pdf", height = 4, width = 6, units = "in")

## Mean fraction of surveys R2 results

fracsurv_lags <- cc_cat_lags %>%
  filter(cat_metric == "mean_fracsurv") %>%
  filter(!is.na(r2))

ggplot(fracsurv_lags, aes(x = lag, y = r2, col = as.factor(Year), group = Year)) + geom_line() + facet_wrap(~cell) +
  labs(x = "Lag (weeks)", y = expression(R^2), col = "Year") + theme_bw(base_size = 15)
ggsave("figures/cc_catcast_fracsurv_lags.pdf", height = 8, width = 12, units = "in")

## Example R2 plot for one site-year

ggplot(filter(fracsurv_lags, cell == 703, Year == 2019), aes(x = lag, y = r2, group = Year)) + 
  geom_line(cex = 1) + 
  labs(x = "Lag (weeks)", y = expression(R^2)) + theme_bw(base_size = 15)
ggsave("figures/ex_r2_plot.pdf", height = 4, width = 6, units = "in")

## Hist of best lag

catcast_best_lag <- fracsurv_lags %>%
  group_by(cell, Year) %>%
  filter(r2 == max(r2, na.rm = T))

ggplot(catcast_best_lag, aes(x = lag)) + geom_histogram(col = "white") + labs(x = "Lag (weeks)", y = "Cell-Years")
ggsave("figures/cc_catcast_lags_hist.pdf", units = "in", height = 4, width = 6)

## Mean lag with latitude

# Hex cell centers
hex_grid <- dggridR::dgconstruct(res = 6)
cell_centers <- dggridR::dgSEQNUM_to_GEO(hex_grid, unique(catcast_best_lag$cell))

cc_df <- data.frame(cell = unique(catcast_best_lag$cell), 
                    lon = cell_centers$lon_deg, 
                    lat = cell_centers$lat_deg)

catcast_lag_lat <- fracsurv_lags %>%
  group_by(cell, Year) %>%
  filter(r2 == max(r2, na.rm = T)) %>%
  summarize(mean_lag = mean(lag)) %>%
  left_join(cc_df)

ggplot(catcast_lag_lat, aes(x = lat, y = mean_lag)) + geom_point(size = 2) +
  labs(x = "Latitude", y = "Best lag across years")
ggsave("figures/cc_catcast_lag_by_lat.pdf", units = "in", height = 4, width = 6)

## Test lags with CC NC sites

cc_site_cat_lags <- cc_site_pheno %>%
  pivot_longer(names_to = "cat_metric", values_to = "val", meanDensity:meanBiomass) %>%
  select(Name, cell, Year, julianweek, cat_metric, val) %>%
  group_by(cat_metric, Name, cell, Year) %>%
  nest() %>%
  mutate(r2 = pmap(list(cell, Year, data), output_lags_backcast)) %>%
  select(-data) %>%
  unnest(cols = c("r2")) %>%
  filter(code == "RL")

## Plot R2 results

pdf(paste0(getwd(), "/figures/cc_catcast_correlation_NCsites.pdf"), height = 4, width = 10)

for(n in unique(cc_site_cat_lags$Name)) {
  
  plot_df <- cc_site_cat_lags %>%
    filter(Name == n)
  
  plot <- ggplot(plot_df, aes(x = lag, y = r2, col = as.factor(Year), group = Year)) + geom_line() + facet_wrap(~cat_metric)+
    labs(x = "Lag (weeks)", y = expression(R^2), title = paste0("Site: ", n), col = "Year") + theme_bw(base_size = 15)
  
  print(plot)
}

dev.off()

#### Shifts + Stretches ####

## Backcasted cats, lags from -8 to 8, stretches from 0.5-1.5

lags <- c(-8:8)
stretches <- seq(0.5, 1.5, by = 0.1)

## fn: stretch + lag r2 - inputs: hex cell, year, cat_data
stretch_lag_r2 <- function(cell, Year, data, ...) {
  cc_wks <- unique(data$julianweek)
  
  leps <- backcast_pheno %>%
    filter(code == "RL", year == Year, hex == cell)
  
  if(nrow(leps) > 0) {
    res <- data.frame(lag = c(), stretch = c(), r2 = c())
    
    for(l in lags) {
      
      w <- l*7
      
      leps$lag_x <- leps$doyl - w
      
      for(s in stretches) {
        leps$stretch <- round(leps$lag_x*s)
        
        leps_wk <- leps %>%
          filter(!is.na(doyl)) %>%
          mutate(julianweek = map_dbl(stretch, ~{
            wk <- cc_wks[. - cc_wks < 7 & . - cc_wks >= 0]
            
            if(length(wk) > 0) {
              wk
            } else { NA }
            
          }))
        
        pheno <- data %>%
          left_join(leps_wk, by = c("julianweek"))
        
        if(is.na(unique(pheno$pdf))) {
          res <- rbind(res, data.frame(lag = l, stretch = s, r2 = NA))
        } else {
          r2 <- summary(lm(val ~ pdf, data = pheno))$r.squared
          
          res <- rbind(res, data.frame(lag = l, stretch = s, r2 = r2))
        }
      }
    }
    
    return(res)
    
  } else {return(c(NA))}
  
}

cc_catcast_lag_stretch <- cc_pheno %>%
  pivot_longer(names_to = "cat_metric", values_to = "val", mean_dens:mean_biomass) %>%
  group_by(cat_metric, cell, Year) %>%
  filter(cat_metric == "mean_fracsurv") %>%
  nest() %>%
  mutate(r2 = pmap(list(cell, Year, data), stretch_lag_r2)) %>%
  select(-data) %>%
  unnest(cols = c("r2"))

pdf(paste0(getwd(), "/figures/cc_catcast_lag_stretch_heatmaps.pdf"), height = 10, width = 10)
for(c in unique(cc_catcast_lag_stretch$cell)) {
  
  plot_df <- cc_catcast_lag_stretch %>%
    filter(cell == c)
  
  p <- ggplot(plot_df, aes(x = lag, y = stretch, fill = r2)) + 
    geom_tile() + facet_wrap(~Year) + scale_fill_viridis_c() + 
    labs(x = "Lag (weeks)", y = "Stretch", fill = expression(R^2), title = paste0("Cell: ", c))
  
  print(p)
}
dev.off()

# Heatmap of best combo of lag/stretch across cell-years

best_lag_stretch <- cc_catcast_lag_stretch %>%
  filter(!is.na(r2)) %>%
  group_by(cell, Year) %>%
  filter(r2 == max(r2, na.rm = T)) %>%
  group_by(lag, stretch) %>%
  summarize(n_cell_year = n())

ggplot(best_lag_stretch, aes(x = lag, y = stretch, fill = n_cell_year)) + 
  geom_tile() + scale_fill_viridis_c() +
  labs(x = "Lag (weeks)", y = "Stretch", fill = "Cell-Years")
ggsave("figures/best_stretch_lag.pdf", units = "in", height = 6, width= 8)

##### Phenometrics ####

## Compare early/late years in catcast and CC sites using deviations from mean and z-scores
## Calculate curve centroids for cat backcast and CC sites
## 10% accumulation for adults

lep_join <- lep_pheno %>%
  filter(code == "RL", year %in% years, HEXcell %in% hexes) %>%
  filter(!grepl("\\.", x))

pheno_centroids <- backcast_pheno %>%
  filter(code == "RL") %>%
  group_by(hex, year) %>%
  mutate(catcast_centr = sum(doyl*pdf, na.rm = T)/sum(pdf, na.rm = T),
         catcast_10 = min(doyl[pdf >= 0.1*max(pdf, na.rm = T)], na.rm = T),
         catcast_50 = min(doyl[pdf >= 0.5*max(pdf, na.rm = T)], na.rm = T)) %>%
  right_join(lep_join, by = c("year", "code", "doyl" = "x", "hex" = "HEXcell")) %>%
  mutate(adult_peak = mean(doyl[y == max(y, na.rm = T)]),
         adult_10 = min(doyl[y >= 0.1*max(y, na.rm = T)], na.rm = T))

## Plot phenocurves for catcast

pdf(paste0(getwd(), "/figures/catcast_phenocurves.pdf"), height = 8, width = 12)

for(c in unique(pheno_centroids$hex)) {
  
  plot_df <- pheno_centroids %>%
    filter(hex == c)
  
  plot <- ggplot(plot_df, aes(x = doyl)) + 
    geom_smooth(aes(y = pdf, col = "Larvae"), se = F) +
    geom_line(aes(y = y, col = "Adults")) + 
    geom_vline(aes(xintercept = catcast_10, col = "Larvae"), lty = 1) +
    geom_vline(aes(xintercept = catcast_50, col = "50"), lty = 2) +
    facet_wrap(~year) +
    labs(x = "Day of year", y = "PDF", col = "Life stage",
         title = paste0("Hex cell ", c)) + theme_bw(base_size = 15)
  
  print(plot)
}

dev.off()

## Correlation between early/late years 
## Calculate deviations and z-scores

cc_allsite_pheno <- cc_site_data %>%
  group_by(cell, Year, Name) %>%
  summarize(catcount_centr = sum(julianweek*fracSurveys)/sum(fracSurveys)) %>%
  group_by(cell, Name) %>%
  mutate(mean_catcount_centr = mean(catcount_centr, na.rm = T),
            sd_catcount_centr = sd(catcount_centr, na.rm = T),
            catcount_dev = catcount_centr - mean_catcount_centr,
            catcount_z = catcount_dev/sd_catcount_centr) %>%
  group_by(cell, Year) %>%
  summarize(mean_catcount_centr = mean(mean_catcount_centr, na.rm = T),
            catcount_dev = mean(catcount_dev, na.rm = T),
            catcount_z = mean(catcount_z, na.rm = T))

pheno_dev <- pheno_centroids %>%
  distinct(year, hex, catcast_centr, catcast_10, catcast_50) %>%
  group_by(hex) %>%
  mutate(mean_catcast_centr = mean(catcast_centr, na.rm = T),
         mean_catcast_10 = mean(catcast_10, na.rm = T),
         mean_catcast_50 = mean(catcast_50, na.rm = T),
         sd_catcast_10 = sd(catcast_10, na.rm = T),
         sd_catcast_50 = sd(catcast_50, na.rm = T),
         sd_catcast_centr = sd(catcast_centr, na.rm = T),
         catcast_dev = catcast_centr - mean_catcast_centr,
         catcast10_dev = catcast_10 - mean_catcast_10,
         catcast50_dev = catcast_50 - mean_catcast_50,
         catcast_z = catcast_dev/sd_catcast_centr,
         catcast10_z = catcast10_dev/sd_catcast_10,
         catcast50_z = catcast50_dev/sd_catcast_50) %>%
  filter(!is.na(catcast_centr)) %>%
  left_join(cc_allsite_pheno, by = c("hex" = "cell", "year" = "Year")) %>%
  filter(!is.na(mean_catcount_centr), catcount_dev != 0)

r_dev <- cor(pheno_dev$catcast_dev, pheno_dev$catcount_dev, use = "pairwise.complete.obs")

r_z <- cor(pheno_dev$catcast_z, pheno_dev$catcount_z, use = "pairwise.complete.obs")

r_10 <- cor(pheno_dev$catcast10_z, pheno_dev$catcount_z, use = "pairwise.complete.obs")

r_50_dev <- cor(pheno_dev$catcast50_dev, pheno_dev$catcount_dev, use = "pairwise.complete.obs")

r_50_z <- cor(pheno_dev$catcast50_z, pheno_dev$catcount_z, use = "pairwise.complete.obs")


# plot correlation of deviations
ggplot(pheno_dev, aes(x = catcount_dev, y = catcast_dev)) + geom_point() +
  geom_abline(intercept = 0, slope = 1, lty = 2) +
  annotate(geom = "text", x = 5, y = 30, label = paste0("r  = ", round(r_dev, 2)), size = 6) +
  labs(x = "Caterpillars Count! centroid deviation", y = "CatCast centroid deviation")
ggsave("figures/catcast_catcount_deviation_1to1.pdf")

# plot correlation of z scores
ggplot(pheno_dev, aes(x = catcount_z, y = catcast_z)) + geom_point() +
  geom_abline(intercept = 0, slope = 1, lty = 2) +
  annotate(geom = "text", x = 1.5, y = -2, label = paste0("r  = ", round(r_z, 2)), size = 6) +
  labs(x = "z-Caterpillars Count! centroid", y = "z-CatCast centroid")
ggsave("figures/catcast_catcount_zscores_1to1.pdf")

# plot correlation of z scores with catcast 10
ggplot(pheno_dev, aes(x = catcount_z, y = catcast50_z, col = as.factor(year), shape = as.factor(hex))) + 
  geom_point(size = 3) +
  geom_abline(intercept = 0, slope = 1, lty = 2) +
  annotate(geom = "text", x = 0.5, y = -2, label = paste0("r  = ", round(r_50_z, 2)), size = 6) +
  labs(x = "z-Caterpillars Count! centroid", y = "z-CatCast 10%", shape = "Hex", color = "Year")
ggsave("figures/catcast_catcount_zscores_50pct_1to1.pdf", units = "in", height = 6, width = 8)

# plot correlation of 50% deviance with catcount deviance
ggplot(pheno_dev, aes(x = catcount_dev, y = catcast50_dev, col = as.factor(year), shape = as.factor(hex))) + 
  geom_point(size = 3) +
  geom_abline(intercept = 0, slope = 1, lty = 2) +
  annotate(geom = "text", x = 6, y = -60, label = paste0("r  = ", round(r_50_dev, 2)), size = 6) +
  labs(x = "Caterpillars Count! centroid deviance", y = "CatCast 50% deviance", shape = "Hex", color = "Year")
ggsave("figures/catcast_catcount_dev_50pct_1to1.pdf", units = "in", height = 6, width = 8)

## Early/late years in catcast and CC sites with temperature 

hex_temps <- read.csv("data/derived_data/hex_mean_temps.csv", stringsAsFactors = F)

pheno_temps <- pheno_centroids %>%
  ungroup() %>%
  distinct(year, hex, code, catcast_centr, catcast_10, adult_peak, adult_10) %>%
  left_join(cc_allsite_pheno, by = c("hex" = "cell", "year" = "Year")) %>%
  filter(!is.na(mean_catcount_centr), !is.na(catcast_centr)) %>%
  select(-catcount_dev, -catcount_z) %>%
  left_join(hex_temps, by = c("hex" = "cell", "year")) %>%
  pivot_longer(names_to = "data", values_to = "pheno", catcast_centr:mean_catcount_centr) %>%
  mutate(plot_labels = case_when(data == "catcast_centr" ~ "CatCast",
                                 data == "mean_catcount_centr" ~ "CatCount",
                                 data == "catcast_10" ~ "CatCast 10%",
                                 data == "adult_peak" ~ "Adult max",
                                 data == "adult_10" ~ "Adult 10%"))

catcount_mod <- summary(lm(pheno ~ mean_temp, data = filter(pheno_temps, data == "mean_catcount_centr")))

catcast_mod <- summary(lm(pheno ~ mean_temp, data = filter(pheno_temps, data == "catcast_centr")))

catcast10_mod <- summary(lm(pheno ~ mean_temp, data = filter(pheno_temps, data == "catcast_10")))

adult_mod <- summary(lm(pheno ~ mean_temp, data = filter(pheno_temps, data == "adult_peak")))

adult10_mod <-  summary(lm(pheno ~ mean_temp, data = filter(pheno_temps, data == "adult_10")))

# ggplot cols
cols <- scales::hue_pal()(5)

ggplot(pheno_temps, aes(x = mean_temp, y = pheno, col = plot_labels)) + 
  geom_point(size = 2, alpha = 0.5) + 
  geom_smooth(method = "lm", se = F) +
  annotate(geom = "text", x = 8.5, y = 0, 
           label = paste0("p = ", round(catcount_mod$coefficients[2,4], 2), "; R2 = ", round(catcount_mod$r.squared, 2)), 
           col = cols[5]) +
  annotate(geom = "text", x = 8.5, y = 8, 
           label = paste0("p = ", round(catcast10_mod$coefficients[2,4], 2), "; R2 = ", round(catcast10_mod$r.squared, 2)), 
           col = cols[4]) +
  annotate(geom = "text", x = 8.5, y = 16, 
           label = paste0("p = ", round(catcast_mod$coefficients[2,4], 2), "; R2 = ", round(catcast_mod$r.squared, 2)), 
           col = cols[3]) +
  annotate(geom = "text", x = 8.5, y = 24, 
           label = paste0("p = ", round(adult_mod$coefficients[2,4], 2), "; R2 = ", round(adult_mod$r.squared, 2)), 
           col = cols[2]) +
  annotate(geom = "text", x = 8.5, y = 32, 
           label = paste0("Slope p = ", round(adult10_mod$coefficients[2,4], 2), "; R2 = ", round(adult_mod$r.squared, 2)), 
           col = cols[1]) +
  labs(x = "Avg spring temperature (March-June)", y = "Peak/centroid date", col = "")
ggsave("figures/catcast_catcount_temp.pdf", units = "in", height = 6, width = 8)
