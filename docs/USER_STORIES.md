# User Stories — WalkingPad Desktop

## Epic 1: Unobtrusive Control & Monitoring

**US01: Menu Bar Monitoring**
As a user, I want to see my current session distance and time in the macOS menu bar so that I can stay informed without switching windows.
- *Status:* Implemented
- *Priority:* High

**US02: Stats Overlay**
As a user, I want a floating, semi-transparent overlay showing my speed, distance, and time so that I can monitor my progress while working in full-screen apps.
- *Status:* Planned
- *Priority:* High

**US03: Global Hotkeys**
As a power user, I want to change the treadmill speed using keyboard shortcuts (e.g., Cmd + Opt + Up/Down) from any application so that I don't have to interrupt my flow.
- *Status:* Planned
- *Priority:* High

## Epic 2: Insightful Analytics

**US04: Dashboard Overview**
As a user, I want a central dashboard to see my weekly and monthly walking trends so that I can track my consistency over time.
- *Status:* Implemented (StatsWindowView)
- *Priority:* Medium

**US05: Activity Heatmap**
As a user, I want to see a heatmap of my walking activity across the week so that I can identify my most productive times.
- *Status:* Implemented
- *Priority:* Medium

**US06: Session Breakdowns**
As a user, I want to see a list of all my walking sessions with start/end times and totals so that I can review my daily activity in detail.
- *Status:* Implemented (ActivityLogTabView)
- *Priority:* Low

## Epic 3: Frictionless Integration

**US07: Notion Sync**
As a user, I want my sessions to automatically sync to Notion so that I have a permanent record of my workouts.
- *Status:* Implemented
- *Priority:* High

**US08: Strava Posting**
As a user, I want to post my daily walking total to Strava with one click so that I can share my progress with my fitness community.
- *Status:* Implemented
- *Priority:* Medium

**US09: Automatic Reconnection**
As a user, I want the app to automatically reconnect to my WalkingPad when it wakes from sleep or comes into range so that I don't have to manually connect every time.
- *Status:* Implemented (BluetoothDiscoveryService)
- *Priority:* High

**US10: Home Assistant / MQTT**
As a smart home enthusiast, I want my treadmill state to be published to MQTT so that I can trigger automations (e.g., turning on a fan when I start walking).
- *Status:* Implemented
- *Priority:* Low

## Epic 4: User Onboarding & Guidance

**US11: Bypass Novice Guide**
As a power user or returning user, I want to skip the mandatory "novice" speed limit tutorial (often 1-3km limit for first 1km) so that I can walk at my desired speed immediately on a new device.
- *Status:* Planned
- *Priority:* High
- *Note:* This was highlighted by the CEO as a key game-changer for friction removal.
