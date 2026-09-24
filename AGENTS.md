# Silicon Badgers — Agent Guide

## Project mission

Silicon Badgers is a University of Wisconsin–Madison student club project to design and build an AI accelerator for **Qwen3.5-2B**. The goal is a correct, measurable, reproducible hardware/software system—not merely high benchmark numbers.

Treat model behavior, numerical accuracy, hardware resource use, latency, throughput, power, and developer usability as first-class constraints.

## Working principles

- Make small, reviewable changes that preserve a runnable build and test path.
- Prefer clear, parameterized designs over one-off optimizations.
- Do not silently change tensor layouts, dtypes, quantization schemes, numerical tolerances, clock/reset semantics, or external interfaces.
- Document assumptions at system boundaries: host ↔ runtime, runtime ↔ driver, driver ↔ hardware, and module ↔ module.
- Optimize only after establishing a baseline and preserving a correctness check.
- Keep student contributors unblocked: explain non-obvious hardware, compiler, and ML decisions in comments or documentation.

## Before making changes

1. Read the nearest `AGENTS.md` and any README or design document relevant to the affected component.
2. Inspect existing build, formatting, simulation, lint, and test commands; use the repository’s established commands rather than inventing replacements.
3. Check the working tree before editing. Preserve unrelated work.
4. Identify the contract affected by the change: shapes, layout, dtype, quantization, protocol, timing, address map, or CLI/API behavior.

## Model and numerical correctness

- Record tensor shapes, layout/order, dtype, scaling factors, rounding mode, saturation behavior, and zero points wherever tensors cross a boundary.
- Use deterministic test vectors and retain a software reference path for every supported operation.
- Compare accelerator output against the reference with explicit tolerances. Report maximum/mean error and mismatch rate when useful; do not call a result “correct” without a defined criterion.
- Include edge cases: zeros, extrema, odd dimensions/tails, sequence-length boundaries, reset/restart, backpressure, and invalid or unsupported inputs.
- Any Qwen-specific preprocessing, tokenizer, KV-cache, RoPE, attention, normalization, activation, or sampling assumption must be documented and tested against the chosen reference implementation.
- Do not download, commit, or redistribute model weights, tokenizers, generated outputs, secrets, or large build artifacts unless the repository explicitly supports doing so.

## Hardware and RTL

- Keep clock and reset behavior explicit and consistent. Avoid implicit latches, undeclared widths, X-dependent behavior, and clock-domain crossings without a documented synchronization strategy.
- Parameterize dimensions and widths where practical; assert legal parameter values and interface invariants.
- For every interface, specify ownership and timing for `valid`, `ready`, request/response, IDs, ordering, byte enables, and error behavior.
- Add or update simulation coverage for functional changes. Assertions are encouraged for protocol, bounds, FIFO, and state-machine invariants.
- Treat synthesis and timing reports as part of validation. Do not claim an optimization unless the target clock, resource metrics, and test configuration are stated.
- Avoid vendor-specific primitives in reusable logic unless isolated behind a documented wrapper.

## Software, runtime, and tooling

- Keep host/runtime behavior compatible with documented hardware contracts and error handling.
- Validate all external inputs, buffer sizes, tensor metadata, and device responses. Fail clearly rather than producing silently incorrect output.
- Keep dependencies minimal and pinned according to existing project conventions.
- Never hard-code a local absolute path, machine-specific tool installation, board serial number, credential, or account-specific setting.
- Make benchmarks reproducible: record commit, model/configuration, precision, batch and sequence lengths, warmup/measurement policy, platform, clock, and the relevant latency/throughput definition.

## Testing and validation

Run the narrowest relevant checks while developing, then the project’s standard verification suite before handing off. At minimum, when applicable:

- format/lint the files changed;
- run unit tests for software changes;
- run RTL lint and focused simulation for hardware changes;
- run integration/reference comparisons for changed model operators or data paths;
- check synthesis/timing or resource estimates when RTL or constraints change.

If an expected check cannot be run, state exactly what was skipped and why. Do not represent unrun checks as passing.

## Documentation and handoff

- Update documentation when interfaces, supported configurations, setup steps, metrics, or architectural decisions change.
- Keep commit messages and pull requests scoped and descriptive. Include the motivation, affected contracts, validation run, and measured impact where relevant.
- Flag decisions that need club consensus, especially target FPGA/ASIC assumptions, model revision, quantization strategy, memory architecture, performance targets, or changes to shared interfaces.
- End work with a concise summary of changed files, validation performed, and known limitations or follow-up work.

## Safety and repository hygiene

- Do not overwrite or revert other contributors’ work without explicit approval.
- Do not commit generated simulation databases, waveforms, bitstreams, model checkpoints, datasets, large binaries, secrets, or machine-local configuration unless specifically intended and documented.
- Prefer portable scripts and relative paths. Keep generated artifacts ignored according to repository conventions.
