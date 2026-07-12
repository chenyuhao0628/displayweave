# Quick recovery checklist

Status: pending re-run against the current performance-control build.

| Scenario | Required result | Current-build evidence |
| --- | --- | --- |
| USB unplug/replug | Recovers with status; no stale session or retry loop | Pending |
| ADB server restart | Bounded retry and recovery | Pending |
| Authorization revoke/reallow | Clear status and recovery | Pending |
| Receiver background/foreground | Rendering resumes without persistent black screen | Pending |
| Lock/unlock | Rendering resumes | Pending |
| WiFi interruption | Bounded recovery | Pending |
| Auto WiFi fallback / USB return | Same install only; old session ends first | Pending |
| HEVC to H.264 fallback | New config and immediate keyframe | Code covered; physical pending |
| Manual reconnect | One replacement session; no leaked forward | Pending |

These are short recovery checks, not endurance or long-term stability evidence.
