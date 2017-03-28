context("interactions")

inGR <- GenomicRanges::GRanges(
  rep("chr1", 5),
  IRanges::IRanges(
    c(10, 20, 30, 100, 1000),
    c(15, 25, 35, 105, 1005)
  )
)

cov <- IRanges::RleList(list(
  "chr1" = c(rep(c(0, 1, 0), each = 20), rep(0, 1000)),
  "chr22" = c(rep(c(0, 5, 1, 5, 0), each = 10), rep(0, 1000))
))

bwFile <- file.path(tempdir(), "test.bw")
rtracklayer::export.bw(cov, bwFile)

test_that("getCisPairs works on small example dataset", {

  gi <- getCisPairs(inGR, 50)

  expect_equal(length(gi), 3)

  a1 <- InteractionSet::anchors(gi, type = "first", id = TRUE)
  a2 <- InteractionSet::anchors(gi, type = "second", id = TRUE)
  expect_true(all(a1 < a2))
  expect_true(all(InteractionSet::pairdist(gi) <= 50))

})


test_that("coverage is added to gi on small example dataset", {

  gi <- getCisPairs(inGR, 50)

  regGR <- InteractionSet::regions(gi)

  InteractionSet::regions(gi) <- addCovToGR(
    regGR,
    bwFile,
    window = 10,
    bin_size = 1,
    colname = "cov")

})

test_that("getCisPairs works with whole CTCF motif data", {

  skip("skipt test on whole CTCF motif data set for time.")

  # use internal motif data
  motifGR <- motif.hg19.CTCF

  # get all pairs within 1Mb
  gi <- getCisPairs(motifGR, 1e6)

  expect_equal(InteractionSet::regions(gi), motifGR)
  expect_true(max(InteractionSet::pairdist(gi)) <= 1e6)

})

test_that("applyToCloseGI runs on small example dataset", {

  #'      4-|       XX
  #'      3-|      XXXX            X
  #'      2-|     XXXXXX          XX
  #'      1-|    XXXXXXXX   XXXX XXX
  #' chr1   |1...5....1....1....2....2
  #'                  0    5    0    5
  #'         <--><-->     <-->  <-->
  #' grWin     1   2        3     4
  #' strand    +   +        -     +
  #'
  #' pairs:
  #' 1 3
  #' 2 3
  #' 2 4

  exampleSeqInfo <- GenomeInfoDb::Seqinfo(seqnames = c("chr1"),
                                seqlengths = c(25),
                                isCircular = c(FALSE),
                                genome = "example")

  cov <- IRanges::RleList(list(
    "chr1" = c(rep(0,4), 1:4, 4:1, rep(0,3), rep(1,4), 0, 1:3, 0, 0)
  ))

  toyCovFile <- file.path(tempdir(), "toy.bw")
  rtracklayer::export.bw(cov, toyCovFile)

  gr <- GenomicRanges::GRanges(
    rep("chr1", 4),
    IRanges::IRanges(
      c(1, 5, 15, 20),
      c(4, 8, 18, 23)
    ),
    seqinfo = exampleSeqInfo
  )

  gi <- InteractionSet::GInteractions(
      c(1, 2, 2),
      c(3, 3, 4),
      gr
  )

  InteractionSet::regions(gi) <- addCovToGR(InteractionSet::regions(gi),
                                            toyCovFile,
                                            window = 4,
                                            bin_size = 1,
                                            colname = "cov")

  #
  l <- InteractionSet::regions(gi)$cov

  ncolBefore <- ncol(S4Vectors::mcols(gi))

  gi <- applyToCloseGI(gi, "cov", fun = cor, colname = "value")

  # check that exactly one column is added
  expect_equal(ncol(S4Vectors::mcols(gi)), ncolBefore + 1)
  expect_equal(names(S4Vectors::mcols(gi)), "value")

  # check that all cor values are correct

  expect_warning(
    manualCor <- cor(t(as.matrix(InteractionSet::regions(gi)$cov)))[
      cbind(
        InteractionSet::anchors(gi, id = TRUE, type = "first"),
        InteractionSet::anchors(gi, id = TRUE, type = "second")
      )]
  )
  expect_equal(gi$value, manualCor)

})

test_that("interactions can be annotated with Hi-C loops", {

  # skip("Skipt test on large files")

  # use internal motif data on chr22
  motifGR <- motif.hg19.CTCF[GenomeInfoDb::seqnames(motif.hg19.CTCF) == "chr22"]

  # get all pairs within 1Mb
  gi <- getCisPairs(motifGR, 1e6)

  # parse loops from internal data
  exampleLoopFile <- system.file(
    "extdata",
    "GM12878_HiCCUPS.chr22_1-18000000.loop.txt",
    package = "chromloop")

  loopGI <- parseLoopsRao(exampleLoopFile, seqinfo = GenomeInfoDb::seqinfo(gi))

  # hits <- InteractionSet::findOverlaps(gi, loopGI, type="within")

  ovl <- InteractionSet::countOverlaps(gi, loopGI, type = "within") >= 1

  S4Vectors::mcols(gi)[,"loop"] <- ovl

})