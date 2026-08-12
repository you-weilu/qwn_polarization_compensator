// correction_solver.v
// Latches the V-pass result (psi, chi, delta) into an internal 
// register on the first pass; combines it with the D-pass result 
// on the second pass to compute the required QWP angle, HWP angle, 
// and LCR retardance following the paper's 3-step algorithm (Sec. 3A).