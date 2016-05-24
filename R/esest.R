esest <- function(yi, vi, zval, zcv, ksig, method) {
  
  ### Compute bounds for effect size estimation
  bo <- bounds(yi = yi, vi = vi, zval = zval, zcv = zcv, ext = FALSE)
  bo.ext <- bounds(yi = yi, vi = vi, zval = zval, zcv = zcv, ext = TRUE)
  
  ### Function that will be used for root-finding/optimization
  pdist <- function(d, yi, vi, zval, zcv, ksig, val, method, cv.P) {
    
    zd <- d/sqrt(vi) # Transform d to zd for approximation
    
    q <- numeric(length(yi)) # Empty object for storing transformed p-values
    ### Loop for computing transformed p-values
    for (i in 1:length(yi)) {
      if (zcv[i] - zd[i] <= 38) { # Do not use approximation
        pmarg <- exp(pnorm(zcv[i] * sqrt(vi[i]), mean = d, sd = sqrt(vi[i]), 
                           lower.tail = FALSE, log.p = TRUE))
        ph1 <- exp(pnorm(yi[i], mean = d, sd = sqrt(vi[i]), lower.tail = FALSE, 
                         log.p = TRUE))
        q[i] <- ph1/pmarg
      } else { # Approximate P(Z>=zval) and P(Z>=zcv)
        q[i] <- approx(zd[i], zval[i], zcv[i])
      }
    }
    
    if (val == "est") { tr.q <<- q } # Store transformed p-values
    
    if (method == "LNP") {
      stat <- sum(-log(q))
    } else if (method == "LN1MINP") {
      stat <- sum(-log(1-q))
    } else if (method == "P") {
      stat <- sum(q)
    } else if (method == "KS" & val == "est") {
      out <- ks.test(x = q, y = punif)$statistic
    } else if (method == "AD" & val == "est") {
      out <- as.numeric(ADGofTest::ad.test(x = q, distr.fun = punif)$statistic)
    }
    
    if (val == "est" & (method == "LNP" | method == "LN1MINP" | method == "P")) {
      out <- stat - ksig
    } else if (val == "ci.lb" & (method == "LNP" | method == "LN1MINP")) {
      out <- stat - qgamma(0.975, ksig, 1)
    } else if (val == "ci.ub" & (method == "LNP" | method == "LN1MINP")) {
      out <- stat - qgamma(0.025, ksig, 1)
    } else if (val == "ci.ub" & method == "P") {
      out <- stat - cv.P
    } else if (val == "ci.lb" & method == "P") {
      out <- stat - cv.P
    }
    
    out
  }
  
  ### Estimate effect size
  if (method == "KS" | method == "AD") { # Estimating effect size based on minimizing test statistic
    ### Lower and upper bound of CI cannot be estimated with this procedure
    ci.lb <- NA 
    ci.ub <- NA
    approx.ci.lb <- 0
    approx.ci.ub <- 0
    if (method == "KS") { # Estimate effect size with estimate of P method as search interval
      est.bo <- try(bisect(func = pdist, lo = bo[1], hi = bo[2], 
                           yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig/2, 
                           val = "est", method = "P"), silent = TRUE)
      if (class(est.bo) == "try-error") { # Estimate of method = P with extended search interval
        est.bo <- bisect(func = pdist, lo = bo.ext[1], hi = bo.ext[2], 
                         yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig/2, 
                         val = "est", method = "P")
      }
      ### Minimize test statistic for KS
      est <- suppressWarnings(try(as.numeric(optimize(pdist, interval = c(est.bo-1.5, est.bo+1.5),
                                                      yi = yi, vi = vi, zval = zval, zcv = zcv, 
                                                      ksig = ksig, val = "est",
                                                      method = method)$minimum), silent = TRUE))
      if (class(est) == "try-error") { est <- NA }
    }
    if (method == "AD") { # Apply quasi-Newton Raphson algorithm for Anderson-Darling method
      est.AD <- suppressWarnings(nlm(pdist, p = 0, yi = yi, vi = vi, zval = zval, 
                                     zcv = zcv, ksig = ksig, val = "est", method = method))
      ### If gradient of tangent line is below 0.1 save estimate
      est <- ifelse(est.AD$gradient < 0.1, est.AD$estimate, NA)
    }
    ### Assign value to object in order to show notification in output
    approx.est <- ifelse(is.na(est) == FALSE & any(zcv-est/sqrt(vi) > 38), 1, 0)
  } else {
    ksig.est <- ifelse(method == "P", ksig/2, ksig) # If method = P divide ksig by two
    approx.est <- 0 # Assign value to object in order to show notification
    est <- try(bisect(func = pdist, lo = bo[1], hi = bo[2], yi = yi, 
                      vi = vi, zval = zval, zcv = zcv, ksig = ksig.est, val = "est", 
                      method = method), silent = TRUE)
    if (class(est) == "try-error") { # Apply bisection method with extended search interval
      approx.est <- 1 # Assign value to object in order to show notification
      est <- try(bisect(func = pdist, lo = bo.ext[1], hi = bo.ext[2], 
                        yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig.est, 
                        val = "est", method = method), silent = TRUE)
      if (class(est) == "try-error") { est <- NA } # If estimate cannot be computed, return NA
    }
    
    ### Apply bisection method for lower bound
    if (method == "P") {
      approx.ci.lb <- 0 # Assign value to object in order to show notification
      ci.lb <- try(bisect(func = pdist, lo = bo[1], hi = est, yi = yi, 
                          vi = vi, zval = zval, zcv = zcv, ksig = ksig, val = "ci.lb", 
                          method = method, cv.P = get.cv.P(ksig)), silent = TRUE)
      if (class(ci.lb) == "try-error") { # Apply bisection method with extended search interval
        approx.ci.lb <- 1 # Assign value to object in order to show notification
        ci.lb <- try(bisect(func = pdist, lo = bo.ext[1], hi = est, 
                            yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig, 
                            val = "ci.lb", method = method, cv.P = get.cv.P(ksig)), 
                     silent = TRUE)
        if (class(ci.lb) == "try-error") { ci.lb <- NA }
      }
    } else if (method == "LN1MINP") {
      approx.ci.lb <- 0 # Assign value to object in order to show notification
      ### If method = LN1MINP switch lower and upper bound
      ci.lb <- try(bisect(func = pdist, lo = bo[1], hi = est, yi = yi, 
                          vi = vi, zval = zval, zcv = zcv, ksig = ksig, val = "ci.ub", 
                          method = method), silent = TRUE)
      if (class(ci.lb) == "try-error") { # Apply bisection method with extended search interval
        approx.ci.lb <- 1 # Assign value to object in order to show notification
        ci.lb <- try(bisect(func = pdist, lo = bo.ext[1], hi = est, 
                            yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig, 
                            val = "ci.ub", method = method), silent = TRUE)
        if (class(ci.lb) == "try-error") { ci.lb <- NA }
      }
    } else {
      approx.ci.lb <- 0 # Assign value to object in order to show notification
      ci.lb <- try(bisect(func = pdist, lo = bo[1], hi = est, yi = yi, 
                          vi = vi, zval = zval, zcv = zcv, ksig = ksig, val = "ci.lb", 
                          method = method), silent = TRUE)
      if (class(ci.lb) == "try-error") { # Apply bisection method with extended search interval
        approx.ci.lb <- 1 # Assign value to object in order to show notification
        ci.lb <- try(bisect(func = pdist, lo = bo.ext[1], hi = est, 
                            yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig, 
                            val = "ci.lb", method = method), silent = TRUE)
        if (class(ci.lb) == "try-error") { ci.lb <- NA }
      }
    }
    
    ### Apply bisection method for upper bound
    if (method == "P") {
      ci.ub <- try(bisect(func = pdist, lo = est, hi = bo[2], yi = yi, 
                          vi = vi, zval = zval, zcv = zcv, ksig = ksig, val = "ci.ub", 
                          method = method, cv.P = ksig - get.cv.P(ksig)), silent = TRUE)
      if (class(ci.ub) == "try-error") { ci.ub <- NA }
    } else if (method == "LN1MINP") {
      if (is.na(est) == TRUE) { # If est could not be estimated: use lower bound search interval
        ci.ub <- try(bisect(func = pdist, lo = bo[1], hi = bo[2], 
                            yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig, 
                            val = "ci.lb", method = method), silent = TRUE)
      } else {
        ci.ub <- try(bisect(func = pdist, lo = est, hi = bo[2], 
                            yi = yi, vi = vi, zval = zval, zcv = zcv, ksig = ksig, 
                            val = "ci.lb", method = method), silent = TRUE)
      }
    } else if (method == "LNP") {
      if (is.na(est) == TRUE) { # If est could not be estimated: use lower bound search interval
        ci.ub <- try(bisect(func = pdist, lo = bo[1], hi = bo[2], yi = yi, 
                            vi = vi, zval = zval, zcv = zcv, ksig = ksig, val = "ci.ub", 
                            method = method), silent = TRUE)
      } else {
        ci.ub <- try(bisect(func = pdist, lo = est, hi = bo[2], yi = yi, 
                            vi = vi, zval = zval, zcv = zcv, ksig = ksig, val = "ci.ub", 
                            method = method), silent = TRUE)
      }
      if (class(ci.ub) == "try-error") { ci.ub <- NA }
    }
  }
  
  return(list(est = est, ci.lb = ci.lb, ci.ub = ci.ub, approx.est = max(approx.est), 
              approx.ci.lb = max(approx.ci.lb), ext.lb = bo.ext[1], tr.q = tr.q))
} 