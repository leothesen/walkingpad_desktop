# Challenge log

Framing challenges raised against work in this repo, and what came of them.

---

## 2026-09-07 — "create more durable logs" after the mid-session crash

**Test that fired:** MECHANISM. The ask named a mechanism ("find the logs, or create
more durable logs for future instances") rather than the outcome.

**Restated outcome:** a walk that happened should end up on Strava, and when the app
dies it should be possible to find out why.

**The case that logging is the wrong problem:** durable logs would have told us
exactly what killed the app on 2026-09-07 and would still have lost the 2.62 km. The
loss was not a logging failure. `Workout.update()` accumulates the daily totals on
every BLE update but only appends to `todaySessions` when a session *ends*, and both
Notion and Strava are fed from sessions. So any death mid-walk — crash, force quit,
power cut, OS restart — keeps the distance in the day's total and drops the session
that carried it. Fixing only the crash narrows one entry into that hole while leaving
the hole; fixing only the logging makes the hole legible without closing it. The
problem worth solving is that an in-flight session has no representation on disk.

**Outcome:** did both, in that order of importance. `SessionCheckpoint` mirrors the
running session to disk on every update and is recovered at launch, which closes the
data loss for every cause of death rather than for one of them. The crash itself is
fixed (`WalkingPadService` indexed a payload before checking its length). Durable
logging shipped as asked, and is what makes the *next* unexplained death diagnosable.
