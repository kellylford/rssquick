#!/bin/bash

echo "RSS Quick - Multi-Platform Small Distribution Build"
echo "=================================================="
echo "Creating framework-dependent packages for multiple platforms..."
echo ""

# Define platforms and base directory
platforms=("win-x64" "win-arm64")
base_dist_dir="dist-multi-small"

# Clean previous distributions
echo "[1/4] Cleaning previous distributions..."
if [ -d "$base_dist_dir" ]; then
    rm -rf "$base_dist_dir"
fi

echo "[2/4] Building for multiple platforms..."
echo ""

for platform in "${platforms[@]}"; do
    echo "Building for $platform..."
    
    platform_dir="$base_dist_dir/$platform"
    publish_dir="bin/Release/net8.0-windows/$platform/publish-small"
    
    # Clean previous build for this platform
    if [ -d "$publish_dir" ]; then
        rm -rf "$publish_dir"
    fi
    
    # Build for this platform
    dotnet publish RSSReaderWPF.csproj \
        --configuration Release \
        --runtime "$platform" \
        --self-contained false \
        --output "$publish_dir"
    
    if [ $? -ne 0 ]; then
        echo "*** BUILD FAILED for $platform ***"
        echo "Check the error messages above"
        read -p "Press Enter to exit"
        exit 1
    fi
    
    # Create distribution folder for this platform
    mkdir -p "$platform_dir"
    
    # Copy all the published files
    cp -r "$publish_dir"/* "$platform_dir/"
    
    # Copy essential files
    cp "RSS.opml" "$platform_dir/"
    cp "README.md" "$platform_dir/"
    
    # Create platform-specific run script
    cat > "$platform_dir/Run-RSSQuick.cmd" << EOF
@echo off
echo Starting RSS Quick for $platform...
echo Note: This requires .NET 8.0 Runtime for $platform
start "" "RSSQuick.exe"
EOF
    
    # Create platform-specific instructions
    if [ "$platform" = "win-x64" ]; then
        arch_description="Intel/AMD processors (most common)"
    else
        arch_description="ARM64 processors (Surface, newer laptops)"
    fi
    
    cat > "$platform_dir/DISTRIBUTION-README.txt" << EOF
RSS Quick - Small Distribution ($platform)
=====================================

This version is built for $arch_description.

SYSTEM REQUIREMENTS:
- Windows 10/11 on $platform
- .NET 8.0 Runtime for $platform
- Download from: https://dotnet.microsoft.com/download/dotnet/8.0
- Choose "Runtime" not "SDK"
- Select the $platform version

HOW TO RUN:
1. Install .NET 8.0 Runtime for $platform if not already installed
2. Double-click "RSSQuick.exe"
3. Or use "Run-RSSQuick.cmd"

For support: https://github.com/kellylford/rssquick
EOF
    
    echo "✓ Completed $platform distribution"
    echo ""
done

echo "[3/4] Creating helper files..."

# Create main README
cat > "$base_dist_dir/README-CHOOSE-YOUR-PLATFORM.txt" << EOF
RSS Quick - Multi-Platform Small Distribution
==============================================

This package contains RSS Quick for multiple processor types.
Choose the folder that matches your computer:

FOLDERS:

win-x64/     - For Intel/AMD processors (most common)
             - Most desktop PCs, older laptops

win-arm64/   - For ARM64 processors  
             - Surface devices, newer laptops

HOW TO CHOOSE:
1. Try win-x64/ first (works for most people)
2. If it asks for .NET download, try win-arm64/
3. Each folder has its own installation instructions

INSTALLATION:
1. Choose your platform folder
2. Read the DISTRIBUTION-README.txt in that folder
3. Install .NET Runtime if prompted
4. Run RSSQuick.exe

For support: https://github.com/kellylford/rssquick
EOF

echo "[4/4] Multi-platform distribution complete!"
echo ""
echo "*** SUCCESS! ***"
echo ""
echo "Multi-platform distribution created in: $base_dist_dir/"
echo ""

# Show contents
echo "Package structure:"
ls -la "$base_dist_dir/"
echo ""

# Show sizes
echo "Platform sizes:"
for platform in "${platforms[@]}"; do
    size=$(du -sh "$base_dist_dir/$platform" | cut -f1)
    echo "  $platform: $size"
done

echo ""
echo "DISTRIBUTION READY:"
echo "- win-x64/     - For Intel/AMD computers"
echo "- win-arm64/   - For ARM64 computers"
echo "- README-CHOOSE-YOUR-PLATFORM.txt - User instructions"
echo ""
echo "Multi-platform distribution build complete!"
