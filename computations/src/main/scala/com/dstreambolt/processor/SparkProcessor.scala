package com.dstreambolt.processor

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.Trigger
import java.util.Properties

/**
 * DStreamBolt Spark Processor
 * Real-time and batch processing of log data from Kafka
 */
object SparkProcessor {

  val logSchema: StructType = StructType(Array(
    StructField("timestamp", StringType, nullable = true),
    StructField("ip", StringType, nullable = true),
    StructField("method", StringType, nullable = true),
    StructField("endpoint", StringType, nullable = true),
    StructField("status", IntegerType, nullable = true),          // Changed from status_code
    StructField("size", IntegerType, nullable = true),            // Changed from response_size
    StructField("referer", StringType, nullable = true),          // Added referer
    StructField("user_agent", StringType, nullable = true),
    StructField("response_time", DoubleType, nullable = true),    // Added response_time
    StructField("request_id", StringType, nullable = true),
    StructField("ingestion_timestamp", StringType, nullable = true)
  ))

  /**
   * Create Spark session
   */
  def createSparkSession(appName: String = "DStreamBolt-Processor", master: Option[String] = None): SparkSession = {
    val builder = SparkSession.builder()
      .appName(appName)
      .config("spark.sql.streaming.forceDeleteTempCheckpointLocation", "true")
      .config("spark.streaming.stopGracefullyOnShutdown", "true")

    master.foreach(m => builder.master(m))

    builder.getOrCreate()
  }

  /**
   * Batch processing of Kafka messages
   */
  def processBatch(
    spark: SparkSession,
    kafkaBroker: String,
    topic: String = "dstreambolt-logs",
    outputPath: Option[String] = None
  ): DataFrame = {
    import spark.implicits._

    println(s"📊 Starting batch processing from Kafka topic: $topic")

    // Read from Kafka
    val df = spark.read
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBroker)
      .option("subscribe", topic)
      .option("startingOffsets", "earliest")
      .load()

    // Parse JSON
    val logsDF = df
      .select(from_json(col("value").cast("string"), logSchema).as("data"))
      .select("data.*")
      .withColumn("processing_timestamp", current_timestamp())

    val totalCount = logsDF.count()
    println(s"✅ Read $totalCount log entries from Kafka")

    // Aggregations
    println("\n" + "=" * 80)
    println("📈 REQUEST STATISTICS BY STATUS CODE:")
    println("=" * 80)
    logsDF.groupBy("status")
      .count()
      .orderBy(desc("count"))
      .show(false)

    println("\n" + "=" * 80)
    println("🔝 TOP 10 ENDPOINTS:")
    println("=" * 80)
    logsDF.groupBy("endpoint")
      .count()
      .orderBy(desc("count"))
      .limit(10)
      .show(false)

    println("\n" + "=" * 80)
    println("🔝 TOP 10 SLOWEST ENDPOINTS (Avg Response Time):")
    println("=" * 80)
    logsDF.groupBy("endpoint")
      .agg(
        avg("response_time").as("avg_response_time"),
        count("*").as("request_count")
      )
      .orderBy(desc("avg_response_time"))
      .limit(10)
      .show(false)

    println("\n" + "=" * 80)
    println("⚠️  ERROR ANALYSIS (Status >= 400):")
    println("=" * 80)
    val errorDF = logsDF.filter(col("status") >= 400)
    val errorCount = errorDF.count()

    if (errorCount > 0) {
      errorDF.groupBy("status", "endpoint")
        .count()
        .orderBy(desc("count"))
        .limit(10)
        .show(false)
    } else {
      println("✅ No errors found!")
    }

    println("\n" + "=" * 80)
    println(s"📊 SUMMARY: Processed $totalCount logs, $errorCount errors")
    println("=" * 80)

    // Save results if output path provided
    outputPath.foreach { path =>
      println(s"\n💾 Saving results to: $path")
      logsDF.write.mode("overwrite").parquet(path)
    }

