#!/bin/bash

# Build script for Windows 11 executable
# This script builds XPipe for Windows 11
# Works on both Windows (Git Bash/MSYS) and Linux environments

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${GREEN}=== XPipe Windows 11 Build Script ===${NC}\n"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

# Detect if we're on Windows (Git Bash/MSYS)
IS_WINDOWS=false
if [[ -n "$MSYSTEM" ]] || [[ -n "$MINGW_PREFIX" ]] || [[ -d "/c/Program Files" ]] || [[ -n "$WINDIR" ]]; then
    IS_WINDOWS=true
fi

# Check Java (JDK required, not just JRE)
# On Windows, try to find Java in common locations if not in PATH
if ! command_exists java; then
    if [ "$IS_WINDOWS" = "true" ]; then
        echo -e "${YELLOW}Java not in PATH, searching Windows installation directories...${NC}"
        
        # Common Windows Java installation paths
        WINDOWS_PATHS=(
            "/c/Program Files/Microsoft/jdk-"*
            "/c/Program Files/Eclipse Adoptium/jdk-"*
            "/c/Program Files/Java/jdk-"*
            "/c/Program Files (x86)/Java/jdk-"*
        )
        
        JAVA_FOUND=false
        for java_base in "${WINDOWS_PATHS[@]}"; do
            # Expand glob pattern
            for java_dir in $java_base; do
                if [ -d "$java_dir" ] && [ -f "$java_dir/bin/java.exe" ]; then
                    export PATH="$java_dir/bin:$PATH"
                    echo -e "${GREEN}Found Java at: $java_dir${NC}"
                    JAVA_FOUND=true
                    break 2
                fi
            done
        done
        
        if [ "$JAVA_FOUND" = "false" ]; then
            echo -e "${RED}Error: Java is not installed or not found.${NC}"
            echo -e "${YELLOW}  Please install JDK 17+ using: winget install Microsoft.OpenJDK.25${NC}"
            echo -e "${YELLOW}  Or manually add Java to your PATH${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Java is not installed. Please install JDK 17 or later.${NC}"
        echo -e "${YELLOW}  On RHEL/CentOS: sudo yum install java-17-openjdk-devel${NC}"
        echo -e "${YELLOW}  On Ubuntu/Debian: sudo apt install openjdk-17-jdk${NC}"
        exit 1
    fi
fi

JAVA_VERSION=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | sed '/^1\./s///' | cut -d'.' -f1)
if [ "$JAVA_VERSION" -lt 17 ]; then
    echo -e "${RED}Error: Java 17 or later is required. Found Java $JAVA_VERSION${NC}"
    exit 1
fi

# Check for javac (JDK compiler) - required for building
if ! command_exists javac; then
    echo -e "${RED}Error: JDK is not fully installed. Only JRE found.${NC}"
    echo -e "${YELLOW}  The Java compiler (javac) is missing. Please install the full JDK:${NC}"
    if [ "$IS_WINDOWS" = "true" ]; then
        echo -e "${YELLOW}  On Windows: winget install Microsoft.OpenJDK.25${NC}"
    else
        echo -e "${YELLOW}  On RHEL/CentOS: sudo yum install java-${JAVA_VERSION}-openjdk-devel${NC}"
        echo -e "${YELLOW}  On Ubuntu/Debian: sudo apt install openjdk-${JAVA_VERSION}-jdk${NC}"
    fi
    exit 1
fi

