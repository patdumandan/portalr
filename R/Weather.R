#' @title Weather by day, calendar month, or lunar month
#'
#' @description Summarize hourly weather data to either daily, monthly, or lunar monthly level.
#'
#' @param level specify 'monthly', 'daily', or 'newmoon'
#' @param fill specify if missing data should be filled, passed to \code{fill_missing_weather}
#' @param horizon Horizon (number of days) to use when calculating cumulative values
#' (eg warm weather precip)
#' @param temperature_limit Temperature limit (in C) to use when calculating cumulative values
#' (eg warm weather precip)
#' @inheritParams summarize_rodent_data
#'
#' @export
#'
weather <- function(level = "daily", fill = FALSE, horizon = 360, temperature_limit = 4,
                      path = get_default_data_path())
{
  level <- tolower(level)
  weather_new <- load_datafile("Weather/Portal_weather.csv", na.strings = c(""), path = path)
  weather_old <- load_datafile("Weather/Portal_weather_19801989.csv", na.strings = c("-99"), path = path)
  moon_dates <- load_datafile("Rodents/moon_dates.csv", na.strings = c(""), path = path)

  ###########Summarise by Day ----------------------
  days <- weather_new %>%
    dplyr::group_by(.data$year, .data$month, .data$day) %>%
    dplyr::summarize(mintemp = min(.data$airtemp),
                     maxtemp = max(.data$airtemp),
                     meantemp = mean(.data$airtemp),
                     precipitation = sum(.data$precipitation),
                     battv = ifelse(all(is.na(.data$battv)), NA, min(.data$battv, na.rm = TRUE))) %>%
    dplyr::ungroup()

  weather <- dplyr::bind_rows(weather_old[1:3442, ], days)  %>%
    dplyr::mutate(locally_measured = TRUE,
#                  battv = ifelse(is.infinite(.data$battv), NA, .data$battv),
                  battery_low = ifelse(.data$battv < 11, TRUE, FALSE)) %>%
    dplyr::select(c("year", "month", "day", "mintemp", "maxtemp", "meantemp",
                    "precipitation", "locally_measured", "battery_low"))

  if (fill)
  {
    weather <- fill_missing_weather(weather, path)
  }

  weather <- weather %>%
    dplyr::mutate(date = as.Date(paste(.data$year, .data$month, .data$day, sep = "-"))) %>%
    tidyr::complete(date = tidyr::full_seq(.data$date, period = 1), fill = list(value = NA)) %>%
    dplyr::mutate(year = lubridate::year(.data$date), month = lubridate::month(.data$date)) %>%
    dplyr::mutate(warm_days = zoo::rollapplyr(.data$mintemp, width = horizon,
                             FUN = function(x) length(which(x >= temperature_limit)), partial = TRUE)) %>%
    dplyr::mutate(cool_precip = zoo::rollapplyr(ifelse(.data$mintemp < temperature_limit,
                                                       .data$precipitation, 0),
                                            width = horizon, FUN = sum, partial = TRUE, na.rm = TRUE)) %>%
    dplyr::mutate(warm_precip = zoo::rollapplyr(ifelse(.data$mintemp >= temperature_limit,
                                                       .data$precipitation, 0),
                                                width = horizon, FUN = sum, partial = TRUE, na.rm = TRUE))

  if (level == "monthly") {

    ##########Summarise by Month -----------------

    weather = weather %>%
      dplyr::group_by(.data$year, .data$month) %>%
      dplyr::summarize(mintemp = min(.data$mintemp, na.rm = TRUE),
                       maxtemp = max(.data$maxtemp, na.rm = TRUE),
                       meantemp = mean(.data$meantemp, na.rm = TRUE),
                       precipitation = sum(.data$precipitation, na.rm = TRUE),
                       warm_days = mean(.data$warm_days, na.rm = TRUE),
                       cool_precip = mean(.data$cool_precip, na.rm = TRUE),
                       warm_precip = mean(.data$warm_precip, na.rm = TRUE),
                       locally_measured = all(.data$locally_measured, na.rm = TRUE),
                       battery_low = all(.data$battery_low, na.rm = TRUE)) %>%
      dplyr::ungroup() %>%
      dplyr::arrange(.data$year, .data$month) %>%
      dplyr::select(c("year", "month", "mintemp", "maxtemp", "meantemp",
                      "precipitation", "locally_measured", "battery_low",
                      "warm_days", "cool_precip", "warm_precip")) %>%
      dplyr::mutate(battery_low = ifelse(.data$year < 2003, NA, .data$battery_low),
      mintemp = ifelse(is.finite(.data$mintemp), .data$mintemp, NA),
      maxtemp = ifelse(is.finite(.data$maxtemp), .data$maxtemp, NA),
      meantemp = ifelse(is.finite(.data$meantemp), .data$meantemp, NA))

    } else if (level == "newmoon") {

    ##########Summarise by lunar month -----------------

    newmoon_number <- moon_dates$newmoonnumber[-1]
    newmoon_start <- as.Date(moon_dates$newmoondate[-nrow(moon_dates)])
    newmoon_end <- as.Date(moon_dates$newmoondate[-1])
    newmoon_match_number <- NULL
    newmoon_match_date <- NULL
    for (i in seq(newmoon_number)) {
      temp_dates <- as.character(seq.Date(newmoon_start[i] + 1, newmoon_end[i], 1))
      temp_numbers <- rep(newmoon_number[i], length(temp_dates))
      newmoon_match_date <- c(newmoon_match_date, temp_dates)
      newmoon_match_number <- c(newmoon_match_number, temp_numbers)
    }
    newmoon_match_date <- as.Date(newmoon_match_date)

    newmoon_sums <- moon_dates %>%
      dplyr::mutate(date = as.Date(.data$newmoondate)) %>%
      dplyr::left_join(weather, by = "date") %>%
      dplyr::select(c("date", "newmoonnumber", "warm_days", "cool_precip", "warm_precip"))

    weather$newmoonnumber <- newmoon_match_number[match(weather$date, newmoon_match_date)]

    weather <- weather %>%
      dplyr::group_by(.data$newmoonnumber) %>%
      dplyr::summarize(date = max(.data$date, na.rm = TRUE),
                       mintemp = min(.data$mintemp, na.rm = TRUE),
                       maxtemp = max(.data$maxtemp, na.rm = TRUE),
                       meantemp = mean(.data$meantemp, na.rm = TRUE),
                       precipitation = sum(.data$precipitation,  na.rm = TRUE),
                       locally_measured = all(.data$locally_measured, na.rm = TRUE),
                       battery_low = all(.data$battery_low, na.rm = TRUE)) %>%
      dplyr::arrange(.data$newmoonnumber) %>%
      dplyr::select(c("newmoonnumber", "date", "mintemp", "maxtemp", "meantemp",
                      "precipitation", "locally_measured", "battery_low")) %>%
      dplyr::mutate(battery_low = ifelse(.data$date < "2003-01-01", NA, .data$battery_low)) %>%
      dplyr::left_join(newmoon_sums, by = c("newmoonnumber", "date")) %>%
      dplyr::mutate(mintemp = ifelse(is.finite(.data$mintemp), .data$mintemp, NA),
                    maxtemp = ifelse(is.finite(.data$maxtemp), .data$maxtemp, NA),
                    meantemp = ifelse(is.finite(.data$meantemp), .data$meantemp, NA))
  }

  return(as.data.frame(weather))
}