    logsDF
  }

  /**
   * Streaming processing of Kafka messages with MySQL sink
   */
  def processStreaming(
    spark: SparkSession,
    kafkaBroker: String,
    topic: String = "dstreambolt-logs",
    checkpointDir: String = "/tmp/spark-checkpoints",
    windowDuration: String = "30 seconds",
    mysqlConfig: Option[Map[String, String]] = None
  ): Unit = {
    import spark.implicits._

    println(s"🔄 Starting streaming processing from Kafka topic: $topic")
    println(s"📍 Checkpoint directory: $checkpointDir")
    println(s"⏱️  Window duration: $windowDuration")

    // Read stream from Kafka
    val streamDF = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", kafkaBroker)
      .option("subscribe", topic)
      .option("startingOffsets", "latest")
      .load()

    // Parse JSON - use timestamp from data, not Kafka metadata
    val logsStream = streamDF
      .select(
        from_json(col("value").cast("string"), logSchema).as("data")
      )
      .select("data.*")
      .withColumn("processing_timestamp", current_timestamp())
      .withColumn("event_timestamp", to_timestamp(col("timestamp")))

    // Windowed aggregations by status
    val statusAggregations = logsStream
      .withWatermark("event_timestamp", "2 minutes")
      .groupBy(
        window(col("event_timestamp"), windowDuration),
        col("status")
      )
      .agg(
        count("*").as("request_count"),
        avg("size").as("avg_response_size"),
        avg("response_time").as("avg_response_time"),
        max("response_time").as("max_response_time"),
        min("response_time").as("min_response_time")
      )
      .select(
        col("window.start").as("window_start"),
        col("window.end").as("window_end"),
        col("status"),
        col("request_count"),
        col("avg_response_size"),
        col("avg_response_time"),
        col("max_response_time"),
        col("min_response_time"),
        current_timestamp().as("processing_timestamp")
      )

    // Endpoint aggregations
    val endpointAggregations = logsStream
      .withWatermark("event_timestamp", "2 minutes")
      .groupBy(
        window(col("event_timestamp"), windowDuration),
        col("endpoint"),
        col("method")
      )
      .agg(
        count("*").as("request_count"),
        avg("response_time").as("avg_response_time"),
        expr("percentile_approx(response_time, 0.95)").as("p95_response_time"),
        expr("percentile_approx(response_time, 0.99)").as("p99_response_time"),
        approx_count_distinct("ip").as("unique_ips"),
        sum(when(col("status") >= 400, 1).otherwise(0)).as("error_count")
      )
      .select(
        col("window.start").as("window_start"),
        col("window.end").as("window_end"),
        col("endpoint"),
        col("method"),
        col("request_count"),
        col("avg_response_time"),
        col("p95_response_time"),
        col("p99_response_time"),
        col("unique_ips"),
        col("error_count"),
        current_timestamp().as("processing_timestamp")
      )

    if (mysqlConfig.isDefined) {
      val config = mysqlConfig.get
      val url = s"jdbc:mysql://${config("host")}:3306/${config("database")}"

      // Write status aggregations to MySQL
      val statusQuery = statusAggregations.writeStream
        .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
          println(s"📊 Writing status aggregations batch $batchId to MySQL")
          batchDF.write
            .format("jdbc")
            .option("url", url)
            .option("dbtable", "status_summary")
            .option("user", config("user"))
            .option("password", config("password"))
            .option("driver", "com.mysql.cj.jdbc.Driver")
            .mode("append")
            .save()
        }
        .outputMode("update")
        .option("checkpointLocation", s"$checkpointDir/status")
        .trigger(Trigger.ProcessingTime(windowDuration))
        .start()

      // Write endpoint aggregations to MySQL
      val endpointQuery = endpointAggregations.writeStream
        .foreachBatch { (batchDF: DataFrame, batchId: Long) =>
          println(s"📊 Writing endpoint aggregations batch $batchId to MySQL")
          batchDF.write
            .format("jdbc")
            .option("url", url)
            .option("dbtable", "endpoint_summary")
            .option("user", config("user"))
            .option("password", config("password"))
            .option("driver", "com.mysql.cj.jdbc.Driver")
            .mode("append")
            .save()
        }
        .outputMode("update")
        .option("checkpointLocation", s"$checkpointDir/endpoint")
        .trigger(Trigger.ProcessingTime(windowDuration))
        .start()

      println("✅ Streaming queries started. Writing to MySQL every window.")
      println("Press Ctrl+C to stop.")

      statusQuery.awaitTermination()
    } else {
      // Fallback to console output if MySQL not configured
      val query = statusAggregations.writeStream
        .outputMode("update")
        .format("console")
        .option("truncate", "false")
        .option("checkpointLocation", checkpointDir)
        .trigger(Trigger.ProcessingTime(windowDuration))
        .start()

      println("✅ Streaming query started (console mode). Press Ctrl+C to stop.")
      query.awaitTermination()
    }
  }

  /**
   * Write DataFrame to MySQL
   */
  def writeToMySQL(df: DataFrame, mysqlConfig: Map[String, String]): Unit = {
    val host = mysqlConfig("host")
    val database = mysqlConfig("database")
    val table = mysqlConfig.getOrElse("table", "spark_results")
    val user = mysqlConfig("user")
    val password = mysqlConfig("password")

    println(s"💾 Writing to MySQL: $host/$database")

    val url = s"jdbc:mysql://$host:3306/$database"

    df.write
      .format("jdbc")
      .option("url", url)
      .option("dbtable", table)
      .option("user", user)
      .option("password", password)
      .option("driver", "com.mysql.cj.jdbc.Driver")
      .mode("append")
      .save()

    println("✅ Data written to MySQL successfully")
  }

  /**
   * Parse command line arguments
   */
  case class Config(
    sparkMaster: String = "",
    appName: String = "DStreamBolt-Processor",
    kafkaBroker: String = "",
    topic: String = "dstreambolt-logs",
    mode: String = "batch",
    windowDuration: String = "30 seconds",
    outputPath: Option[String] = None,
    checkpointDir: String = "/tmp/spark-checkpoints",
    mysqlHost: Option[String] = None,
    mysqlUser: Option[String] = None,
    mysqlPassword: Option[String] = None,
    mysqlDatabase: String = "dstreambolt",
    mysqlTable: String = "spark_results"
  )

  def parseArgs(args: Array[String]): Config = {
    val parser = new scopt.OptionParser[Config]("SparkProcessor") {
      head("DStreamBolt Spark Processor", "1.0")

      opt[String]("spark-master")
        .required()
        .action((x, c) => c.copy(sparkMaster = x))
        .text("Spark master URL (e.g., spark://host:7077)")

      opt[String]("app-name")
        .optional()
        .action((x, c) => c.copy(appName = x))
        .text("Spark application name")

      opt[String]("kafka-broker")
        .required()
        .action((x, c) => c.copy(kafkaBroker = x))
        .text("Kafka broker address (e.g., host:9092)")

      opt[String]("topic")
        .optional()
        .action((x, c) => c.copy(topic = x))
        .text("Kafka topic to consume")

      opt[String]("mode")
        .optional()
        .action((x, c) => c.copy(mode = x))
        .validate(x => if (Seq("batch", "streaming").contains(x)) success else failure("mode must be 'batch' or 'streaming'"))
        .text("Processing mode (batch or streaming)")

      opt[String]("window-duration")
        .optional()
        .action((x, c) => c.copy(windowDuration = x))
        .text("Window duration for streaming aggregations")

      opt[String]("output-path")
        .optional()
        .action((x, c) => c.copy(outputPath = Some(x)))
        .text("Output path for batch processing results")

      opt[String]("checkpoint-dir")
        .optional()
        .action((x, c) => c.copy(checkpointDir = x))
        .text("Checkpoint directory for streaming")

      opt[String]("mysql-host")
        .optional()
        .action((x, c) => c.copy(mysqlHost = Some(x)))
        .text("MySQL host")

      opt[String]("mysql-user")
        .optional()
        .action((x, c) => c.copy(mysqlUser = Some(x)))
        .text("MySQL user")

      opt[String]("mysql-password")
        .optional()
        .action((x, c) => c.copy(mysqlPassword = Some(x)))
        .text("MySQL password")

      opt[String]("mysql-database")
        .optional()
        .action((x, c) => c.copy(mysqlDatabase = x))
        .text("MySQL database")

      opt[String]("mysql-table")
        .optional()
        .action((x, c) => c.copy(mysqlTable = x))
        .text("MySQL table")
    }

    parser.parse(args, Config()) match {
      case Some(config) => config
      case None => sys.exit(1)
    }
  }

  def main(args: Array[String]): Unit = {
    val config = parseArgs(args)

    println("=" * 60)
    println("🚀 DStreamBolt Spark Processor")
    println("=" * 60)
    println(s"Mode: ${config.mode}")
    println(s"Kafka Broker: ${config.kafkaBroker}")
    println(s"Topic: ${config.topic}")
    println(s"Spark Master: ${config.sparkMaster}")
    println("=" * 60)

    // Create Spark session
    val spark = createSparkSession(config.appName, Some(config.sparkMaster))
    spark.sparkContext.setLogLevel("WARN")

    try {
      // Build MySQL config if provided
      val mysqlConfig = if (config.mysqlHost.isDefined && config.mysqlUser.isDefined && config.mysqlPassword.isDefined) {
        Some(Map(
          "host" -> config.mysqlHost.get,
          "user" -> config.mysqlUser.get,
          "password" -> config.mysqlPassword.get,
          "database" -> config.mysqlDatabase,
          "table" -> config.mysqlTable
        ))
      } else {
        None
      }

      config.mode match {
        case "batch" =>
          val df = processBatch(
            spark,
            config.kafkaBroker,
            config.topic,
            config.outputPath
          )

          // Write to MySQL if configured
          mysqlConfig.foreach(cfg => writeToMySQL(df, cfg))

        case "streaming" =>
          processStreaming(
            spark,
            config.kafkaBroker,
            config.topic,
            config.checkpointDir,
            config.windowDuration,
            mysqlConfig
          )
      }
    } catch {
      case _: InterruptedException =>
        println("\n⏹️  Stopping Spark processor...")
      case e: Exception =>
        println(s"\n❌ Error: ${e.getMessage}")
        e.printStackTrace()
        sys.exit(1)
    } finally {
      spark.stop()
      println("✅ Spark session stopped")
    }
  }
}