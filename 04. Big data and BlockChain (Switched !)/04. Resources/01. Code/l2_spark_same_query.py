# IT 505 · Class 4 · Lesson 2 · Example 2b — The same question in Apache Spark (professor demonstration; optional for students).
# Task: count the Madrid order lines of orders_big.parquet with Spark, and look at the plan Spark makes before it computes.
# Link to the lecture: data frames, Spark SQL, and lazy evaluation ("plan first, compute later").
# Needs: Java 17 or newer, and  pip install pyspark  (Spark 4.x). Run it in the folder that contains orders_big.parquet.

# time measures how long each action takes, in seconds.
import time
# SparkSession is the entry point to every Spark program written in Python (PySpark).
from pyspark.sql import SparkSession

# Start Spark on this computer only: "local[*]" uses every processor core as if each core were a small worker machine.
spark = SparkSession.builder.appName("Mercadillo505").master("local[*]").getOrCreate()
# Hide the informational messages, so that only warnings and errors are printed.
spark.sparkContext.setLogLevel("ERROR")
# Print the Spark version, so the output can be compared with the slides.
print("Spark version:", spark.version)

# Describe the data: Spark reads the footer of the Parquet file (the schema) but does not read the rows yet.
orders = spark.read.parquet("orders_big.parquet")
# A transformation: keep the Madrid lines. Nothing is computed here; Spark only adds this step to its plan.
madrid = orders.filter(orders.city == "Madrid")
# explain() prints the physical plan: notice PushedFilters (the filter goes down to the file reader) and ReadSchema.
madrid.explain()

# An action: count() forces Spark to execute the plan; only now are the files read.
start = time.perf_counter()
# The answer must be the same number DuckDB gave on the same file.
print("Madrid lines (DataFrame):", madrid.count(), "in %.2f s" % (time.perf_counter() - start))

# Spark SQL: register the data frame under a table name, so that ordinary SQL can be used on it.
orders.createOrReplaceTempView("orders_big")
# Same question written in SQL; Spark turns this text into the same kind of plan.
start = time.perf_counter()
# collect() is an action: it brings the one-row result back to Python.
print("Madrid lines (Spark SQL):", spark.sql("SELECT COUNT(*) AS n FROM orders_big WHERE city = 'Madrid'").collect()[0]["n"], "in %.2f s" % (time.perf_counter() - start))

# Stop Spark and free the memory it used.
spark.stop()
