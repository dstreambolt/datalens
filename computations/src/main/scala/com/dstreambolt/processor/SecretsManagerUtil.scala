package com.dstreambolt.processor

import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.scala.DefaultScalaModule
import scala.util.{Try, Success, Failure}

/**
 * AWS Secrets Manager client for DStreamBolt Spark processor
 * Retrieves MySQL credentials securely from AWS Secrets Manager
 */
object SecretsManagerUtil {

  private val mapper = new ObjectMapper()
  mapper.registerModule(DefaultScalaModule)

  /**
   * Get MySQL configuration from AWS Secrets Manager
   *
   * @param secretName Name of the secret in AWS Secrets Manager
   * @param region AWS region (default: ap-south-1)
   * @return Map containing MySQL configuration
   */
  def getMySQLConfig(
    secretName: String = "dstreambolt/mysql",
    region: String = "ap-south-1"
  ): Try[Map[String, String]] = {
    Try {
      println(s"🔐 Loading MySQL config from AWS Secrets Manager: $secretName")

      val client = SecretsManagerClient.builder()
        .region(Region.of(region))
        .build()

      try {
        val request = GetSecretValueRequest.builder()
          .secretId(secretName)
          .build()

        val response = client.getSecretValue(request)
        val secretString = response.secretString()

        // Parse JSON to Map
        val config = mapper.readValue(secretString, classOf[Map[String, Any]])
          .map { case (k, v) => k -> v.toString }

        println("✅ MySQL config loaded from Secrets Manager")
        println(s"   Host: ${config.getOrElse("host", "N/A")}")
        println(s"   Database: ${config.getOrElse("database", "N/A")}")
        println(s"   User: ${config.getOrElse("username", "N/A")}")

        // Convert to expected format
        Map(
          "host" -> config.getOrElse("host", "localhost"),
          "port" -> config.getOrElse("port", "3306"),
          "user" -> config.getOrElse("username", "root"),
          "password" -> config.getOrElse("password", ""),
          "database" -> config.getOrElse("database", "dstreambolt_metrics")
        )
      } finally {
        client.close()
      }
    } recoverWith {
      case e: Exception =>
        println(s"⚠️  Failed to load from Secrets Manager: ${e.getMessage}")
        println("   Falling back to environment variables...")
        Success(getMySQLConfigFromEnv())
    }
  }

  /**
   * Get MySQL configuration from environment variables (fallback)
   */
  private def getMySQLConfigFromEnv(): Map[String, String] = {
    Map(
      "host" -> sys.env.getOrElse("MYSQL_HOST", "localhost"),
      "port" -> sys.env.getOrElse("MYSQL_PORT", "3306"),
      "user" -> sys.env.getOrElse("MYSQL_USER", "root"),
      "password" -> sys.env.getOrElse("MYSQL_PASSWORD", ""),
      "database" -> sys.env.getOrElse("MYSQL_DATABASE", "dstreambolt_metrics")
    )
  }

  /**
   * Get Kafka configuration from AWS Secrets Manager
   *
   * @param secretName Name of the secret in AWS Secrets Manager
   * @param region AWS region (default: ap-south-1)
   * @return Map containing Kafka configuration
   */
  def getKafkaConfig(
    secretName: String = "dstreambolt/kafka",
    region: String = "ap-south-1"
  ): Try[Map[String, String]] = {
    Try {
      println(s"🔐 Loading Kafka config from AWS Secrets Manager: $secretName")

      val client = SecretsManagerClient.builder()
        .region(Region.of(region))
        .build()

      try {
        val request = GetSecretValueRequest.builder()
          .secretId(secretName)
          .build()

        val response = client.getSecretValue(request)
        val secretString = response.secretString()

        // Parse JSON to Map
        val config = mapper.readValue(secretString, classOf[Map[String, Any]])

        println("✅ Kafka config loaded from Secrets Manager")

        // Extract brokers list
        val brokers = config.get("brokers") match {
          case Some(list: List[_]) => list.mkString(",")
          case Some(str: String) => str
          case _ => "localhost:9092"
        }

        Map(
          "brokers" -> brokers,
          "topic" -> config.getOrElse("topic", "dstreambolt-logs").toString,
          "security_protocol" -> config.getOrElse("security_protocol", "PLAINTEXT").toString
        )
      } finally {
        client.close()
      }
    } recoverWith {
      case e: Exception =>
        println(s"⚠️  Failed to load Kafka config from Secrets Manager: ${e.getMessage}")
        println("   Falling back to environment variables...")
        Success(getKafkaConfigFromEnv())
    }
  }

  /**
   * Get Kafka configuration from environment variables (fallback)
   */
  private def getKafkaConfigFromEnv(): Map[String, String] = {
    Map(
      "brokers" -> sys.env.getOrElse("KAFKA_BROKERS", "localhost:9092"),
      "topic" -> sys.env.getOrElse("KAFKA_TOPIC", "dstreambolt-logs"),
      "security_protocol" -> sys.env.getOrElse("KAFKA_SECURITY_PROTOCOL", "PLAINTEXT")
    )
  }

  /**
   * Test connection to AWS Secrets Manager
   */
  def testConnection(region: String = "ap-south-1"): Boolean = {
    Try {
      val client = SecretsManagerClient.builder()
        .region(Region.of(region))
        .build()

      try {
        client.listSecrets()
        true
      } finally {
        client.close()
      }
    }.getOrElse(false)
  }
}

