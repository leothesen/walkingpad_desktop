# Design System — WalkingPad Desktop

## Visual Identity: Liquid Glass

The "Liquid Glass" design system is inspired by macOS 26's emphasis on transparency, depth, and fluid motion. It focuses on being unobtrusive, ensuring the user stays in flow while providing critical information at a glance.

### Key Principles
1. **Unobtrusiveness:** Information should be available but not demanding of attention.
2. **Depth & Texture:** Use of glass-like materials (ultra-thin, frosted) to provide depth and context.
3. **Motion:** Fluid transitions that reflect the physical movement of walking.
4. **Frictionless Control:** Minimizing clicks to achieve common tasks.

---

### 1. Palette

| Color | Value | Usage |
|-------|-------|-------|
| **Accent (Blue)** | `#0A84FF` | Primary action color, icons for metrics. |
| **Glass Background** | Translucent Frosted | Used for the menu bar popover and floating stats overlay. |
| **Primary Text** | `#FFFFFF` / `#000000` | Main content (adaptive to dark/light mode). |
| **Secondary Text** | `#8E8E93` | Labels, captions, tertiary info. |
| **Success (Green)** | `#30D158` | Positive trends, connected states. |
| **Warning (Orange)** | `#FF9F0A` | Charging, low signal. |
| **Critical (Red)** | `#FF453A` | Disconnected, emergency stop. |

---

### 2. Typography

We use the system font with specific styles for a modern, tech-focused look:

- **Primary Numbers (Hero):** `.system(size: 42, weight: .bold, design: .rounded).monospacedDigit()`
- **Secondary Numbers:** `.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()`
- **Labels:** `.system(size: 11, weight: .medium, design: .rounded)`
- **Log/Debug:** `.system(size: 11, design: .monospaced)`

---

### 3. Components

#### 3.1. Stats Card (Liquid Glass)
A frosted glass card with a subtle border and rounded corners.
- **Background:** `.ultraThinMaterial`
- **Corner Radius:** `14pt`
- **Padding:** `12pt`
- **Border:** `0.5pt white / 10% opacity` (for dark mode)

#### 3.2. Metric Card (Compact)
Small, focused card for individual stats (Steps, Time, Avg Speed).
- **Icon:** Top-aligned SF Symbol in Accent color.
- **Value:** Semibold monospaced digits.
- **Label:** Caption 2 gray text.

#### 3.3. Trend Chart
SwiftUI Chart using a smooth line or bar with a gradient fill.
- **Gradient:** From `Accent` to `Accent / 10% opacity`.
- **Interaction:** Hover tooltip showing detailed data.

#### 3.4. Consistency Streak
A compact grid or line representing daily activity across the selected time range.
- **Inactive Day:** Low-opacity circle.
- **Active Day:** Filled circle with a subtle glow.

---

### 4. Interactions & Motion

- **Fades:** Use ease-in-out fades for window appearances.
- **Slide & Fade:** Used for tooltip transitions in the trend chart.
- **Scale:** Subtle scale-up on hover for interactive elements (MetricCards).
- **Haptics:** (Future) Use macOS haptics for speed adjustment clicks.

---

### 5. High-Priority Features

- **Global Hotkeys:** Cmd + Opt + Up/Down for speed control.
- **Bypass Novice Guide:** A "Pro Mode" toggle in settings to skip device tutorials.
- **Stats Overlay:** A non-interactive, always-on-top overlay with adjustable opacity.
