# SDL3 Multi-Touch API Research

**Date:** November 9, 2024
**Purpose:** Research SDL3's multi-touch capabilities for implementing macOS trackpad gestures in OhCAD
**SDL Version:** 3.2.26 (verified working on macOS)

---

## Executive Summary

SDL3 provides **excellent multi-touch support** with native finger tracking, touch device detection, and normalized coordinates. While SDL3 removed high-level gesture recognition (pinch, rotate) from SDL2, it provides **low-level finger tracking** that allows us to implement custom gesture detection.

### Key Findings

✅ **Native touch device detection** - Enumerate and identify touch devices (trackpad, touchscreen, etc.)
✅ **Multi-finger tracking** - Track up to unlimited simultaneous fingers with unique IDs
✅ **Normalized coordinates** - (0.0-1.0) for device-independent touch handling
✅ **Pressure sensitivity** - Normalized pressure data (0.0-1.0)
✅ **Delta movement** - dx/dy for velocity calculations
✅ **Device type detection** - Distinguish between trackpad (INDIRECT_RELATIVE) and touchscreen (DIRECT)

⚠️ **No built-in gesture recognition** - SDL3 removed gesture events; we need custom implementation
✅ **Custom gestures possible** - Low-level finger data allows implementing pinch, rotate, swipe, etc.

---

## Touch Device API

### Device Enumeration

```odin
import sdl "vendor:sdl3"

// Get all connected touch devices
count: i32
devices := sdl.GetTouchDevices(&count)
defer sdl.free(devices)

for i in 0..<count {
    touch_id := devices[i]
    name := sdl.GetTouchDeviceName(touch_id)
    device_type := sdl.GetTouchDeviceType(touch_id)

    fmt.printf("Touch Device %d: %s (Type: %v)\n", i, name, device_type)
}
```

### Touch Device Types

```odin
TouchDeviceType :: enum {
    INVALID = -1,
    DIRECT,                 // Touch screen with window-relative coordinates
    INDIRECT_ABSOLUTE,      // Trackpad with absolute device coordinates
    INDIRECT_RELATIVE,      // Trackpad with screen cursor-relative coordinates (macOS)
}
```

**macOS trackpads** typically report as `INDIRECT_RELATIVE`.

---

## Touch Events

### Event Types

SDL3 provides four finger event types:

```odin
EventType :: enum {
    FINGER_DOWN      = 0x700,  // Finger touched the surface
    FINGER_UP,                 // Finger lifted from surface
    FINGER_MOTION,             // Finger moved while touching
    FINGER_CANCELED,           // Touch interrupted (e.g., system gesture)
}
```

### TouchFingerEvent Structure

```odin
TouchFingerEvent :: struct {
    using commonEvent: CommonEvent,
    touchID:  TouchID,   // Touch device ID
    fingerID: FingerID,  // Unique finger ID (tracks individual fingers)
    x:        f32,       // Normalized X position (0.0 - 1.0)
    y:        f32,       // Normalized Y position (0.0 - 1.0)
    dx:       f32,       // Normalized X delta (-1.0 - 1.0)
    dy:       f32,       // Normalized Y delta (-1.0 - 1.0)
    pressure: f32,       // Pressure (0.0 - 1.0)
    windowID: WindowID,  // Window underneath finger (if any)
}
```

### Key Features

1. **Unique Finger IDs**: Each finger gets a unique `FingerID` that persists for the duration of the touch
2. **Normalized Coordinates**: All positions are 0.0-1.0 relative to window size
3. **Delta Movement**: `dx` and `dy` provide velocity/direction information
4. **Pressure Data**: Full pressure sensitivity (useful for stylus/pen)
5. **Window Awareness**: Knows which window the touch occurred on

---

## Getting Active Fingers

You can query active fingers at any time (useful for gesture detection):

```odin
// Get all currently touching fingers on a device
count: i32
fingers := sdl.GetTouchFingers(touch_id, &count)
defer sdl.free(fingers)

for i in 0..<count {
    finger := fingers[i]
    fmt.printf("Finger %d at (%.2f, %.2f) pressure=%.2f\n",
               finger.id, finger.x, finger.y, finger.pressure)
}
```

The `Finger` structure:

```odin
Finger :: struct {
    id:       FingerID,  // Unique finger identifier
    x:        f32,       // Normalized X (0.0-1.0)
    y:        f32,       // Normalized Y (0.0-1.0)
    pressure: f32,       // Pressure (0.0-1.0)
}
```

