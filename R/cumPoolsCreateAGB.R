## NOTES
#    FORCS parameters are hard coded: minimum merchantable age, a, and b (used 
#    to calculate the proportion of merchantable Stemwood)

cumPoolsCreateAGB <- function(allInfoAGBin, table6, table7, pixGroupCol = "pixelGroup"){
  counter <- 0L
  cumBiomList <- list()
  
  expectedColumns <- c("canfi_species", "juris_id", "ecozone", "age", "B", pixGroupCol)
  if (pixGroupCol == "yieldPixelGroup") {
    expectedColumns <- c(expectedColumns, "cohort_id")
  }
  if (any(!(expectedColumns %in% colnames(allInfoAGBin)))) {
    stop("The AGB table needs the following columns ", paste(expectedColumns, collapse = " "))
  }
  
  # Identify unique sp, juris_id, ecozone
  curves <- unique(allInfoAGBin[, .(canfi_species, juris_id, ecozone)])
  curves[,curve_id := .I]
  
  AGB <- merge(allInfoAGBin, curves, by = c("canfi_species", "juris_id", "ecozone"), all.x = TRUE)
  
  # Do one set of parameters at a time
  for (i_curve in curves$curve_id) {
    counter <- counter + 1L
    oneCurve <- AGB[curve_id == i_curve, ]
    
    ## IMPORTANT BOURDEWYN PARAMETERS FOR NOT HANDLE AGE 0 ##
    oneCurve <- oneCurve[which(age>0),]
    
    # Get AGB in each of the 3 pools
    cumBiom <- as.matrix(convertAGB2pools(oneCurve, table6, table7))
    
    # going from tonnes of biomass/ha to tonnes of carbon/ha here
    ### HARD CODED VALUE ####################
    cumBiom <- cumBiom * 0.5 ## this value is in sim$cbmData@biomassToCarbonRate
    
    # To handle cohortData as well
    if(pixGroupCol != "yieldPixelGroup") cohort_id <- NULL
    
    cumBiomList[[counter]] <- oneCurve[, 
                                       .(gcids = cohort_id,
                                         species = speciesCode,
                                         age = age,
                                         pixGroupColValue = get(pixGroupCol))]  # Use get() to refer to pixGroupCol dynamically
    setnames(cumBiomList[[counter]], "pixGroupColValue", pixGroupCol)
    cumBiomList[[counter]] <- cbind(cumBiomList[[counter]],
                                    cumBiom)
    
  }
  cumPools <- rbindlist(cumBiomList)
  return(cumPools)
}

convertAGB2pools <- function(oneCurve, table6, table7){
  
  # get the parameters
  spec <- as.integer(unique(oneCurve$canfi_species))
  ez <- unique(oneCurve$ecozone)
  admin <- unique(oneCurve$juris_id)
  params6 <- table6[canfi_spec == spec & ecozone == ez & juris_id == admin,][1]
  params7 <- table7[canfi_spec == spec & ecozone == ez & juris_id == admin,][1]
  
  # get the proportions of each pool
  pVect <- CBMutils::biomProp(table6 = params6, table7 = params7, vol = oneCurve$B)
  
  totTree <-  oneCurve$B
  totalStemWood <- totTree * pVect[, 1]
  
  ##TODO
  # find actual data on the proportion of totTree that is merch
  # Problem: CBM currently uses "merch" and "other" as C-pools. In these
  # equations (this function that matches the Boudewyn et al 2007 workflow),
  # totalStemwood is the sum of totMerch (eq1), b_n (eq2[,1] - stem wood biomass
  # of live, nonmerchantable-sized trees) and b_s (eq3 - stem wood biomass of
  # live, sapling-sized trees). The "merch" and the "other" C-pool requires us
  # to know the proportion of totalStemWood that is "merch" and "other"
  ##### IMPORTANT HARD CODING INFORMATION #######
  ## current fix: using the same parameters as FORCS (Forest Carbon Succession
  ## Extension V3.1). Eq 1 on p20 is PropStem = a *(1-b^Age) where a is 0.7546
  ## and b is 0.983. FORCS also sets a minimum merchantable age per species.
  ## Because we are in the RIA, I am setting that at 15. This needs to be a
  ## parameter either from LandR or set by the user (by provinces by species? -
  ## this is usually a diamter not an age)
  
  ### HARD CODED minimum merchantable age, a, b
  minMerchAge <-  15
  a <- 0.7546
  b <- 0.983
  
  # if age < MinMerchAge, the propMerch is 0, otherwise use FORCS, until we find actual data.
  propMerch <- (oneCurve$age >= minMerchAge) * a * (1-b^oneCurve$age)
  
  totMerch <- propMerch * totalStemWood
  
  # otherStemWood is everything that is not totMerch
  otherStemWood <- totalStemWood - totMerch
  
  bark <- totTree * pVect[, 2]
  branch <- totTree * pVect[, 3]
  fol <- totTree * pVect[, 4]
  other <- branch + bark + otherStemWood
  biomCumulative <- as.matrix(cbind(totMerch,fol,other))
  return(biomCumulative)
}

