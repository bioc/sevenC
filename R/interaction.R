#' Build a \code{\link{GInteractions}} object with all pairs of input
#' \code{\link{GRanges}} within a given distance.
#'
#' Distance is calculated from the center of input regions.
#'
#' @param inGR \code{\link{GRanges}} object of genomic regions. The ranges shuld
#'   be sorted according to chr, strand, and start position. Use
#'   \code{\link[GenomicRanges]{sort()}} to sort it.
#' @param maxDist maximal distance in base-pairs between pairs of ranges as
#'   single  numeric value.
#' @return A \code{\link[InteractionSet]{GInteractions}} object with all pairs
#'   within the given distance.
#' @export
getCisPairs <- function(inGR, maxDist=10^6){

  # check that input GRanges object is sorted
  if( !all(inGR == sort(inGR))) stop("Input ranges inGR need to be sorted. Use
                                     sort(inGR) to sort it")

  # get center postions of each input range
  posGR <- GenomicRanges::resize(inGR, width=1, fix="center")

  # calculate overlap all possible gene pairs within maxDist bp
  hits <- GenomicRanges::findOverlaps(posGR,
                      maxgap=maxDist,
                      drop.redundant=TRUE,
                      drop.self=TRUE,
                      ignore.strand=TRUE)

  # build IntractionSet object
  gi <- InteractionSet::GInteractions(
    S4Vectors::queryHits(hits),
    S4Vectors::subjectHits(hits),
    inGR,
    mode="strict"
  )

  # sort gi
  gi <- BiocGenerics::sort(gi)


  # add distance
  gi$dist <- InteractionSet::pairdist(gi, type="mid")

  # remove pairs with distance >= maxDist
  # this is essential in case of non-zero length ranges in inGR
  gi <- gi[gi$dist <= maxDist]

  return(gi)
}


#' returns indecies of columns with non-zero variance
#'
#' @param dat data.frame or matirx
#' @return column indecies of columns with non-zero variance
noZeroVar <- function(dat) {
  out <- apply(dat, 2, function(x) length(unique(x)))
  which(out > 1)
}

#' Apply a function to pairs of close genomic regions.
#'
#' This function adds a vector with the resulting functin call for each input
#' interaction.
#'
#'
#' @param gi A sorted \code{\link[InteractionSet]{GInteractions}} object.
#' @param datacol a string matching an annotation column in \code{regions(gi)}.
#'   This collumn is assumed to hold the same number of values for each
#'   interaction \code{NumericList}.
#' @param fun A function that takes two numeric vectors as imput to compute a
#'   summary statsitic. Default is \code{\link{cor()}}.
#' @param colname A string that is used as columnname for the new column in
#'   \code{gi}.
#' @param maxDist maximal distance of pairs in bp as numeric. If maxDist=NULL,
#'   the maximal distance is computed from input interactions gi by
#'   \code{max(pairdist(gi))}.
#' @return A \code{\link[InteractionSet]{GInteractions}} similar to \code{gi}
#'   just wiht an additinoal column added.
#' @export
#' @import data.table
applyToCloseGI <- function(gi, datcol, fun=cor, colname="value", maxDist=NULL){

  # Algorithm
  # (0) define maxDist
  # (1) Group genome in overlapping bins of size 2*maxDist
  # (2) Run pairwise correlation for all ranges in each bin
  # (3) Combine correlations to data.frame with proper id1 and id2 in first columns
  # (4) Query data frame with input pairs
  #   /uses inner_join() from dplyr like in
  #  http://stackoverflow.com/questions/26596305/match-two-data-frames-based-on-multiple-columns

  # check input
  if ( any(is.na(GenomeInfoDb::seqlengths(gi))) ) stop("gi object need seqlengths.")

  #-----------------------------------------------------------------------------
  # (0) define maxDist
  #-----------------------------------------------------------------------------
  if(is.null(maxDist)){
    maxDist <- max(InteractionSet::pairdist(gi))
  }else{
    if(maxDist < max(InteractionSet::pairdist(gi))) stop("maxDist is smaller than maximal distance between interactions in input gi.")
  }

  #-----------------------------------------------------------------------------
  # (1) group ranges in by bins
  #-----------------------------------------------------------------------------

  message("INFO: Prepare Genomic bins...")

  # if (all(!is.na(seqlengths(ancGR))))
  # create GRanges object for entire genome
  genomeGR <- GenomicRanges::GRanges(GenomeInfoDb::seqinfo(gi))

  # tile genoe in overlapping bins of with 2*maxDist
  binGR <- unlist(GenomicRanges::slidingWindows(genomeGR, 2*maxDist, maxDist))

  hits <- GenomicRanges::findOverlaps(binGR, InteractionSet::regions(gi))

  #-----------------------------------------------------------------------------
  # (2) compute pairwise correlatin for all ranges in each bin
  #-----------------------------------------------------------------------------
  message("INFO: compute correlations for each group...")

  covList <- S4Vectors::mcols(InteractionSet::regions(gi))[,datcol]
  datamat <- as.matrix(covList)

  corMatList <- lapply(1:length(binGR), function(i){

    # #DEBUG:
    # message("DEBUG: index i, ", i)

    # get regions in this bin
    regIdx <- S4Vectors::subjectHits(hits)[S4Vectors::queryHits(hits) == i]

    if (length(regIdx) == 1){
      dat <- cbind(datamat[regIdx,])
    }else{
      dat <- t(datamat[regIdx,])
    }

    # get indices with non-zero variance (they casue warning and NA in cor())
    subIdx <- noZeroVar(dat)

    n = length(subIdx)

    # compute pairwise correlations for all regions in this bin
    if (n != 1){

      m <- cor(dat[,subIdx])

    }else{

      m <- 1

    }

    # constract data.table object for all pairs
    corDT <- data.table::data.table(
      rep(regIdx[subIdx], n),
      rep(regIdx[subIdx], each=n),
      array(m)
    )

  })

  #-----------------------------------------------------------------------------
  # (3) combine all data.frames
  #-----------------------------------------------------------------------------
  message("INFO: Combine data.tables of pairwise correlations...")
  # corDF <- data.frame(do.call("rbind", corMatList))
  corDT <- data.table::rbindlist(corMatList)

  #-----------------------------------------------------------------------------
  # (4) Query with input pairs
  #-----------------------------------------------------------------------------

  # names(corDF) <- c("id1", "id2", "val")
  names(corDT) <- c("id1", "id2", "val")
  data.table::setkeyv(corDT, cols=c("id1", "id2"))

  # convert gp into data.table and set keys to id1 and id2 columns
  #names(gp)[1:2] <- c("id1", "id2")
  gpDT <- data.table::data.table(
    id1 = InteractionSet::anchors(gi, type="first", id=TRUE),
    id2 = InteractionSet::anchors(gi, type="second", id=TRUE),
    key=c("id1", "id2")
  )

  message("INFO: Query correlation for input pairs...")
  matches <- corDT[gpDT, on=c("id1", "id2"), mult="first"]

  #return(matches$val)
  S4Vectors::mcols(gi)[,colname] <- matches$val

  return(gi)
}


#' Add column to \code{\link{GenomicInteraction}} with overlap support.
#'
#' See overlap methods in \code{\link{InteractionSet}} package for more details
#' on the oberlap calculations: \code{?InteractionSet::overlapsAny}
#'
#' @param gi \code{\link{GenomicInteraction}} object
#' @param subject another \code{\link{GenomicInteraction}} object
#' @param colname name of the new annotation columm in \code{gi}.
#' @param ... addtional arguments passed to \code{\link{IRanges::overlapsAny}}.
#' @return \code{\link{InteractionSet}} \code{gi} as input but with additonal
#'   annotation column \code{colname} indicationg whthere there each interaction
#'   is supported by \code{subject} or not.
#' @export
addInteractionSupport <- function(gi, subject, colname, ...){

  ol <- IRanges::overlapsAny(gi, subject, ...)

  gi$Loop_Rao_GM12878 <- factor(ol, c(FALSE, TRUE), c("No loop", "Loop"))

  return(gi)
}