# On Windows, handle Java paths with spaces (Gradle requirement)
if [ "$IS_WINDOWS" = "true" ]; then
    # Determine current Java home
    if [ -z "$JAVA_HOME" ]; then
        JAVA_EXE=$(which java 2>/dev/null || command -v java 2>/dev/null)
        if [ -n "$JAVA_EXE" ]; then
            # Resolve symlinks and get real path
            if [ -L "$JAVA_EXE" ]; then
                JAVA_EXE=$(readlink -f "$JAVA_EXE" 2>/dev/null || readlink "$JAVA_EXE" 2>/dev/null || echo "$JAVA_EXE")
            fi
            # Get JAVA_HOME (parent of bin directory)
            JAVA_HOME=$(dirname "$(dirname "$JAVA_EXE")")
        fi
    fi
    
    # Check if JAVA_HOME has spaces
    if [[ "$JAVA_HOME" == *" "* ]]; then
        # Try to use symlink if it exists
        SYMLINK_PATH="/c/jdk-25"
        if [ -d "$SYMLINK_PATH" ] && [ -f "$SYMLINK_PATH/bin/java.exe" ]; then
            export JAVA_HOME="$SYMLINK_PATH"
            export PATH="$SYMLINK_PATH/bin:$PATH"
            echo -e "${GREEN}Using Java symlink to avoid spaces in path: $SYMLINK_PATH${NC}"
        else
            echo -e "${RED}Error: Java path contains spaces, which Gradle does not support.${NC}"
            echo -e "${YELLOW}  Please create a symlink (run PowerShell as Administrator):${NC}"
            echo -e "${YELLOW}  New-Item -ItemType Junction -Path \"C:\\jdk-25\" -Target \"$JAVA_HOME\"${NC}"
            echo -e "${YELLOW}  Or: mklink /J C:\\jdk-25 \"$JAVA_HOME\"${NC}"
            echo -e "${YELLOW}  Then set: export JAVA_HOME=\"/c/jdk-25\"${NC}"
            exit 1
        fi
    fi
    
    # Set Gradle to use JAVA_HOME explicitly (convert to Windows path format)
    if [ -n "$JAVA_HOME" ]; then
        # Convert Git Bash path to Windows path format for Gradle
        if [[ "$JAVA_HOME" == /c/* ]]; then
            # Convert /c/path to C:\path
            GRADLE_JAVA_HOME=$(echo "$JAVA_HOME" | sed 's|^/c/|C:|' | sed 's|/|\\|g')
        elif [[ "$JAVA_HOME" == /cygdrive/* ]]; then
            # Handle cygwin paths
            GRADLE_JAVA_HOME=$(cygpath -w "$JAVA_HOME" 2>/dev/null || echo "$JAVA_HOME")
        else
            GRADLE_JAVA_HOME="$JAVA_HOME"
        fi
        
        export GRADLE_OPTS="-Dorg.gradle.java.home=$GRADLE_JAVA_HOME ${GRADLE_OPTS}"
        echo -e "${GREEN}Setting Gradle Java home: $GRADLE_JAVA_HOME${NC}"
    fi
fi

echo -e "${GREEN}✓ Java JDK found (version $JAVA_VERSION)${NC}"

# Check Gradle
if [ -f "./gradlew" ]; then
    echo -e "${GREEN}✓ Gradle wrapper found${NC}"
    GRADLE_CMD="./gradlew"
elif command_exists gradle; then
    echo -e "${GREEN}✓ Gradle found${NC}"
    GRADLE_CMD="gradle"
else
    echo -e "${RED}Error: Gradle is not installed and gradlew not found.${NC}"
    exit 1
fi

# Update OS detection message
if [ "$IS_WINDOWS" = "true" ]; then
    echo -e "${GREEN}✓ Running on Windows${NC}"
elif [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${YELLOW}Warning: This script is designed for Linux/Windows. Cross-compilation may have limitations.${NC}"
fi

# Check for Wine (optional, for MSI building)
if command_exists wine; then
    echo -e "${GREEN}✓ Wine found (can be used for MSI building)${NC}"
    HAS_WINE=true
else
    echo -e "${YELLOW}⚠ Wine not found (optional, needed for MSI installer creation)${NC}"
    HAS_WINE=false
fi

echo ""

# Set build options
BUILD_TYPE="${BUILD_TYPE:-portable}"  # portable or installer
ARCH="${ARCH:-x86_64}"  # x86_64 or arm64

echo -e "${YELLOW}Build configuration:${NC}"
echo "  Type: $BUILD_TYPE"
echo "  Architecture: $ARCH"
echo ""

# Clean previous builds (optional)
if [ "${CLEAN_BUILD:-false}" = "true" ]; then
    echo -e "${YELLOW}Cleaning previous builds...${NC}"
    $GRADLE_CMD clean
    echo ""
fi

# Build the project
echo -e "${GREEN}Building XPipe for Windows...${NC}"
echo ""

# Important note about cross-compilation
echo -e "${YELLOW}Important:${NC}"
echo "  jpackage typically requires running on the target OS (Windows) to create"
echo "  native Windows executables and MSI installers."
echo "  This script will attempt to build, but for best results, consider:"
echo "  1. Running this script on a Windows machine, OR"
echo "  2. Using Wine for MSI creation (if available)"
echo ""

# Set build environment variables
export RELEASE="${RELEASE:-false}"
export STAGE="${STAGE:-false}"

# Apply code formatting (Spotless) to fix any formatting issues
echo -e "${YELLOW}Applying code formatting...${NC}"
if $GRADLE_CMD spotlessApply --no-daemon > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Code formatting applied${NC}"
else
    echo -e "${YELLOW}⚠ Code formatting check skipped or failed${NC}"
fi
echo ""

# First, build all JARs (platform-independent)
echo -e "${YELLOW}Building JAR files...${NC}"
$GRADLE_CMD build --no-daemon -x test
echo -e "${GREEN}✓ JAR files built${NC}"
echo ""

# Check if private_files.txt exists (required for full version with MSI)
HAS_FULL_VERSION=false
if [ -f "private_files.txt" ]; then
    HAS_FULL_VERSION=true
    echo -e "${GREEN}Full version build detected${NC}"
fi

# Build Windows executable using jpackage
# Note: jpackage may not work perfectly cross-platform, but we'll try
echo -e "${YELLOW}Building Windows executable image with jpackage...${NC}"
echo -e "${YELLOW}Note: This creates the executable structure but may need Windows for final packaging${NC}"

# Build the jpackage image
# This creates the Windows executable structure
if $GRADLE_CMD :dist:jpackageImage --no-daemon; then
    echo -e "${GREEN}✓ Windows executable image built${NC}"
    
    # The output will be in build/dist/jpackage/xpiped/
    OUTPUT_DIR="build/dist/jpackage/xpiped"
    
    if [ -d "$OUTPUT_DIR" ]; then
        echo -e "${GREEN}✓ Build output found at: $OUTPUT_DIR${NC}"
        
        # Create a zip archive for easy distribution
        if command_exists zip; then
            echo -e "${YELLOW}Creating portable zip archive...${NC}"
            ZIP_NAME="xpipe-portable-windows-${ARCH}.zip"
            cd "$OUTPUT_DIR/.."
            zip -r "$ZIP_NAME" xpiped/ > /dev/null 2>&1
            cd "$SCRIPT_DIR"
            
            if [ -f "build/dist/jpackage/$ZIP_NAME" ]; then
                echo -e "${GREEN}✓ Portable archive created: build/dist/jpackage/$ZIP_NAME${NC}"
            fi
        fi
    fi
else
    echo -e "${RED}✗ jpackage image build failed${NC}"
    echo -e "${YELLOW}This is expected if cross-compiling from Linux to Windows${NC}"
    echo -e "${YELLOW}Consider running this script on a Windows machine for full support${NC}"
fi

# Try to build MSI if on Windows or with Wine
if [ "$BUILD_TYPE" = "installer" ] && [ "$HAS_FULL_VERSION" = "true" ]; then
    echo ""
    echo -e "${YELLOW}Attempting to build MSI installer...${NC}"
    
    # Check if we're actually on Windows
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$WINDIR" ]]; then
        echo -e "${GREEN}Running on Windows - building MSI...${NC}"
        if $GRADLE_CMD :dist:buildMsi --no-daemon; then
            echo -e "${GREEN}✓ MSI installer built successfully${NC}"
        else
            echo -e "${RED}MSI build failed${NC}"
        fi
    elif [ "$HAS_WINE" = "true" ]; then
        echo -e "${YELLOW}Using Wine to build MSI (experimental)...${NC}"
        echo -e "${YELLOW}Note: This may not work perfectly. For best results, build on Windows.${NC}"
        # Wine-based build would go here, but it's complex and may not work
        echo -e "${YELLOW}Skipping MSI build with Wine (not fully supported)${NC}"
    else
        echo -e "${YELLOW}MSI build requires running on Windows or having Wine installed${NC}"
        echo -e "${YELLOW}Skipping MSI build${NC}"
    fi
fi

# Find and display output files
echo ""
echo -e "${GREEN}=== Build Summary ===${NC}"
echo ""

# Look for MSI installer
MSI_FOUND=false
if [ -f "build/dist/artifacts/xpipe-installer-windows-${ARCH}.msi" ]; then
    echo -e "${GREEN}✓ MSI Installer:${NC}"
    echo -e "    build/dist/artifacts/xpipe-installer-windows-${ARCH}.msi"
    MSI_FOUND=true
    echo ""
fi

# Look for portable zip
ZIP_FOUND=false
if [ -f "build/dist/jpackage/xpipe-portable-windows-${ARCH}.zip" ]; then
    echo -e "${GREEN}✓ Portable ZIP:${NC}"
    echo -e "    build/dist/jpackage/xpipe-portable-windows-${ARCH}.zip"
    ZIP_FOUND=true
    echo ""
fi

# Look for jpackage directory
DIR_FOUND=false
if [ -d "build/dist/jpackage/xpiped" ]; then
    echo -e "${GREEN}✓ Executable directory:${NC}"
    echo -e "    build/dist/jpackage/xpiped/"
    if [ -f "build/dist/jpackage/xpiped/xpiped.exe" ]; then
        echo -e "    Main executable: xpiped.exe"
    fi
    DIR_FOUND=true
    echo ""
fi

# Look for JAR files
JAR_FOUND=false
if [ -d "app/build/libs" ] && [ -n "$(ls -A app/build/libs/*.jar 2>/dev/null)" ]; then
    echo -e "${GREEN}✓ JAR files:${NC}"
    ls -1 app/build/libs/*.jar 2>/dev/null | head -3 | while read jar; do
        echo -e "    $jar"
    done
    JAR_FOUND=true
    echo ""
fi

if [ "$MSI_FOUND" = "true" ] || [ "$ZIP_FOUND" = "true" ] || [ "$DIR_FOUND" = "true" ]; then
    echo -e "${GREEN}Windows build completed!${NC}"
else
    echo -e "${YELLOW}Build completed, but no Windows-specific output found.${NC}"
    echo -e "${YELLOW}This may be due to cross-compilation limitations.${NC}"
fi

echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "  • jpackage typically requires running on Windows to create native executables"
echo "  • For MSI installer: Run this script on Windows with BUILD_TYPE=installer"
echo "  • For portable version: The zip/directory can be extracted and run on Windows 11"
echo "  • Full version features require private_files.txt to be present"
echo ""
echo -e "${YELLOW}Windows vs Linux Build:${NC}"
echo "  • Building on Windows is recommended for best results"
echo "  • Cross-compilation from Linux may have limitations"
echo "  • If building on Linux, you may only get JAR files or partial builds"
echo "  • For production Windows installers, use a Windows build machine"
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo "  ./build-windows.sh                    # Build portable version"
echo "  BUILD_TYPE=installer ./build-windows.sh  # Build MSI installer (Windows only)"
echo "  ARCH=arm64 ./build-windows.sh          # Build for ARM64 architecture"
echo ""
