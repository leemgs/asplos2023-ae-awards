#include <string.h>
#include <iostream>
#include <thread>
#include <iomanip>

#include "sb_select.h"
#include "sb_where.h"
#include "sb_aggregate.h"
#include "sb_join.h"
#include "sb_yahoo.h"

int main(int argc, char *argv[])
{
	string testcase = (argc > 1) ? argv[1] : "select";
    long unsigned int num_cores = (argc > 2) ? atoi(argv[2]) : thread::hardware_concurrency() - 1;
    long unsigned int records_total = (argc > 3) ? atoi(argv[3]) : 10000000;
	long unsigned int records_per_interval = (argc > 4) ? atoi(argv[4]) : 1000000;

	bench_pipeline_config config = {
		.records_total = records_total,
		.records_per_interval = records_per_interval,
		.cores = num_cores
	};

	print_config();

	double time = 0;
    if (testcase == "select") {
		auto projector = [](temporal_event e) {
            temporal_event e1 {e.dur, e.payload + 1};
            return e1;
        };
        SelectBench benchmark(config, 1, projector);
		time = benchmark.run_benchmark();
    } else if (testcase == "where") {
        auto filter = [](temporal_event e) {
            return e.payload > 0;
        };
        WhereBench benchmark(config, 1, filter);
		time = benchmark.run_benchmark();
    } else if (testcase == "alterdur") {
        auto projector = [](temporal_event e) {
            temporal_event e1 {e.dur + 1, e.payload};
            return e1;
        };
        SelectBench benchmark(config, 1, projector);
		time = benchmark.run_benchmark();
    } else if (testcase == "aggregate") {
        AggregateBench benchmark(config, 1);
		time = benchmark.run_benchmark();
    } else if (testcase == "join") {
        JoinBench benchmark(config, 1);
		time = benchmark.run_benchmark();
    } else if (testcase == "yahoo") {
        YahooBench benchmark(config, 1);
		time = benchmark.run_benchmark();
    } else {
        throw runtime_error("Invalid testcase");
    }

    cout << fixed;
    cout << "Throughput(M/s), " << testcase <<", " << num_cores << ", " << setprecision(3) << records_total / time << endl;

    return 0;
}
