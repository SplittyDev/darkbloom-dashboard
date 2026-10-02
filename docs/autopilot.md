# Autopilot (macOS)

Implementation and operational notes for maintainers.

Open **Darkbloom → Autopilot** and choose **Calibrate & Enable**. Calibration stops inference,
intersects `darkbloom models list --all --json` with `darkbloom models catalog --json`, then benchmarks
only downloaded, active text models with a valid template that meet catalog minimum RAM and fit
within 80% of unified memory,
and makes one fresh ranking pass before running `darkbloom start --model <best-model>`.
Catalog retrieval and eligibility checks finish before inference stops; a failed or empty catalog never
falls back to benchmarking arbitrary local models. Catalog membership is also refreshed before ranking.
The CLI also enforces its own hardware eligibility. Failed benchmarks are excluded and recorded.
Calibration uses three iterations per model and includes prefill in effective output throughput.
A private temporary copy of the provider config clears only `backend.enabled_models` for benchmarking;
the live config is preserved. No models are downloaded.

Every 60 seconds, Autopilot fetches fresh model pricing, demand and provider counts. API-facing model
IDs are joined to local artifact IDs using the catalog’s explicit `hugging_face_id` mapping; model
quantizations are never inferred from names. Non-catalog downloads are omitted from Autopilot entirely,
including local calibration and model-specific activity history. It estimates
completion revenue per hour from measured output tokens per total second and estimated utilization:
`min(1, (active + queued requests) / providers)`. Joining a different model adds this Mac to the
provider count. Providers receive 100% of the listed price. Electricity assumptions are editable while paused. These are
comparative estimates, not measured earnings: routing priority, request lengths, batching, prompt/cache
billing, model-specific power draw and actual provider payouts are not available in these feeds.

A normal switch requires the same winner across three consecutive samples, a 1:2:3 recency-weighted
average, a positive net estimate, and an improvement exceeding both the configured margin (10% by
default) and $0.001/hour. Unknown current-model profitability, missing observations and long sampling
gaps prevent automatic switches. Multiple reported models do not block switching; Autopilot compares
against the current model (or the best measured selection if no current model is reported) and switches
to a single winner. The switch command is
`darkbloom switch --model <id>` on the installed CLI, retaining its default 600-second drain timeout.
Network/catalog/snapshot errors retry automatically. Confirmation uses the daemon's advertised
selection, since loaded slots can lag behind a switch or be empty until the first request.
Unconfirmed changes stay enabled and are checked every 60 seconds without issuing overlapping
commands. A pending drain retries the same selection after at least 60 seconds. If that switch
reports `A provider model switch is already in progress`, or two switch attempts time out,
Autopilot replaces the provider using `darkbloom start --model <intended-model> --timeout 0 --force`.
This cancels unfinished work and restarts with the intended selection; plain `restart` would retain
the old selection. An otherwise unconfirmed change also escalates after 30 minutes. Forced recovery
is persisted before execution, requires serving-state confirmation (and a changed process identity
when the old identity is known), and retries at most once every three minutes if unsuccessful.
Pausing prevents further recovery commands. If the daemon settles on a different selection before
escalation, Autopilot starts a fresh three-sample
window before trying another change. A confirmed stopped daemon is started using current rankings.

Calibration, assumptions, recovery information and the latest 500 activity entries are stored in
`~/Library/Application Support/DarkbloomDashboard/autopilot.json`. CLI version changes show a
recalibration recommendation while evaluations, switches and recovery continue using the existing
benchmarks, including after enabling again. **Recalibrate & Enable** refreshes those measurements
and clears the warning. Machine or memory changes trigger recalibration on enable;
newly downloaded or changed-size models also require **Recalibrate & Enable**.
The sidebar always shows whether Autopilot is **On** or **Off**, with a warning indicator when
attention is needed; hover over the row for its detailed status.
Autopilot runs while Dashboard is open and opens paused after relaunch. Pausing lets an in-flight
command finish. A cancelled or unsuccessful calibration restores the prior selection when the outcome
is known; an uncertain calibration stop requires attention instead of repeating destructive commands.
Pending starts/switches are saved across pauses and relaunches and reconciled before any new calibration.
Normal app quit waits for this cleanup. Local automatic warmups are suspended while Autopilot owns
the machine, and local dashboard restarts pause Autopilot first.

CLI contracts: [provider CLI reference](https://github.com/Layr-Labs/d-inference/blob/master/docs/provider/cli-reference.md)
and [standard benchmark report](https://github.com/Layr-Labs/d-inference/blob/master/provider-swift/Sources/ProviderBenchmark/ModelBenchmark.swift).
