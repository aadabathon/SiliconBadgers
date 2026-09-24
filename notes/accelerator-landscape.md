# Accelerator landscape → Silicon Badgers (meeting prep)

Source: the reading list in `Hardware Solutions - Google Docs (2).pdf` (links only, no prose) plus the project's Technical Report v2.
**Caveat:** these notes are from general knowledge of each vendor's public architecture, not from reading every linked paper. Numbers marked (verify) are ones to check against the linked source before you repeat them in the meeting. Newer items (Groq 3 LPX, Maia 200, Taalas) may postdate what I know well.

---

## 0. The one idea that organizes everything: roofline

Attainable perf = min(peak compute, memory BW x arithmetic intensity).
Arithmetic intensity = MACs per byte moved.

- **Prefill** (many tokens at once): matrix x matrix, high reuse, compute-bound.
- **Decode** (one token at a time, batch 1): matrix x vector, every weight is read once and used once. INT4 weights give about 2 MAC/byte. **Memory-bound.**

Our report's numbers: 1.14 GB moved per token at 8K context, so 20 tok/s needs about 23 GB/s sustained. That is only about 280 MAC lanes at 250 MHz. **The design problem for decode is bandwidth, not FLOPs.** Nearly every chip below is a different answer to "where do the weights live and how fast can I stream them?"

## 1. The industry in one table

| Vendor | Core idea | Where weights live | Good at | Lesson for us |
|---|---|---|---|---|
| **NVIDIA GPU** (Blackwell) | Thousands of programmable SIMT cores plus tensor cores, HBM | HBM (off-chip, stacked) | Everything; flexible | The baseline. Wins on software (CUDA), not efficiency. Low-bit formats (FP4/NVFP4) with block scales are now standard |
| **Google TPU** | Big **systolic array** (128x128 in early gens), software-managed on-chip memory, no caches, compiler (XLA) schedules everything | HBM, plus large on-chip buffers | Dense matmul, training and inference at pod scale | Systolic array plus compiler-scheduled dataflow is the canonical model for our matrix engine. Ironwood is inference-focused |
| **d-Matrix Corsair** | **Digital in-memory compute**: MACs sit inside SRAM arrays; chiplets; 3D-stacked DRAM planned | On-chip SRAM (fast) plus DRAM tier | Low-latency, small-batch decode | Attacks the decode bandwidth wall by moving compute to data |
| **Groq LPU** (now tied to NVIDIA per the doc) | **Deterministic, statically scheduled** dataflow; huge on-chip SRAM, no HBM; compiler knows every cycle | Entirely on-chip SRAM, sharded over many chips | Very low, predictable latency | Static scheduling makes performance predictable, but capacity is tiny per chip so a model spans many chips |
| **Etched Sohu** | **Transformer-only ASIC**; drops generality for attention/MLP efficiency | HBM | Transformer throughput | Specializing on one model family is a real strategy. Ours (Qwen3.5 hybrid with DeltaNet) would break a pure-attention ASIC |
| **AMD Instinct MI300** | GPU plus CPU chiplets, big HBM, unified memory, ROCm | HBM3 | Capacity and bandwidth per dollar | Chiplet plus memory partitioning (NUMA-like) is the cost of huge HBM |
| **Qualcomm Hexagon NPU** | Scalar + vector + tensor units on a phone SoC, tightly coupled, low power | Shared LPDDR | Edge, perf/watt | Closest to a small heterogeneous system: CPU-class control plus tensor engine. Power and LPDDR bandwidth are the limit |
| **MatX** | Startup; LLM-specialized chip mixing large SRAM and HBM | SRAM plus HBM | Throughput and latency for LLMs | Same tradeoff space; watch their blogs |
| **Tenstorrent** (Wormhole/Blackhole) | Grid of **Tensix cores**, each with its own RISC-V cores, SRAM, and NoC; **open software stack**, RISC-V based, chiplet-friendly | GDDR6 plus per-core SRAM | Scalable, programmable, open | **Most relevant to us.** Uses small RISC-V cores to *control* dataflow engines, which is the architecture in our report |
| **Microsoft Maia** | Custom Azure chip; microscaling (MX) formats, big SRAM plus HBM, Ethernet scale-out | HBM plus on-chip SRAM | Azure OpenAI inference | Direct evidence the industry is moving to MX/block-scaled low-bit formats, which is our INT4 group-64 decision |
| **Meta MTIA** | Grid of PEs plus RISC-V cores plus on-chip SRAM, tuned for recommendation then LLM | LPDDR/HBM plus SRAM | Cost-efficient inference | Another example of RISC-V as the control fabric around a matrix engine |
| **AWS Trainium/Inferentia** | **NeuronCores**: tensor, vector, scalar, GPSIMD engines, software-managed SRAM | HBM | Training (Trn) and inference (Inf) | AWS also owns our F2 platform; the engine split (matrix / vector / scalar) mirrors our compute plan |
| **Taalas** | **Model hardwired into silicon**, weights as physical structure, no HBM | On die | Extreme tokens/s per watt for one fixed model | Extreme end of "specialize". Zero flexibility. Quoted 17k tok/s figures are marketing (verify) |
| **Cerebras** | **Wafer-scale engine**: one giant die, tens of GB of on-chip SRAM | On-wafer SRAM (or MemoryX streaming) | Very fast inference and training | Same "put weights in SRAM" thesis as Groq, taken to the extreme |

