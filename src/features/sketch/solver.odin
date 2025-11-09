// features/sketch - Levenberg-Marquardt Constraint Solver
package ohcad_sketch

import "core:fmt"
import "core:math"

// Solver configuration
SolverConfig :: struct {
    max_iterations: int,     // Maximum solver iterations
    tolerance: f64,          // Convergence tolerance (residual norm)
    lambda_initial: f64,     // Initial damping parameter
    lambda_factor: f64,      // Factor to increase/decrease lambda
    epsilon: f64,            // Finite difference epsilon for Jacobian
}

// Default solver configuration
default_solver_config :: proc() -> SolverConfig {
    return SolverConfig{
        max_iterations = 100,
        tolerance = 1e-6,
        lambda_initial = 0.01,
        lambda_factor = 10.0,
        epsilon = 1e-8,
    }
}

// Solver result status
SolverStatus :: enum {
    Success,           // Converged successfully
    MaxIterations,     // Reached max iterations without converging
    Overconstrained,   // System is overconstrained (conflicting constraints)
    Underconstrained,  // System is underconstrained (needs more constraints)
    NumericalError,    // Numerical error (NaN, singular matrix, etc.)
}

// Solver result
SolverResult :: struct {
    status: SolverStatus,
    iterations: int,
    final_residual: f64,
    message: string,
}

// =============================================================================
// Levenberg-Marquardt Solver
// =============================================================================

// Solve sketch constraints using Levenberg-Marquardt algorithm
sketch_solve_constraints :: proc(sketch: ^Sketch2D, config: Maybe(SolverConfig) = nil) -> SolverResult {
    result: SolverResult

    // Use provided config or default
    solver_config := config.? or_else default_solver_config()

    // Check DOF status
    dof_info := sketch_calculate_dof(sketch)

    if dof_info.status == .Overconstrained {
        result.status = .Overconstrained
        result.message = "Sketch is overconstrained (conflicting constraints)"
        return result
    }

    // Allow solving underconstrained sketches - they'll partially solve
    // Just warn but continue
    if dof_info.status == .Underconstrained {
        fmt.printf("⚠️  Sketch is underconstrained (DOF: %d), will solve partially\n", dof_info.dof)
    }

    // Pack variables (all non-fixed point coordinates)
    variables, var_count := pack_variables(sketch)
    defer delete(variables)

    if var_count == 0 {
        result.status = .Success
        result.message = "No free variables to solve"
        return result
    }

    // Levenberg-Marquardt main loop
    lambda := solver_config.lambda_initial

    for iter in 0..<solver_config.max_iterations {
        // Evaluate residuals at current position
        residuals := sketch_evaluate_constraints(sketch)
        defer delete(residuals)

        residual_count := len(residuals)
        if residual_count == 0 {
            result.status = .Success
            result.iterations = iter
            result.message = "No constraints to solve"
            return result
        }

        // Calculate residual norm
        residual_norm := compute_norm(residuals)

        // Check convergence
        if residual_norm < solver_config.tolerance {
            result.status = .Success
            result.iterations = iter
            result.final_residual = residual_norm
            result.message = "Converged successfully"
            return result
        }

        // Compute Jacobian (numerical)
        jacobian := compute_jacobian(sketch, solver_config.epsilon)
        defer delete(jacobian)

        // Solve normal equations: (J^T * J + lambda * I) * delta = -J^T * r
        solved := false
        for attempt in 0..<10 {  // Try different damping values
            delta, ok := solve_normal_equations(jacobian, residuals, lambda, var_count, residual_count)

            if !ok {
                // Increase damping and retry
                lambda *= solver_config.lambda_factor
                continue
            }
            defer delete(delta)

            // Apply update
            apply_delta(sketch, delta)

            // Evaluate new residuals
            new_residuals := sketch_evaluate_constraints(sketch)
            new_residual_norm := compute_norm(new_residuals)
            delete(new_residuals)

            // Check if update improved the solution
            if new_residual_norm < residual_norm {
                // Good step - decrease damping
                lambda /= solver_config.lambda_factor
                solved = true
                break
            } else {
                // Bad step - undo update and increase damping
                apply_delta(sketch, delta, -1.0)  // Negate delta
                lambda *= solver_config.lambda_factor
            }
        }

        if !solved {
            result.status = .NumericalError
            result.iterations = iter
            result.final_residual = residual_norm
            result.message = "Could not find valid step"
            return result
        }
    }

    // Max iterations reached
    residuals := sketch_evaluate_constraints(sketch)
    result.status = .MaxIterations
    result.iterations = solver_config.max_iterations
    result.final_residual = compute_norm(residuals)
    result.message = "Reached maximum iterations"
    delete(residuals)

    return result
}

// =============================================================================
// Variable Packing/Unpacking
// =============================================================================

// Pack all non-fixed point coordinates into a flat array
pack_variables :: proc(sketch: ^Sketch2D) -> ([]f64, int) {
    count := 0
    for point in sketch.points {
        if !point.fixed {
            count += 2  // x and y
        }
    }

    if count == 0 {
        return nil, 0
    }

    vars := make([]f64, count)
    idx := 0

    for point in sketch.points {
        if !point.fixed {
            vars[idx] = point.x
            vars[idx + 1] = point.y
            idx += 2
        }
    }

    return vars, count
}

// Apply delta to sketch variables
apply_delta :: proc(sketch: ^Sketch2D, delta: []f64, scale: f64 = 1.0) {
    idx := 0

    for &point in sketch.points {
        if !point.fixed {
            if idx + 1 < len(delta) {
                point.x += delta[idx] * scale
                point.y += delta[idx + 1] * scale
                idx += 2
            }
        }
    }
}

