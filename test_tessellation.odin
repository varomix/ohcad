package main

import "core:fmt"
import tess "src/core/tessellation"

main :: proc() {
    fmt.println("Testing libtess2 bindings...")

    if !tess.test_simple_square() {
        fmt.println("\n❌ Test FAILED")
        return
    }

    fmt.println("\n✅ All tests PASSED")
}
