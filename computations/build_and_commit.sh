#!/bin/bash
# Build Scala Spark JAR locally and commit to repo
# Run this on your Mac before pushing to Git

set -e

cd "$(dirname "$0")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building Scala Spark Processor Locally"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if SBT is installed
if ! command -v sbt &> /dev/null; then
    echo "❌ SBT not found!"
    echo ""
    echo "Install SBT on macOS:"
    echo "  brew install sbt"
    echo ""
    exit 1
fi

echo "✅ SBT found: $(sbt --version | head -1)"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
sbt clean

echo ""
echo "📦 Building JAR with assembly..."
echo "   (This may take 2-5 minutes on first build)"
echo ""

# Build with increased memory
export SBT_OPTS="-Xmx2048m -Xss4m"
sbt assembly

# Find the JAR
JAR_FILE=$(find target/scala-2.12 -name "dstreambolt-processor-*.jar" -type f | head -1)

if [ -z "$JAR_FILE" ]; then
    echo "❌ JAR file not found after build!"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BUILD COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 JAR: $(basename $JAR_FILE)"
echo "📏 Size: $(ls -lh $JAR_FILE | awk '{print $5}')"
echo ""

# Ask if user wants to commit
read -p "Do you want to commit this JAR to Git? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "📝 Committing JAR to Git..."

    # Create .gitattributes to handle binary files
    if [ ! -f .gitattributes ]; then
        echo "*.jar binary" > .gitattributes
        git add .gitattributes
    fi

    # Force add the JAR (it might be in .gitignore)
    git add -f "$JAR_FILE"

    # Commit
    COMMIT_MSG="Build: Add Scala Spark JAR $(basename $JAR_FILE)"
    git commit -m "$COMMIT_MSG" || echo "⚠️  Nothing to commit or commit failed"

    echo ""
    echo "✅ JAR committed to Git"
    echo ""
    echo "📤 Push to remote:"
    echo "   git push"
    echo ""
    echo "🚀 Then run Jenkins job:"
    echo "   http://13.232.132.240:8081/job/deploy-prebuilt-scala-spark/"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