// =============================================================================
// Jacobian Computation (Numerical)
// =============================================================================

// Compute Jacobian matrix using finite differences
// J[i,j] = ∂r[i]/∂x[j]
compute_jacobian :: proc(sketch: ^Sketch2D, epsilon: f64) -> []f64 {
    // Get variable count
    _, var_count := pack_variables(sketch)

    // Get residual count
    residuals := sketch_evaluate_constraints(sketch)
    residual_count := len(residuals)
    delete(residuals)

    // Allocate Jacobian (row-major: residual_count x var_count)
    jacobian := make([]f64, residual_count * var_count)

    // Compute each column via finite differences
    var_idx := 0
    for &point in sketch.points {
        if point.fixed do continue

        // Perturb x coordinate
        original_x := point.x
        point.x += epsilon

        residuals_plus := sketch_evaluate_constraints(sketch)

        point.x = original_x - epsilon
        residuals_minus := sketch_evaluate_constraints(sketch)

        point.x = original_x

        // Central difference: (f(x+h) - f(x-h)) / 2h
        for i in 0..<residual_count {
            jacobian[i * var_count + var_idx] = (residuals_plus[i] - residuals_minus[i]) / (2.0 * epsilon)
        }

        delete(residuals_plus)
        delete(residuals_minus)
        var_idx += 1

        // Perturb y coordinate
        original_y := point.y
        point.y += epsilon

        residuals_plus = sketch_evaluate_constraints(sketch)

        point.y = original_y - epsilon
        residuals_minus = sketch_evaluate_constraints(sketch)

        point.y = original_y

        // Central difference
        for i in 0..<residual_count {
            jacobian[i * var_count + var_idx] = (residuals_plus[i] - residuals_minus[i]) / (2.0 * epsilon)
        }

        delete(residuals_plus)
        delete(residuals_minus)
        var_idx += 1
    }

    return jacobian
}

// =============================================================================
// Normal Equations Solver
// =============================================================================

// Solve (J^T * J + lambda * I) * delta = -J^T * r
// Returns delta and success flag
solve_normal_equations :: proc(
    jacobian: []f64,
    residuals: []f64,
    lambda: f64,
    var_count: int,
    residual_count: int,
) -> ([]f64, bool) {
    // Compute J^T * J
    jtj := make([]f64, var_count * var_count)
    defer delete(jtj)

    for i in 0..<var_count {
        for j in 0..<var_count {
            sum := f64(0)
            for k in 0..<residual_count {
                sum += jacobian[k * var_count + i] * jacobian[k * var_count + j]
            }
            jtj[i * var_count + j] = sum
        }
    }

    // Add damping: J^T * J + lambda * I
    for i in 0..<var_count {
        jtj[i * var_count + i] += lambda
    }

    // Compute -J^T * r
    jtr := make([]f64, var_count)
    defer delete(jtr)

    for i in 0..<var_count {
        sum := f64(0)
        for k in 0..<residual_count {
            sum += jacobian[k * var_count + i] * residuals[k]
        }
        jtr[i] = -sum
    }

    // Solve linear system using Cholesky decomposition
    delta := make([]f64, var_count)
    ok := solve_cholesky(jtj, jtr, delta, var_count)

    if !ok {
        delete(delta)
        return nil, false
    }

    return delta, true
}

// Solve A * x = b using Cholesky decomposition (A must be positive definite)
solve_cholesky :: proc(A: []f64, b: []f64, x: []f64, n: int) -> bool {
    // Allocate lower triangular matrix L
    L := make([]f64, n * n)
    defer delete(L)

    // Cholesky decomposition: A = L * L^T
    for i in 0..<n {
        for j in 0..=i {
            sum := A[i * n + j]

            for k in 0..<j {
                sum -= L[i * n + k] * L[j * n + k]
            }

            if i == j {
                if sum <= 0.0 {
                    // Not positive definite
                    return false
                }
                L[i * n + j] = math.sqrt(sum)
            } else {
                if L[j * n + j] == 0.0 {
                    return false
                }
                L[i * n + j] = sum / L[j * n + j]
            }
        }
    }

    // Forward substitution: L * y = b
    y := make([]f64, n)
    defer delete(y)

    for i in 0..<n {
        sum := b[i]
        for k in 0..<i {
            sum -= L[i * n + k] * y[k]
        }
        if L[i * n + i] == 0.0 {
            return false
        }
        y[i] = sum / L[i * n + i]
    }

    // Back substitution: L^T * x = y
    for i := n - 1; i >= 0; i -= 1 {
        sum := y[i]
        for k in i + 1..<n {
            sum -= L[k * n + i] * x[k]
        }
        if L[i * n + i] == 0.0 {
            return false
        }
        x[i] = sum / L[i * n + i]
    }

    return true
}

// =============================================================================
// Utility Functions
// =============================================================================

// Compute L2 norm of vector
compute_norm :: proc(v: []f64) -> f64 {
    sum := f64(0)
    for val in v {
        sum += val * val
    }
    return math.sqrt(sum)
}

// Print solver result
solver_result_print :: proc(result: SolverResult) {
    fmt.printf("Solver Result:\n")
    fmt.printf("  Status: %v\n", result.status)
    fmt.printf("  Iterations: %d\n", result.iterations)
    fmt.printf("  Final Residual: %.6e\n", result.final_residual)
    fmt.printf("  Message: %s\n", result.message)
}
