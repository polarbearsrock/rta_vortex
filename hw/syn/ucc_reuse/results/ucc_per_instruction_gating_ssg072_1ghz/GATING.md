# Pipeline gating and removed run detection

The existing opcode pipeline (`b32_gate_op_q1` through `q5`) and valid pipelines describe instructions already moving through the FU. A bank enable uses the valid/opcode at the appropriate preceding stage, including delayed SFU reservation slots. Its information is available before the receiving capture edge. Changing opcode on successive CUDA issues is supported subject to the existing dispatcher reservations. This ordinary pipeline metadata remains.

The removed mechanism was separate: three five-bit histories recognized exact homogeneous FMA32/MUL.LO/EX2 runs. Its suppression predicate was conceptually:

```text
match(t) = reset_released && !dpa_mode && valid && opcode == selected_opcode
skip(t)  = match(t) && match(t-1) && ... && match(t-5)
```

Thus the first five matching issues did not activate this extra suppression; the sixth and later matching cycles could suppress selected proved-constant captures. Other optimizations reused this predicate for isolation and extra capture gates. Removing only the original nineteen gates would leave those dependencies behind.

The current transform disables all fifteen history outputs, performs exact Boolean constant folding using the actual cell functions, bypasses redundant enabled ICGs and deletes dead control. It removes 28 ICGs in total, including the three history clocks. No arithmetic register is removed, moved, replaced by a constant or given a new latency. All remaining arithmetic next-state connections equal the old graph after these control substitutions. Full mixed gate replay independently checks architectural behavior; this is not advertised as whole-netlist formal equivalence.

The next optimization should distinguish a bank whose value is not consumed from a bank that must supply a known constant. The first may hold under its per-instruction enable. The second needs a correct constant read/bypass before its storage clock can be suppressed; retaining an arbitrary previous value is insufficient. Removing the run detector is complete. A new constant-bypass architecture has not been implemented in this snapshot.

The reset warmup counter and valid/opcode pipelines are retained for initialization and stage tracking. They are not fixed-opcode run detectors. The separate thirteen rounding sticky registers combine groups of four tail bits and are also unrelated.