## 2. Five design axes (use these in conversation)

1. **Where do weights live?** HBM (GPU/TPU/MI300/Trainium) vs. on-chip SRAM (Groq, Cerebras, d-Matrix) vs. baked into the chip (Taalas). *Us: HBM/DDR on F2.*
2. **How is the matmul done?** Systolic array (TPU), SIMT tensor cores (NVIDIA), in-memory compute (d-Matrix), grid of small cores (Tenstorrent). *Us: matrix array plus vector/reduction engines, and a separate recurrent-state engine.*
3. **Who schedules?** Hardware (GPU warps, caches) vs. compiler (TPU, Groq, Trainium). Compiler-scheduled means predictable and simpler hardware, but harder software. *Us: RISC-V firmware plus a command queue, in between.*
4. **What number format?** BF16, then FP8, then FP4/INT4 with **block scales** (MX, NVFP4). *Us: INT4, group size 64, BF16 scales = 4.25 bits/weight.*
5. **How general?** GPU (everything), TPU/NPU (tensors), Sohu (transformers only), Taalas (one model). *Us: one model, but a hybrid with DeltaNet, so we must handle attention plus recurrence.*

## 3. What is different about *our* model

Every chip above was designed mainly for attention plus MLP. **Qwen3.5-2B is hybrid:** 18 of 24 layers are Gated DeltaNet (a linear-attention/recurrent layer with fixed-size state) and 6 are full attention.

- DeltaNet needs a **state engine** (per-head 128x128 matrix update per token) that GPUs handle with custom kernels and most ASICs do not natively support.
- The CPU profiling showed the depthwise convolution fallback dominating time (81%). On GPUs this is fused into custom kernels (the report notes fused DeltaNet kernels were absent on the CPU run).
- The state does not grow with context, so long-context memory pressure is smaller than in pure-attention models. KV cache exists only in 6 layers.
- **A pure transformer ASIC (Sohu) or a compiler that only knows attention would not run this model out of the box.** That is our angle: a programmable-enough design that covers the hybrid.

## 4. RISC-V primer (what you need to say credibly)

- **RISC-V is an ISA (an instruction contract), not a chip.** Cores are separate IP (Rocket, BOOM, CVA6, VexRiscv, PicoRV32, and others). Open, license-free, extensible.
- **RV32I** is the 32-bit base integer set: load/store, add, branch, no multiply until the M extension. Extensions are letters: M (multiply), A (atomics), F/D (float), C (compressed), V (vector).
- **Why RISC-V in accelerators?** (a) no license fee, (b) you can add custom instructions or, as in our plan, none at all, (c) small cores are cheap control processors. Tenstorrent, Meta MTIA, and many others use it this way.
- **Our design choice:** the RISC-V core is an **unmodified control processor**. It runs C firmware, and talks to the accelerator via **MMIO** (ordinary loads/stores to special addresses) plus a **doorbell**. The accelerator decodes its own command format, not RISC-V instructions. No custom opcodes, no vector extension required.
- **Gotchas the report calls out:** FENCE orders memory operations but does **not** flush caches; a 64-bit DMA address must be written as two 32-bit halves and published only when both are done; a timeout does not mean DMA stopped.
- **Likely question: "why not just a state machine instead of a CPU?"** Answer: firmware can schedule 24 heterogeneous layers, manage per-request state, and change without re-synthesizing the FPGA.

