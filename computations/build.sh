#!/bin/bash
# Build Scala Spark Processor

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building DStreamBolt Scala Processor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if sbt is installed
if ! command -v sbt &> /dev/null; then
    echo "❌ sbt not found. Installing..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install sbt
        else
            echo "Please install Homebrew first: https://brew.sh"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Ubuntu/Debian
        echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
        echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list
        curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo apt-key add
        sudo apt-get update
        sudo apt-get install sbt
    else
        echo "Unsupported OS. Please install sbt manually: https://www.scala-sbt.org/download.html"
        exit 1
    fi
fi

echo "✅ sbt version:"
sbt --version

echo ""
echo "📦 Cleaning previous builds..."
sbt clean

echo ""
echo "🔧 Compiling Scala code..."
sbt compile

echo ""
echo "📦 Creating fat JAR with dependencies..."
sbt assembly

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BUILD COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 Output JAR:"
ls -lh target/scala-2.12/*.jar
echo ""
echo "To submit to Spark:"
echo "  spark-submit --master spark://host:7077 \\"
echo "    --class com.dstreambolt.processor.SparkProcessor \\"
echo "    target/scala-2.12/dstreambolt-processor-1.0.0.jar \\"
echo "    --spark-master spark://host:7077 \\"
echo "    --kafka-broker host:9092 \\"
echo "    --mode batch"
echo ""