---

## Gesture Implementation Strategy

Since SDL3 removed built-in gesture recognition, we need to implement custom gesture detection using the low-level finger data.

### 2-Finger Orbit (Drag)

**Algorithm:**
1. Track when exactly 2 fingers are active
2. Calculate centroid of both fingers
3. Track centroid movement (dx, dy)
4. Apply as camera orbit (azimuth += dx, elevation += dy)

```odin
GestureState :: struct {
    active_fingers: map[FingerID]Finger,  // Currently touching fingers
    prev_centroid: [2]f32,                // Previous 2-finger center
    is_two_finger_drag: bool,
}

detect_orbit_gesture :: proc(state: ^GestureState) -> (azimuth_delta, elevation_delta: f32) {
    if len(state.active_fingers) != 2 {
        state.is_two_finger_drag = false
        return 0, 0
    }

    // Calculate centroid of 2 fingers
    centroid := [2]f32{0, 0}
    for _, finger in state.active_fingers {
        centroid.x += finger.x
        centroid.y += finger.y
    }
    centroid /= 2

    if !state.is_two_finger_drag {
        state.is_two_finger_drag = true
        state.prev_centroid = centroid
        return 0, 0
    }

    // Calculate delta
    dx := centroid.x - state.prev_centroid.x
    dy := centroid.y - state.prev_centroid.y
    state.prev_centroid = centroid

    // Scale to camera sensitivity (typical: 0.01-0.05)
    return dx * 0.02, dy * 0.02
}
```

### 2-Finger Pinch (Zoom)

**Algorithm:**
1. Track when exactly 2 fingers are active
2. Calculate distance between fingers
3. Compare to previous distance
4. Scale < 1.0 = zoom out, > 1.0 = zoom in

```odin
detect_pinch_gesture :: proc(state: ^GestureState) -> (zoom_factor: f32) {
    if len(state.active_fingers) != 2 {
        return 1.0  // No zoom
    }

    // Get 2 finger positions
    fingers := make([dynamic]Finger, 0, 2)
    for _, finger in state.active_fingers {
        append(&fingers, finger)
    }

    // Calculate distance between fingers
    dx := fingers[1].x - fingers[0].x
    dy := fingers[1].y - fingers[0].y
    distance := math.sqrt(dx*dx + dy*dy)

    // Compare to previous distance
    if state.prev_distance == 0 {
        state.prev_distance = distance
        return 1.0
    }

    // Calculate zoom factor (ratio of distances)
    zoom := distance / state.prev_distance
    state.prev_distance = distance

    // Clamp zoom to reasonable range
    return clamp(zoom, 0.9, 1.1)  // Max 10% per frame
}
```

### 2-Finger Pan (with Shift modifier)

**Algorithm:**
1. Check if Shift key is held
2. If yes + 2 fingers, use centroid movement for pan
3. Apply to camera target position

```odin
detect_pan_gesture :: proc(state: ^GestureState, shift_held: bool) -> (pan_x, pan_y: f32) {
    if !shift_held || len(state.active_fingers) != 2 {
        return 0, 0
    }

    // Same as orbit, but interpret as pan instead
    centroid := calculate_centroid(state.active_fingers)

    if state.prev_centroid == nil {
        state.prev_centroid = centroid
        return 0, 0
    }

    dx := centroid.x - state.prev_centroid.x
    dy := centroid.y - state.prev_centroid.y
    state.prev_centroid = centroid

    // Scale to pan sensitivity
    return dx * camera_distance * 0.1, dy * camera_distance * 0.1
}
```

---

## Complete Event Loop Example