## 5. LLM architecture cheat sheet (for our model)

- **Token flow:** tokenize, embedding lookup (248,320 x 2048), 24 layers, final norm, output head (logits over 248,320), sample.
- **Each layer:** norm, *mixer* (attention or DeltaNet), residual, norm, MLP, residual.
- **MLP (SwiGLU):** `down( SiLU(gate(x)) * up(x) )`. Three matmuls (2048 to 6144 twice, then 6144 to 2048). 48% of dense MACs.
- **Full attention:** Q/K/V projections, Q/K norm, partial RoPE (64 of 256 dims), softmax(QK^T/sqrt(d))V, sigmoid output gate. **GQA:** 8 query heads share 2 KV heads (4x less KV traffic). **Online softmax** (FlashAttention idea) avoids storing the T x T score matrix.
- **DeltaNet (recurrent):** small causal conv, then a per-head state S (128x128) updated each token: decay, predict, correct, update. State is fixed-size, so no KV growth.
- **Prefill vs decode:** prefill = whole prompt in parallel (compute-bound); decode = one token per step (memory-bound). Benchmark and schedule them separately.
- **Three state stores per request:** KV cache (grows, 6 layers), recurrent state (18 MiB FP32 fixed), conv history (about 0.84 MiB).
- **Quantization vocabulary:** weight-only INT4 (dequantize to BF16 at use), group size = weights sharing one scale, AWQ/GPTQ = ways to pick good quantized weights, MX/NVFP4 = block-scaled FP4 formats.
- **Output head is 27% of MACs** but only about 2% of CPU time. Do not size hardware from CPU profiles alone.

## 6. How this maps to our project decisions

| Our open decision (report p.27) | What industry suggests |
|---|---|
| **Precision: INT4 vs FP4** | MX/NVFP4 (Maia, NVIDIA) shows block-scaled FP4 is mainstream. INT4 g64 is a fine baseline. Compare both on whole-model quality before freezing |
| **Memory: bank mapping, tile DMA** | Everyone fights the same wall. HBM designs (TPU, Trainium, MI300) stripe across channels; SRAM-centric designs (Groq, Cerebras) avoid it but need many chips. On F2, using all 32 HBM ports in parallel matters |
| **Scheduling: firmware vs compiler** | Tenstorrent (RISC-V control plus command queues) is the closest analog. TPU/Groq push scheduling into the compiler. Our hybrid is reasonable |
| **Systolic array vs other matmul** | Systolic is proven and simple, and the TPU reference is the one to read first. But batch-1 decode underuses a big array, so plan a vector-friendly decode path |
| **Tapeout scope** | Small block (MAC tile, state engine) is realistic and echoes what startups validate first. Full model needs DRAM PHY plus package, a much bigger scope |

## 7. Reading order (if you only have an hour)

1. Roofline model (Williams et al.), 10 min. Gives you the vocabulary.
2. Google TPU v1 blog/paper, the "in-depth look" link, for systolic arrays.
3. Tenstorrent Wormhole basics, for RISC-V plus dataflow.
4. Groq LPU ISCA'20 paper (TSP), for static scheduling.
5. Maia MX-formats piece, for the quantization direction.

## 8. Questions worth raising tonight

1. Are we sizing the matrix array for prefill or decode? They want different shapes.
2. Who owns the DeltaNet state engine? It is not in any off-the-shelf design (`rtl-compute`?).
3. Which RISC-V core: pick one now (VexRiscv/CVA6/Rocket-class) or defer? It affects the `soc` repo.
4. Do we commit to INT4 g64 or run the FP4 comparison first?
5. FPGA-only goal, or a block-level tapeout as well? (Budget anchor in the report: chipIgnite about $14,950 base.)
