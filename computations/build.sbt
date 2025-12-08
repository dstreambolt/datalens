name := "dstreambolt-processor"

version := "1.0.0"

scalaVersion := "2.12.18"

// Spark dependencies
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql" % "3.5.0" % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % "3.5.0",
  "org.apache.kafka" % "kafka-clients" % "3.5.0",
  "com.mysql" % "mysql-connector-j" % "8.2.0",
  "com.github.scopt" %% "scopt" % "4.1.0"
)

// Assembly settings for fat jar
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case "reference.conf" => MergeStrategy.concat
  case x => MergeStrategy.first
}

assembly / assemblyJarName := s"${name.value}-${version.value}.jar"

// Exclude provided dependencies from assembly
assembly / assemblyExcludedJars := {
  val cp = (assembly / fullClasspath).value
  cp.filter { jar =>
    jar.data.getName.startsWith("spark-")
  }
}