```odin
GestureManager :: struct {
    active_fingers: map[FingerID]Finger,
    prev_centroid: Maybe([2]f32),
    prev_distance: f32,
    primary_touch_device: TouchID,
}

handle_touch_events :: proc(app: ^AppState, event: ^sdl.Event) {
    gesture := &app.gesture_manager

    #partial switch event.type {
    case .FINGER_DOWN:
        touch_event := event.tfinger

        // Store finger in active fingers
        finger := Finger{
            id = touch_event.fingerID,
            x = touch_event.x,
            y = touch_event.y,
            pressure = touch_event.pressure,
        }
        gesture.active_fingers[touch_event.fingerID] = finger

        fmt.printf("Finger %d down at (%.2f, %.2f)\n", finger.id, finger.x, finger.y)

    case .FINGER_UP:
        touch_event := event.tfinger

        // Remove finger from active fingers
        delete_key(&gesture.active_fingers, touch_event.fingerID)

        // Reset gesture state when no fingers touching
        if len(gesture.active_fingers) == 0 {
            gesture.prev_centroid = nil
            gesture.prev_distance = 0
        }

        fmt.printf("Finger %d up\n", touch_event.fingerID)

    case .FINGER_MOTION:
        touch_event := event.tfinger

        // Update finger position
        if finger, ok := &gesture.active_fingers[touch_event.fingerID]; ok {
            finger.x = touch_event.x
            finger.y = touch_event.y
            finger.pressure = touch_event.pressure
        }

        // Detect gestures based on number of active fingers
        switch len(gesture.active_fingers) {
        case 2:
            // Check keyboard modifiers
            keyboard_state := sdl.GetKeyboardState(nil)
            shift_held := keyboard_state[sdl.SCANCODE_LSHIFT] || keyboard_state[sdl.SCANCODE_RSHIFT]

            if shift_held {
                // 2-finger + shift = Pan
                pan_x, pan_y := detect_pan_gesture(gesture, true)
                apply_camera_pan(&app.camera, pan_x, pan_y)
            } else {
                // 2-finger drag = Orbit
                azimuth_delta, elevation_delta := detect_orbit_gesture(gesture)
                app.camera.azimuth += azimuth_delta
                app.camera.elevation += elevation_delta
                camera_update_position(&app.camera)

                // 2-finger pinch = Zoom (simultaneously)
                zoom_factor := detect_pinch_gesture(gesture)
                app.camera.distance *= (2.0 - zoom_factor)  // Invert for natural feel
                camera_update_position(&app.camera)
            }
        }
    }
}
```

---

## Coordinate Conversion

Touch coordinates are normalized (0.0-1.0). Convert to screen/world space:

```odin
// Convert normalized touch coordinates to window pixels
touch_to_window :: proc(touch_x, touch_y: f32, window_width, window_height: i32) -> (x, y: f32) {
    return touch_x * f32(window_width), touch_y * f32(window_height)
}

// Convert normalized touch to NDC for 3D
touch_to_ndc :: proc(touch_x, touch_y: f32) -> (ndc_x, ndc_y: f32) {
    return touch_x * 2.0 - 1.0, 1.0 - touch_y * 2.0  // Y flipped
}
```

---

## Platform-Specific Notes

### macOS Trackpad

- Reports as `INDIRECT_RELATIVE` device type
- Coordinates are relative to window
- Supports up to 10+ simultaneous touches
- Excellent pressure sensitivity
- System gestures (3-finger swipe, etc.) may cancel touches

### System Gesture Conflicts

macOS has system-wide gestures that may interfere:
- **3-finger drag**: Mission Control
- **4-finger swipe**: Switch spaces
- **Pinch**: Zoom

**Solution**: Use 2-finger gestures to avoid conflicts with system gestures.

---

## Implementation Checklist for OhCAD

### Phase 1: Basic Touch Detection
- [ ] Initialize SDL3 with `INIT_VIDEO` flag
- [ ] Enumerate touch devices at startup
- [ ] Print touch device info to console
- [ ] Handle `FINGER_DOWN`, `FINGER_UP`, `FINGER_MOTION` events
- [ ] Track active fingers in `GestureManager`
- [ ] Print finger count and positions to console

### Phase 2: 2-Finger Orbit
- [ ] Detect when exactly 2 fingers are active
- [ ] Calculate centroid of 2 fingers
- [ ] Track centroid delta movement
- [ ] Apply delta to camera azimuth/elevation
- [ ] Add sensitivity slider for orbit speed
- [ ] Smooth orbit with damping/inertia

### Phase 3: 2-Finger Pinch Zoom
- [ ] Calculate distance between 2 fingers
- [ ] Track distance changes over time
- [ ] Map distance ratio to zoom factor
- [ ] Apply zoom to camera distance
- [ ] Clamp zoom to min/max camera distance
- [ ] Smooth zoom with exponential scaling

