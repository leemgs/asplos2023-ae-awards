package org.streambench;

import org.apache.spark.api.java.function.ForeachFunction;
import org.apache.spark.sql.*;
import org.apache.spark.sql.types.DataTypes;
import org.apache.spark.sql.types.StructField;
import org.apache.spark.sql.types.StructType;

import java.sql.Timestamp;
import java.util.*;

public class App {
    public static Dataset<Row> generateDf(Long size, Long period, SparkSession spark) {
        List<Row> list = new ArrayList<>();
        Random rand = new Random();
        double range = 100.0;
        for (int i = 0; i < size; i++) {
            double payload = rand.nextDouble() * range - range / 2;
            list.add(RowFactory.create(new Timestamp(i * period), new Timestamp((i + 1) * period), (float) payload));
        }
        StructType schema = DataTypes.createStructType(
                new StructField[] { DataTypes.createStructField("start_time", DataTypes.TimestampType, false),
                        DataTypes.createStructField("end_time", DataTypes.TimestampType, false),
                        DataTypes.createStructField("payload", DataTypes.FloatType, false) });

        return spark.createDataFrame(list, schema);
    }

    public static double runTest(Dataset<Row> test) {
        long start = System.nanoTime();
        test.foreach((ForeachFunction<Row>) e -> {
            return;
        });
        long end = System.nanoTime();
        return (end - start) / 1e9;
    }

    public static void main(String[] args) {
        String benchmark = (args.length > 0) ? args[0] : "select";
        long size = (args.length > 1) ? Long.parseLong(args[1]) : 10000000;
        long period = 1;

        SparkSession spark = SparkSession.builder().appName("Test").getOrCreate();
        spark.sparkContext().setLogLevel("ERROR");

        Dataset<Row> stream1 = generateDf(size, period, spark).cache();
        double runTime = 0;
        switch (benchmark) {
        case "select":
            Dataset<Row> select = stream1.select(functions.col("start_time"), functions.col("end_time"),
                    functions.col("payload").plus(3.0f));
            runTime = runTest(select);
            break;
        case "where":
            Dataset<Row> where = stream1.filter("payload > 0");
            runTime = runTest(where);
            break;
        case "aggregate":
            Dataset<Row> aggregate = stream1.groupBy(
                    functions.window(stream1.col("start_time"), String.format("%d milliseconds", 1000 * period)))
                    .sum("payload");
            runTime = runTest(aggregate);
            break;
        case "alterdur":
            Dataset<Row> alterdur = stream1.select(functions.col("start_time"),
                    functions.col("start_time")
                            .plus(functions.expr(String.format("INTERVAL %d MILLISECONDS", 10 * period))),
                    functions.col("payload"));
            runTime = runTest(alterdur);
            break;
        case "innerjoin":
            Dataset<Row> stream2 = generateDf(size, period, spark).cache();
            Dataset<Row> innerjoin = stream1.join(stream2,
                    stream1.col("start_time").equalTo(stream2.col("start_time")));
            runTime = runTest(innerjoin);
            break;
        default:
            System.out.println("Unknown benchmark type");
        }

        System.out.printf("Benchmark: %s; Execution Time: %.3f seconds", benchmark, runTime);
    }
}
