#' This function loads weight at age data (in mgN) from the initial conditions file.
#'
#' @param dir Character string giving the path of the Atlantis model folder.
#' If data is stored in multiple folders (e.g. main model folder and output
#' folder) you should use 'NULL' as dir.
#' @param init Character string giving the filename of the initial conditions netcdf file.
#' Usually "init[...].nc".
#' @param fgs Character string giving the filename of 'functionalGroups.csv'
#' file. In case you are using multiple folders for your model files and
#' outputfiles pass the complete folder/filename string as fgs.
#' In addition set dir to 'NULL' in this case.
#' @param select_variable Character value spefifying which variable to load.
#' For \code{load_init_age} this can be "Nums", "ResN", "StructN",
#' For \code{load_init_nonage} please select "N" (default)
#' For \code{load_init_physics} simply pass the names of the physical variables.
#' @param select_groups Character vector of funtional groups which shall be read in.
#' Names have to match the ones used in the ncdf file. Check column "Name" in
#' "functionalGroups.csv" for clarification.
#' @param bboxes Integer vector giving the box-id of the boundary boxes.
#' Can be created with \code{get_boundary()}.
#' @param bps Vector of character strings giving the complete list of epibenthic
#' functional groups (Only present in the sediment layer). The names have to match
#' the column 'Name' in the 'functionalGroups.csv' file. Can be created with
#' \code{load_bps()}.
#' @family load functions
#' @export
#' @return A dataframes with columns atoutput, polygon, layer (if present), species (if present).
#'
#' @author Alexander Keth

#' @examples
#' dir <- system.file("extdata", "gns", package = "atlantistools")
#' init <- "init_simple_NorthSea.nc"
#' fgs <- "functionalGroups.csv"
#' bboxes <- get_boundary(load_box(dir, bgm = "NorthSea.bgm"))
#' bps = load_bps(dir = dir, fgs = "functionalGroups.csv",
#'                                 init = "init_simple_NorthSea.nc")
#'
#' load_init_age(dir = dir, init = init, fgs = fgs, bboxes = bboxes,
#'               select_variable = "ResN",
#'               select_groups = "cod")
#'
#' load_init_age(dir = dir, init = init, fgs = fgs, bboxes = bboxes,
#'               select_variable = "ResN")
#'
#' load_init_nonage(dir = dir, init = init, fgs = fgs, bboxes = bboxes, bps = bps,
#'                  select_groups = "crangon")
#'
#' load_init_nonage(dir = dir, init = init, fgs = fgs, bboxes = bboxes, bps = bps)

load_init_age <- function(dir = getwd(), init, fgs, select_variable, select_groups = NULL, bboxes) {
  # Consrtuct vars to search for!
  fgs_data <- load_fgs(dir = dir, fgs = fgs)
  age_groups <- get_age_groups(dir = dir, fgs = fgs)
  if (any(!is.element(select_groups, age_groups))) stop("Selected group is not a fully age-structured group.")
  if (is.null(select_groups)) select_groups <- age_groups

  num_cohorts <- fgs_data$NumCohorts[is.element(fgs_data$Name, select_groups)]
  ages <- lapply(num_cohorts, seq, from = 1, by = 1)

  vars <- NULL
  for (i in seq_along(select_groups)) {
    tags <- paste0(select_groups[i], ages[[i]], "_", select_variable)
    vars <- c(vars, tags)
  }

  # Extract data
  df_list <- load_init(dir = dir, init = init, vars = vars)
  # Add columns!
  for (i in seq_along(select_groups)) {
    for (j in 1:length(ages[[i]])) {
      if (i == 1 & j == 1) k <- 1
      df_list[[k]]$species <- select_groups[i]
      df_list[[k]]$agecl <- ages[[i]][j]
      k <- k + 1
    }
  }
  result <- do.call(rbind, df_list)

  # Cleanup
  result <- remove_min_pools(df = result)
  result <- remove_bboxes(df = result, bboxes = bboxes)
  result <- dplyr::filter_(result, ~!is.na(layer))
  result$species <- convert_factor(data_fgs = fgs_data, col = result$species)

  return(result)
}

#' @export
#' @rdname load_init_age
load_init_nonage <- function(dir = getwd(), init, fgs, select_variable = "N", select_groups = NULL, bboxes, bps) {
  # Consrtuct vars to search for!
  if (is.null(select_groups)) select_groups <- get_groups(dir = dir, fgs = fgs)
  select_bps <- select_groups[is.element(select_groups, bps)]
  select_groups <- select_groups[!is.element(select_groups, bps)]

  # Extract data for non biomasspools!
  if (length(select_groups) >= 1) {
    df_list <- load_init(dir = dir, init = init, vars = paste(select_groups, select_variable, sep = "_"))
    # Add columns!
    for (i in seq_along(select_groups)) {
      df_list[[i]]$species <- select_groups[i]
    }
    df1 <- do.call(rbind, df_list)
  }

  # Extract data for biomasspools!
  if (length(select_bps)) {
    read_nc <- RNetCDF::open.nc(con = convert_path(dir = dir, file = init))
    on.exit(RNetCDF::close.nc(read_nc))
    n_layers    <- RNetCDF::dim.inq.nc(read_nc, 2)$length
    df_list <- load_init(dir = dir, init = init, vars = paste(select_bps, select_variable, sep = "_"))
    # Add columns!
    for (i in seq_along(select_bps)) {
      df_list[[i]]$species <- select_bps[i]
    }
    df2 <- do.call(rbind, df_list)
    df2$layer <- n_layers - 1
  }

  if (length(select_groups) >= 1 & length(select_bps) >= 1)  result <- rbind(df1, df2)
  if (length(select_groups) >= 1 & !length(select_bps) >= 1) result <- df1
  if (!length(select_groups) >= 1 & length(select_bps) >= 1) result <- df2

  # Cleanup
  result <- remove_min_pools(df = result)
  result <- remove_bboxes(df = result, bboxes = bboxes)
  result <- dplyr::filter_(result, ~!is.na(layer))
  result$species <- convert_factor(data_fgs = load_fgs(dir = dir, fgs = fgs), col = result$species)

  return(result)
}

#' @export
#' @rdname load_init_age
load_init_physics <- function(dir = getwd(), init, select_variable, bboxes) {
  # Extract data!
  df_list <- load_init(dir = dir, init = init, vars = select_variable)
  # Add columns!
  for (i in seq_along(select_variable)) {
    df_list[[i]]$variable <- select_variable[i]
  }
  result <- do.call(rbind, df_list)

  # Cleanup
  result <- remove_min_pools(df = result)
  result <- remove_bboxes(df = result, bboxes = bboxes)
  result <- dplyr::filter_(result, ~!is.na(layer))

  return(result)
}

#' @export
#' @rdname load_init_age
load_init_weight <- function(dir = getwd(), init, fgs, bboxes) {
  rn <- load_init_age(dir = dir, init = init, fgs = fgs, select_variable = "ResN", bboxes = bboxes) %>%
    dplyr::select_(.dots = c("atoutput", "species", "agecl")) %>%
    dplyr::rename_(.dots = c("rn" = "atoutput")) %>%
    unique()
  sn <- load_init_age(dir = dir, init = init, fgs = fgs, select_variable = "StructN", bboxes = bboxes) %>%
    dplyr::select_(.dots = c("atoutput", "species", "agecl")) %>%
    dplyr::rename_(.dots = c("sn" = "atoutput")) %>%
    unique()
  df <- dplyr::inner_join(rn, sn, by = c("species", "agecl")) %>%
    dplyr::select_(.dots = c("species", "agecl", "sn", "rn"))
  return(df)
}





