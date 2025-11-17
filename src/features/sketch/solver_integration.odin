// features/sketch - Integration with constraint solver
package ohcad_sketch

import "core:fmt"

// Solve the sketch constraints using libslvs
// Returns true if solve succeeded, false otherwise
// Updates point positions in place if successful
solve_sketch :: proc(s: ^Sketch2D) -> bool {
    result := solve_sketch_2d(s)

    if !result.success {
        fmt.printf("Sketch solve failed: %s\n", result.error_message)
        fmt.printf("  Result code: %d\n", result.result_code)
        fmt.printf("  DOF: %d\n", result.dof)
        return false
    }

    // Success!
    if result.dof > 0 {
        fmt.printf("Sketch solved (under-constrained, DOF=%d)\n", result.dof)
    } else if result.dof == 0 {
        // Fully constrained - ideal state
    } else {
        fmt.printf("Sketch solved (over-constrained, DOF=%d)\n", result.dof)
    }

    return true
}

// Get degrees of freedom without solving
// Useful for UI feedback (e.g., showing "Fully Constrained" indicator)
get_sketch_dof :: proc(s: ^Sketch2D) -> int {
    result := solve_sketch_2d(s)
    return result.dof
}
