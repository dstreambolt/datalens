name := "dstreambolt-processor"

version := "1.0.0"

scalaVersion := "2.12.18"

// Spark dependencies
// Mark Spark and Kafka as "provided" since they're available in cluster
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % "3.5.0" % "provided",
  "org.apache.kafka" % "kafka-clients" % "3.6.1" % "provided",
  "com.mysql" % "mysql-connector-j" % "8.2.0",
  "com.github.scopt" %% "scopt" % "4.1.0",
  "software.amazon.awssdk" % "secretsmanager" % "2.20.0",
  "com.fasterxml.jackson.module" %% "jackson-module-scala" % "2.15.0"
)

// Assembly settings for fat jar
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", "services", xs @ _*) => MergeStrategy.concat
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case "reference.conf" => MergeStrategy.concat
  case "application.conf" => MergeStrategy.concat
  case x if x.endsWith(".proto") => MergeStrategy.first
  case x if x.contains("module-info") => MergeStrategy.discard
  case x => MergeStrategy.first
}

assembly / assemblyJarName := s"${name.value}-${version.value}.jar"


