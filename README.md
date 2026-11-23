# HSF1 Pipelined Floating Point Adder (FPADD-PIPE)

HSF1 is a pipelined parameterized ANY-precision floating point adder designed for high-performance computing applications. 
It can be configured to support various floating point formats by adjusting the parameters for exponent and mantissa widths.

This IP is pipelined to achieve high throughput, making it suitable for applications requiring fast floating point arithmetic operations.

## Updates in Nov. 23, 2026

Version 0.2 includes the following fixes.

- Fixed the sign of zero when adding signed zeros or when two nonzero operands cancel exactly.
- Fixed overflow handling for all four rounding modes. The adder now returns infinity or the largest finite value with the correct sign and sets the result flags accordingly.
- Fixed out-of-range bit selections in the barrel shifters and ALU for small exponent and mantissa widths.

We've updated the reference model and enabled a new regression flow. A single command now tests every exponent and mantissa width pair (`E`, `M`) in the regression matrix in all four rounding modes, giving us broader test coverage.

*Note: We have now introduced AI agent tools to assist with bug analysis, test script development, and documentation generation.  
All modifications and suggestions produced by AI are subject to our manual review and approval. We remain actively involved throughout the process, ensuring that we fully understand, verify, and maintain control over all AI-generated content and changes.*

## Features
- Fully pipelined architecture w/ II = 1
- Parameterized exponent and mantissa widths
- Parameterized rounding modes, supporting multiple IEEE 754 rounding modes, including:
    - Round to Nearest Even
    - Round towards Zero
    - Round towards Positive Infinity
    - Round towards Negative Infinity
- Exception outputs: NaN and Infinity detection

## Getting Started
### FuseSoC and Cocotb Requirements
This IP organized with [FuseSoC](https://github.com/olofk/fusesoc), a package manager and build system for HDL code.
To build and simulate the IP core, you need to have following requirements installed:
- fusesoc
- numpy
- pytest
- cocotb

You can simply use `uv` or other Python virtual environment tools to create a new environment,
then install the requirements with `pip`:
```
uv pip install fusesoc numpy pytest cocotb
```
All required programs will be automatically fetched by install these packages.

### RTL Infrastructure Dependencies
This IP core depends on the [RTL Infrastructure Library](https://github.com/hasu-ic-club/hasunosora-hdl-infra) provided by Hasunosora IC Design Club. 

The git URL of the library is already registered in the FuseSoC configuration file `~/.fusesoc/config` of the repository. So if you have set up FuseSoC correctly, it can automatically fetch the library when building the IP core.

### Building and Simulating the IP Core

The Makefile uses FuseSoC's simulation flow to build the IP core and run the cocotb testbench with Cadence Xcelium. Run the commands below from the repository root.

For a single configuration, use `make run`. The default is FP32 with round-to-nearest-even. You can select a different exponent width, mantissa width, or rounding mode on the command line.

```sh
make run
make run EXPONENT_WIDTH=3 MANTISSA_WIDTH=6 FP_ROUND_MODE=3
```

`FP_ROUND_MODE` of `0`, `1`, `2`, and `3` select rounding modes as following table.
| Rounding Mode | Number |
| -- | -- |
| To Nearest Even | 0 |
| Toward Zero | 1 |
| Toward Positive Infinity | 2 | 
| Toward Negative Infinity | 3 | 

To run a single test case, set `COCOTB_TEST_FILTER`.

```sh
make run COCOTB_TEST_FILTER=directed_extremes
```

Use `make regression` to run the full matrix of ten formats and four rounding modes. To run a smaller matrix, pass exponent:mantissa pairs in `FORMATS` and mode numbers in `ROUND_MODES`.

```sh
make regression
make regression FORMATS="8:23 4:3" ROUND_MODES="0 3"
```

Build artifacts and `results.xml` are stored separately for each configuration, for example under `build/cocotb/sim/e8m23r0/` for the default run. Make reports a failure if a test fails or cocotb produces no results.

For waveforms and RTL coverage, use the `sim_debug` target.

```sh
make run TARGET=sim_debug COCOTB_TEST_FILTER=directed_extremes
```

You can open the SHM waveform database in Indago. For the default configuration, it is stored at `build/cocotb/sim_debug/e8m23r0/ida.db/ida.shm`.

### Using Other Simulators

The supplied Makefile is set up for Xcelium. To run the same cocotb tests with another simulator, add a simulation target in `proj/hsf1_fpadd_pipe.core` and set `flow_options.tool` and the corresponding tool options for that simulator. Keep the cocotb test module, the simulation wrapper, and its three HDL parameters so you can run the same configurations.

Use the cocotb launch and waveform options supported by your simulator. The `sim_debug` target uses the Xcelium-specific script `proj/tb/script/xrun.tcl`. See the [FuseSoC documentation](https://fusesoc.readthedocs.io/en/stable/user/build_system/eda_flows.html) for details on configuring a simulation flow.

If you run into trouble, feel free to open an issue. Pull requests adding support for other simulators are welcome!

## Testing

Each configuration uses the same cocotb testbench to compare the result bits and the NaN, infinity, and exception flags against the reference model.

| Test Case Name | Description |
|----------------|-------------|
| `directed_extremes` | Checks signed zeros, NaNs, infinities, and boundary cases for cancellation, subnormal results, rounding, and overflow. |
| `random_binary` | Generates random operand bit patterns across the entire encoding space, including special values. |
| `random_finite` | Generates random finite operands with extra coverage around exponent boundaries, large exponent gaps, and near cancellation. Adds input gaps and output backpressure. |
| `exhaustive_small` | Checks every ordered pair of operand encodings for small formats. The default total operand width limit is 8 bits, including the sign bit. |
| `flow_control` | Checks full throughput, output stability under backpressure, and reset with transactions in flight. |

Use `HSF1_RANDOM_CASES` to set the number of vectors in each random test, `HSF1_SEED` to reproduce a run, and `HSF1_EXHAUSTIVE_BITS` to adjust the width limit for exhaustive testing.

## Known Issues
There is some bugs of rounding mode in v0.1 version and we fixed them in v0.2.

Currently, we have not found any known issues with this IP core. If you encounter any problems or bugs, please report them by opening an issue in this repository.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing
Contributions are welcome! If you find any issues or have suggestions for improvements, please open an issue or submit a pull request.