# Cider Evaluation
[![DOI](https://zenodo.org/badge/428745504.svg)](https://zenodo.org/badge/latestdoi/428745504)

This repository contains the evaluation materials for our ASPLOS 2023 paper
entitled "Stepwise Debugging for Hardware Accelerators".

This evaluation consists of one code artifact, the Cider Interpreter and
Interactive Debugger, and the tools required to reproduce the graphs appearing
in the paper.

**Goals**
1. To reproduce our benchmark graphs
2. Demonstrate the usability of Cider and compare it with related tools

# Setup

## Artifact Sources

This artifact is available in two formats: A docker container and through code
repositories hosted on github.

If you are using the prebuilt docker image then you do not need to clone the
repository, but should still keep this README file on hand. Otherwise run
```
git clone https://github.com/cucapra/cidr-evaluation
```

## Docker (est. 5-50 min)

This requires [Docker][docker]. If running via Docker Desktop, you
will need to increase the amount of memory the containers are allowed to use via
the settings. Around 14 GB of RAM should be sufficient, less than this may cause
certain benchmarks to be killed before completing.

***Note***: running benchmarks via Docker _will_ have an impact on performance.
In particular, it can cause Verilator compilation to take notably longer than
running locally on the machine and may influence the graphs produced later.

To get started, simply run:
```bash
# remove --rm if you want the container to persist on exit
docker run -it --rm ghcr.io/cucapra/cidr-eval:latest
```

You will now have a terminal open in the container and can proceed to
[use the artifact](#step-by-step-guide).


If instead you wish to build the docker image locally:
```bash
# if using bash
bash scripts/setup.sh

# or directly invoke the commands
docker build . -t cider-eval:latest &&
docker run -it cider-eval:latest
```

## Local Machine (est. 30-50+ min)

Running the code locally requires installing several tools:
- The Rust programming language
- Icarus Verilog
- Verilator
- Fud & the Calyx infrastructure
  - runt
- Dahlia
- (optional) TVM

The rest of this section will walk you through the process.

### Install build dependencies
You may also install these as the tools come up. Not all dependencies will be
necessary if you are not building everything from source (for example using
homebrew Verilator & Icarus).

```bash
# for mac
brew install jq sbt make autoconf flex bison scala ninja cmake build gperf numactl perl

# for linux
apt-get install -y jq sbt make autoconf g++ flex bison libfl2 libfl-dev default-jdk ninja-build build-essential cmake gperf libgoogle-perftools-dev numactl perl-doc perl ccache
```

### Install python dependencies
```bash
python3 -m pip install numpy flit prettytable wheel hypothesis pytest simplejson matplotlib scipy seaborn
```

### Install [Rust][rust]
```bash
# On Mac and Linux
curl https://sh.rustup.rs -sSf | sh
```

### Install Rust-based tools
```bash
cargo install runt

# optional, only needed if you want to use fud's vcd-json target
cargo install vcdump
```

### Install [Verilator][verilator]
```bash
# On Mac:
brew install verilator

# On Linux
# first see https://verilator.org/guide/latest/install.html
git clone --branch v4.220 https://github.com/verilator/verilator
cd verilator && autoconf &&
./configure && make && sudo make install
```

### Install [Icarus-Verilog][icarus]
```bash
# On Mac:
brew install icarus-verilog

# On linux
git clone --branch v11_0 https://github.com/steveicarus/iverilog
sh autoconf.sh && ./configure && make && make install
```

### Install [TVM][tvm] (optional)
This step is not necessary to run the benchmarks but is required to use the
relay frontend.

```bash
git clone --recursive https://github.com/apache/tvm.git
cd tvm
git checkout v0.10.dev0
git submodule init && git submodule update
mkdir build && cd build
cp ../cmake/config.cmake
cmake -G Ninja .. && ninja # optionally -j `nproc` for faster build

python3 -m pip install -Iv antlr4-python3-runtime==4.7.2

cd ../python
python3 setup.py bdist_wheel && python3 -m pip install --user dist/tvm-*.whl
```

### Build [Dahlia][dahlia]
This requires Java, Scala, and sbt.

```bash
# for Mac
brew cask install adoptopenjdk
brew install scala sbt

# for ubuntu/debian
# from https://www.scala-sbt.org/1.x/docs/Installing-sbt-on-Linux.html#Ubuntu+and+other+Debian-based+distributions

sudo apt-get update
sudo apt-get install apt-transport-https curl gnupg -yqq
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo -H gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/scalasbt-release.gpg --import
sudo chmod 644 /etc/apt/trusted.gpg.d/scalasbt-release.gpg
sudo apt-get update
sudo apt-get install sbt
```

To build Dahlia:
```bash
git clone https://github.com/cucapra/dahlia.git && cd dahlia
sbt "; getHeaders; assembly"
```

### Build Calyx and Cider
```bash
git clone https://github.com/cucapra/calyx.git calyx
cd calyx
git checkout cider-eval # important !!!
cargo build --all --release
```

### Install Fud
```bash
cd calyx # go to the calyx directory from the prior step
cd fud
flit install --symlink # make sure this is in your path
```
Now you need to configure fud. Fill in `PATH/TO/CALYX` and `PATH/TO/DAHLIA` with
the appropriate values for your installation

```bash
fud config global.futil_directory 'PATH/TO/CALYX' && \
fud config stages.dahlia.exec 'PATH/TO/DAHLIA/fuse' && \
fud config stages.futil.exec 'PATH/TO/CALYX/target/release/futil' && \
fud config stages.interpreter.exec 'PATH/TO/CALYX/target/release/interp' && \
fud register icarus-verilog -p 'PATH/TO/CALYX/fud/icarus/icarus.py' && \
fud config stages.interpreter.flags " --no-verify " # the spaces are important
```

You may optionally link the mrxl and ntt frontends, though they are not required
to run the benchmarks:
```bash
fud register ntt -p 'PATH/TO/CALYX/frontends/ntt-pipeline/fud/ntt.py' && \
fud register mrxl -p 'PATH/TO/CALYX/frontends/mrxl/fud/mrxl.py'
```

You can now run `fud check` to see that all the pieces were installed correctly.
Fud will note that
```
synth-verilog, vivado-hls were not installed correctly.
```
which is expected behavior as these targets are not required.

### Install Calyx-py
```bash
cd calyx/calyx-py
flit install --symlink
```

Congrats! You should now be ready to run the artifact locally.

## Step-by-step Guide
- **Benchmark data and graph generation**: Generate the graphs found in the paper
  using pre-supplied data.
    - Core benchmark graphs (Fig 6a, 6b, 6c)
    - LeNet comparison (table 2)
- **Benchmark correctness across tools**
  - Verify that Icarus, Verilator, and Cider all correctly simulate the entire
    benchmark suite (i.e. all tools agree)
- **Data Collection**
  - Collect benchmark data for the full benchmark suite
  - Generate graphs & table from collected data
- *(Optional)* **Interactive Debugging with Cider**
  - Debug the sample program with Cider (sec 4)


## Graph Generation (5 min)

This repo includes the folder `paper_data` which contains the data we collected
and used to generate the graphs in the paper. The data is separated into
`individual-results`, which contains a file for each benchmark detailing each trial
performed, and `statistics` which has the statistical analysis for each
benchmark.

When ready, you can generate the graphs from the paper by running (from the repo
root):
```bash
# in cider-eval
python3 scripts/visualize.py paper_data/statistics
```

This will generate 3 pdf files called `f3`, `f2`, and `f1` corresponding to
figure 6a, 6b, and 6c, respectively. It will also print out a summary of various
statistics to the standard output. In particular, you should see the stats for
the LeNet trial (used in Table 2):
```
===LeNet Stats===
Icarus Comp: 0.308 s
 stderr: 0.003 s
Icarus Sim: 215.03990000000002 min
 stderr: 1.8939833333333334 min
Icarus Slowdown: 27.877538762034813

Icarus Slowdown (interp): 8.254980380464792

verilator Comp: 16.506 s
 stderr: 5.873 s
verilator Sim: 7.713733333333334 min
 stderr: 0.00835 min

interp Sim: 26.049716666666665 min
 stderr: 0.061233333333333334 min
interp Slowdown: 3.377056937410333
```

## Benchmark Correctness (est 5+ hours)

Next we can verify that the tools all produce the correct (and identical)
results for each of our benchmarks. We use the snapshot testing tool
[Runt][runt] to compare the output of each tool to a single "golden" result for
each benchmark. This means that all tools are producing the same exact results
after running through jq formatting.

From the root of this repo you can run the following command to evaluate *all the
benchmarks*.
```bash
# in cider-eval
runt
```
This will run 95 different tests, running each of the benchmarks through Cider,
Icarus, and Verilator. As well as running the Core benchmarks suite (everything
but LeNet) through Cider after being fully lowered.

This process will take some time to complete. In particular, NTT-64 can take a
while for Verilator to compile and LeNet will take a long time to execute for
Cider and Icarus.

For a quick(er) smoke test, you can run
```bash
# in cider-eval
runt -x "lenet|ntt"
```
this will run the polybench and TCAM tests but skip the longer running NTT tests
and LeNet. This should complete in a few minutes.

When finished with the *full* test suite, you should see that all 95 tests have
passed. If you want a print out of the tests as they complete you can run
```bash
# in cider-eval
runt -v
```
which will also display names in addition to incrementing the completion count.

The benchmarks are contained in the `benchmarks` folder and the expected output
for each benchmark is `NAME.expect`.

If the tests fail with a timeout, adjust the timeout value in `runt.toml` for
the appropriate test suite.

## Data Collection (est ~24 hours)

To collect timing data locally run:
```bash
# in cider-eval
python3 scripts/run-benchmarks.py full
```

This will run the entire benchmark suite including LeNet. Each benchmark (except
LeNet) is run ten times for each tool (Cider, Icarus, Verilator) and an addition
ten times through Cider with the program fully lowered (Cider-Lowered). LeNet is
run five times for each tool and is not run fully lowered.

This will produce an `individual-results` and `statistics` folder in the root of
the repo. Note that the timing data is unlikely to be identical because of
differences in machines and resources but that the general relationship between
the tools timing behaviors should hold. Once data is collected you can run
```bash
# in cider-eval
python3 scripts/visualize.py statistics
```
to generate the graphs and statistics from your collected data. Compare these
graphs to figures 6a-c in the paper, they should be similar. The LeNet
statistics are likely to differ but the slowdown numbers between the different
tools should be similar to those we collected.

## *(optional)* Interactive Debugging with Cider (~10 minutes)

This section is meant to let you use Cider's [interactive debugging mode][cider-docs] instead
of the interpreter mode. For this, we've setup a few files from the example
calyx program in section 2.2. These files are the same program, but with a
hardcoded input value `x`, so that the example component can stand alone. This
follows the debugging process shown in section 3. It will be useful to keep this
portion of the paper handy while working through this section. And, if desired,
the [docs][cider-docs] can also be consulted for more detailed discussions of
Cider's commands

To start, run the following command from the root directory:
```bash
# in cider-eval
fud e --to debugger examples/first.futil
```

This will open the interactive debugger. You can type `help` and enter to see
the help message.
```
 > help
```

This will list the different commands the debugger supports. You can see
specific examples of command usage via
```
 > explain
```

When you're ready, run
```
 > continue
```

You will see the same warning printing out repeatedly:
```
WARN Computation over/underflow, source: counter.add
```
Press `CTRL-C` to kill the process.

Reopen the debugger with:
```bash
# in cider-eval
fud e --to debugger examples/first.futil
```

You can set a watchpoint as shown in the paper via:
```
 > watch after incr_idx with print idx_r.out
```

When you're ready, run
```
 > continue
```
and press `CTRL-C` to kill the process after a few seconds. You should see
something like this
```
    idx_r.out = [00]
    idx_r.out = [01]
    idx_r.out = [10]
WARN Computation over/underflow, source: counter.add
    idx_r.out = [11]
WARN Computation over/underflow, source: counter.add
    idx_r.out = [00]
```
This is showing the register value which is overflowing and causing the
infinite loop. Note that because of how warnings are printed, they may not
intersperse exactly as shown.

You can now correct the bug as shown in section 3, if you wish to edit the
example file, or you may instead move to `examples/second.futil`. When you're
ready, run
```bash
# in cider-eval
fud e --to debugger examples/second.futil
```

Then run the continue command
```
 > c
```

The debugger should exit with the following message:
```
Error: invalid memory access to memory counter.dest_m. Given index (1) but memory has dimension (1)
```

This is showing the incorrect memory access happening in the `upd` group. You
can correct the file as discussed in section 3 or move to
`examples/third.futil`.

```bash
# in cider-eval
fud e --to debugger examples/third.futil
```
Run the continue command again, you should see the following:
```
 > c
Main component has finished executing. Debugger is now in inspection mode.
```

Run the following to inspect the output.
```
 > print-state dest_m
    dest_m = [[00000000000000100000000000000000]]
 > print-state \u.16 dest_m
    dest_m = [2]
```

This shows the use of the `print-state` command and formatting codes. These are
discussed in more detail in section 3 of the paper.

Exit the debugger with
```
> exit
```
and re-open the file
```bash
# in cider-eval
fud e --to debugger examples/third.futil
```

Run the following commands:
```
> break incr_st
> continue
Hit breakpoint: counter::incr_st
> print \u.16 acc_r.out
  acc_r.out = 0
> step-over incr_st
> print \u.16 acc_r.out
  acc_r.out = 1/2
```

This demonstrates the incorrect value of the `step` constant!.

You can now make the final set of corrections or move to file `examples/fourth.futil`

```bash
# in cider-eval
fud e --to debugger examples/fourth.futil
```

Finally we can rerun the program and inspect the results.
```
 > c
Main component has finished executing. Debugger is now in inspection mode.
 > print-state \u.16 dest_m
    dest_m = [4]
 >
```

The example program is now correct! This concludes the debugging section, feel
free to play around or close the program at your leisure.

[docker]: https://www.docker.com/
[rust]: https://doc.rust-lang.org/cargo/getting-started/installation.html
[verilator]: https://verilator.org/guide/latest/install.html
[icarus]: http://iverilog.icarus.com/
[tvm]: https://tvm.apache.org/docs/install/from_source.html
[dahlia]: https://capra.cs.cornell.edu/fuse/docs/installation/
[runt]: https://github.com/rachitnigam/runt
[cider-docs]: https://docs.calyxir.org/debug/cider.html
