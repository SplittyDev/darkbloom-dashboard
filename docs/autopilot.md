# Autopilot (macOS)

Implementation and operational notes for maintainers.

Open **Darkbloom → Autopilot** and choose **Calibrate & Enable**. Calibration stops inference,
intersects `darkbloom models list --all --json` with `darkbloom models catalog --json`, then benchmarks
only downloaded, active text models with a valid template that meet catalog minimum RAM and fit
within the configured maximum memory threshold, and makes one fresh ranking pass before starting the best model set with repeated `--model` flags.
Catalog retrieval and eligibility checks finish before inference stops; a failed or empty catalog never
falls back to benchmarking arbitrary local models. Catalog membership is also refreshed before ranking.
The CLI also enforces its own hardware eligibility. Failed benchmarks are excluded and recorded.
Calibration uses three iterations per model and includes prefill in effective output throughput.
A private temporary copy of the provider config clears only `backend.enabled_models` for benchmarking;
the live config is preserved. No models are downloaded.

Every 60 seconds, Autopilot fetches fresh model pricing, demand and provider counts. API-facing model
IDs are joined to local artifact IDs using the catalog's explicit `hugging_face_id` mapping; model
quantizations are never inferred from names. Non-catalog downloads are omitted from Autopilot entirely,
including local calibration and model-specific activity history. Providers receive 100% of the listed
price. Completion revenue includes measured prefill/generation overhead; prompt/cache/request billing
is not included because the billable mix is unknown.

Workload is estimated for requests with the benchmark's prompt and completion token counts. The
public capacity feed reports instantaneous active/queued requests and aggregate rated decode TPS,
not measured per-model arrival rates or typical request lengths. We use equal provider shares and
Little's Law as an approximation:

- `fleet_decode_tps = aggregate_tps / routable_providers`
- `fleet_request_seconds = local_benchmark_seconds * local_decode_tps / fleet_decode_tps`
- `request_rate = (active_requests / fleet_request_seconds + queued_requests / 60) / providers`
- `offered_busy_fraction = request_rate * local_benchmark_seconds`
- `busy_fraction = min(1, offered_busy_fraction)`

`providers` includes this Mac when joining another model. Fleet service time retains the local
benchmark's ratio of prefill/overhead to decode time, while substituting the fleet's rated decode
speed. This is a modeling assumption, not a fleet service-time measurement. Faster local processing
therefore reduces busy time for the same estimated arrival rate. The queue contributes a backlog
spread over the next evaluation minute. All `/h` figures are that short-horizon forecast expressed
as an hourly run rate, recalculated each minute; a queued request is not a measured new arrival.
When fleet TPS is unavailable, active requests per provider give a rough occupancy fallback, visibly
labeled in the ranking. Real request lengths, batching, warm-provider routing priority, and rejected
traffic are unavailable, so displayed request counts explicitly refer to benchmark-sized requests.
Do not infer measured requests/hour or actual GPU utilization from these estimates.

Power assumptions are editable while paused. **Active Serving Power (Watts)** retains the previous
`servingWatts` value. **Idle Power (Watts)** defaults to zero for existing saved state; zero excludes
baseline machine consumption until an idle-power assumption is supplied. Active power is the total
power while serving, not an increment on top of idle power:

`average_watts = idle_watts + max(0, active_watts - idle_watts) * busy_fraction`

`electricity_per_hour = electricity_usd_per_kwh * average_watts / 1000`

For example, 100 W active / 0 W idle at 20% estimated busy time averages 20 W. At $0.11/kWh,
electricity is $0.0022/hour, rather than $0.011/hour. With 10 W idle it averages 28 W and costs
$0.00308/hour. One shared active-power assumption applies to every model; model-specific power
and extra residency overhead are not measured. These are assumptions, not power-meter readings or
measured earnings.