### Phase 4: 2-Finger Pan (with Shift)
- [ ] Detect Shift key state
- [ ] When Shift + 2 fingers, switch to pan mode
- [ ] Apply centroid delta to camera target position
- [ ] Convert touch delta to world-space pan
- [ ] Scale pan by camera distance (far = larger pan)
- [ ] Visual feedback for pan mode (cursor change?)

### Phase 5: Polish & Optimization
- [ ] Add gesture velocity/inertia (momentum scrolling)
- [ ] Exponential zoom scaling (natural feel)
- [ ] Gesture cancellation on system interrupts
- [ ] Configuration options (sensitivity, inertia, etc.)
- [ ] Support for Magic Mouse (if applicable)
- [ ] Fallback to mouse controls (backward compatibility)

---

## Advantages of SDL3 Multi-Touch

✅ **Cross-platform** - Works on macOS, Windows, Linux, iOS, Android
✅ **Low-level control** - Full access to finger data for custom gestures
✅ **Normalized coordinates** - Device-independent, easy to work with
✅ **Pressure data** - Can use for advanced interaction (e.g., pressure-based zoom)
✅ **No external dependencies** - Built into SDL3, no additional libraries
✅ **Active development** - SDL3 is actively maintained and improved

---

## Comparison: SDL3 vs GLFW

| Feature | SDL3 | GLFW |
|---------|------|------|
| Multi-touch events | ✅ Native | ❌ No support |
| Finger tracking | ✅ Yes (unique IDs) | ❌ No |
| Touch device detection | ✅ Yes | ❌ No |
| Pressure sensitivity | ✅ Yes | ❌ No |
| Normalized coordinates | ✅ Yes | N/A |
| Gesture recognition | ⚠️ Custom only | N/A |
| macOS trackpad | ✅ Excellent | ❌ Mouse only |
| Cross-platform | ✅ Excellent | ✅ Good |
| OpenGL integration | ✅ Native | ✅ Native |

**Verdict:** SDL3 is **significantly better** for multi-touch on macOS trackpad. GLFW has no multi-touch support at all.

---

## Recommended Architecture

```
GestureManager (tracks fingers, detects gestures)
    ↓
GestureEvent (orbit, zoom, pan)
    ↓
CameraController (applies gestures to camera)
    ↓
Camera (azimuth, elevation, distance, target)
```

### Modular Design

Keep gesture detection separate from camera logic:

```odin
// Gesture layer (SDL3-specific)
GestureManager :: struct {
    active_fingers: map[FingerID]Finger,
    state: GestureState,
}

GestureEvent :: union {
    OrbitGesture:  struct { dx, dy: f32 },
    ZoomGesture:   struct { factor: f32 },
    PanGesture:    struct { dx, dy: f32 },
}

detect_gestures :: proc(manager: ^GestureManager) -> Maybe(GestureEvent)

// Camera layer (platform-independent)
CameraController :: struct {
    camera: ^Camera,
    orbit_sensitivity: f32,
    zoom_sensitivity: f32,
    pan_sensitivity: f32,
}

apply_gesture :: proc(controller: ^CameraController, gesture: GestureEvent)
```

This separation allows:
- Easy testing of gesture detection
- Platform-independent camera logic
- Swappable input systems (touch, mouse, gamepad)

---

## Next Steps

1. ✅ **SDL3 is confirmed working** on your macOS system
2. 🔄 **Migrate OhCAD from GLFW to SDL3**
   - Create SDL3 window + OpenGL context
   - Port existing mouse/keyboard handlers
   - Test camera controls with mouse (backward compatibility)
3. 🔄 **Implement multi-touch gesture detection**
   - 2-finger orbit (drag)
   - 2-finger pinch (zoom)
   - 2-finger + shift (pan)
4. ⏳ **Polish and tune sensitivity**
   - Add configuration options
   - Implement inertia/momentum
   - Smooth gesture transitions

---

## References

- SDL3 Official Documentation: https://wiki.libsdl.org/SDL3/
- SDL3 Touch API: https://wiki.libsdl.org/SDL3/CategoryTouch
- SDL3 Events: https://wiki.libsdl.org/SDL3/CategoryEvents
- Odin SDL3 Bindings: `/Users/varomix/dev/ODIN_DEV/Odin/vendor/sdl3/`

---

**Conclusion:** SDL3 provides all the tools needed for professional multi-touch CAD navigation on macOS. The low-level finger tracking gives us full control to implement custom gestures that feel natural on trackpad. 🚀