#' @title Fill missing weather with regional data
#'
#' @description Use two weather stations in San Simon valley to fill in
#' missing weather data in the daily time series
#'
#' @param weather a dataframe of daily weather data
#' @inheritParams weather
#'
#' @noRd
#'
fill_missing_weather <- function(weather, path = get_default_data_path())
{
  portal4sw <- read.csv(full_path('PortalData/Weather/Portal4sw_regional_weather.csv', path),
                        na.strings = c(""), header = TRUE, stringsAsFactors = FALSE) %>%
    dplyr::select(c("year", "month", "day", "date", "name", "prcp", "snow", "tmax", "tmin", "tobs"))

  sansimon <- read.csv(full_path('PortalData/Weather/Sansimon_regional_weather.csv', path),
                       na.strings = c(""), header = TRUE, stringsAsFactors = FALSE) %>%
    dplyr::select(c("year", "month", "day", "date", "name", "prcp", "snow"))

  region <- dplyr::full_join(portal4sw, sansimon, by =
                               c("date", "year", "month", "day")) %>%
    dplyr::arrange(.data$year,.data$ month, .data$day) %>%
    dplyr::filter(.data$date >= "1980-01-01")

  regionmeans <- region %>%
    dplyr::group_by(.data$date) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(precip = mean(c(.data$prcp.x, .data$prcp.y), na.rm = TRUE, trim = 0)) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(precip = ifelse(is.nan(.data$precip), NA, .data$precip)) %>%
    dplyr::filter(!(is.na(.data$tmin) & is.na(.data$tmax) &
                      is.na(.data$tobs) & is.na(.data$precip))) %>%
    dplyr::select(c("year", "month", "day", "precip", "tmin", "tmax", "tobs"))

  filled_data <- dplyr::full_join(regionmeans, weather, by = c("year", "month", "day")) %>%
    dplyr::arrange(.data$year, .data$month, .data$day) %>%
    dplyr::mutate(locally_measured = !(is.na(.data$mintemp) | is.na(.data$maxtemp) |
                                       is.na(.data$meantemp) | is.na(.data$precipitation)),
                  mintemp = ifelse(is.na(.data$mintemp), .data$tmin, .data$mintemp),
                  maxtemp = ifelse(is.na(.data$maxtemp), .data$tmax, .data$maxtemp),
                  meantemp = ifelse(is.na(.data$meantemp), .data$tobs, .data$meantemp),
                  precipitation = ifelse(is.na(.data$precipitation),
                                         .data$precip, .data$precipitation)) %>%
    dplyr::select(c("year", "month", "day", "mintemp", "maxtemp", "meantemp", "precipitation",
                    "locally_measured", "battery_low")) %>%
    dplyr::distinct()

  return(as.data.frame(filled_data))
}