A model set shares one sequential engine. Sum the models' offered busy fractions, cap total busy time
at 100%, and scale each model's work proportionally if the set is oversubscribed. Apply completion
revenue to that allocated busy time, then subtract the machine's electricity once. The tab shows the
best set's busy time, handled request rate, average power, revenue, electricity cost and net
estimate together. Individual
ranking rows are explicitly standalone estimates and cannot be added together.

Autopilot selects up to three models in descending earning-rank order, skipping any model whose
estimated memory does not fit the remaining budget. **Maximum Loaded Model Count** is editable from
1 to 3 (default 3); **Maximum Memory Threshold (GB)** is editable from 1 GB to this machine's unified
memory (default `machine_memory_gb * 0.5`). Both settings are saved and editable while paused, once
any pending model change has been reconciled. Existing saved calibrations use these defaults.
The budget sums `estimated_memory_gb` across the entire selection, rather than applying the threshold
to each model separately. Model weights are only an estimate: KV caching and other allocations add
RAM usage. Catalog minimum RAM and valid-template checks still apply. Increasing the threshold may
require recalibration to measure newly eligible models. If no calibrated model fits, Autopilot reports
the problem and retries without selecting an oversized model. If an existing selection exceeds
the budget and no model fits for three stable samples, inference is gracefully stopped; an uncertain
stop stays pending until the daemon confirms it, and never escalates into a forced model start.
The first best-fitting model remains available as a startup fallback. Additional models are loaded
only when they improve the combined machine estimate; a model does not need to cover the machine's
idle cost by itself. A lower-value model can reduce the combined estimate on an already saturated
machine, so spare memory alone does not guarantee that all three slots are filled.

A normal change requires the same model set across three consecutive samples and a 1:2:3
recency-weighted ranking of offered workload and full-busy revenue potential. Adding models requires
a positive combined net estimate and a combined improvement. Replacing or removing models requires
the entire proposed set to beat the current set by the configured margin (10% by default) and
$0.001/hour, with an improvement in every sample. Missing current-model observations and long
sampling gaps prevent profitability-based changes. Reducing a selection to meet the count
or memory limits takes precedence over profitability, after the same three-sample stability gate.
Model order does not affect set confirmation. Additional warm models offer opportunities during gaps
in other models' demand, within the shared sequential work estimate. The switch command is `darkbloom switch --model <id> [--model <id> ...]`, retaining
its default 600-second drain timeout. Autopilot warms missing models in the confirmed selection
sequentially using self-routed, one-token requests, and retries missing residency each evaluation.
Warmup failures remain visible and retry automatically. Other automatic local warmups remain suspended
so they cannot load models outside Autopilot's budget. The tab distinguishes selected models from
loaded/warm models and shows the recommended set's estimated memory.
Network/catalog/snapshot errors retry automatically. Confirmation uses the daemon's advertised
selection, since loaded slots can lag behind a switch or be empty until the first request.
Unconfirmed changes stay enabled and are checked every 60 seconds without issuing overlapping
commands. A pending drain retries the same selection after at least 60 seconds. If that switch
reports `A provider model switch is already in progress`, or two switch attempts time out,
Autopilot replaces the provider using `darkbloom start --model <id> [--model <id> ...] --timeout 0 --force`.
This cancels unfinished work and restarts with the entire intended selection; plain `restart` would retain
the old selection. An otherwise unconfirmed start or switch also escalates after 30 minutes. Forced recovery
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
Pending starts, switches and budget stops are saved across pauses and relaunches and reconciled before any new calibration.
Normal app quit waits for this cleanup. Local automatic warmups are suspended while Autopilot owns
the machine, and local dashboard restarts pause Autopilot first.

CLI contracts: [provider CLI reference](https://github.com/Layr-Labs/d-inference/blob/master/docs/provider/cli-reference.md)
and [standard benchmark report](https://github.com/Layr-Labs/d-inference/blob/master/provider-swift/Sources/ProviderBenchmark/ModelBenchmark.swift).
