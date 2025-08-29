# RSS Quick - Accessible WPF RSS Reader

A fast, accessible RSS reader built with WPF for efficient headline browsing. Features a clean 2-panel interface optimized for screen readers and keyboard navigation.


## Getting RSS Quick

You can download the latest version of RSS Quick in two ways:

- **GitHub Releases:**
  - Visit the [Releases page](https://github.com/kellylford/rssquick/releases) for official packages.
- **Direct Download:**
  - Download from OneDrive: [RSS Quick Packages](https://1drv.ms/f/c/a7b1bd807b044bbc/EuVL5TCSlyJNrqWJJ0SzPsEBXkHTELkLBeeIwKCwNP8epA?e=DVNkcT)

### Which Package Should I Use?

- **win-x64**: For most Intel/AMD Windows computers
- **win-arm64**: For ARM-based Windows devices (Surface Pro X, etc)

### How to Run

1. **Download** the ZIP file for your computer's architecture.
2. **Unzip** the contents to any folder (e.g., your Desktop or Documents).
3. **Run** `RSSQuick.exe` inside the unzipped folder.
   - If you do not have the .NET 8.0 Runtime installed, Windows will prompt you to download it automatically.
   - No installation is required—just unzip and run!

---
## Quick Start


1. **Run** the application (`RSSQuick.exe` or `dotnet run`)
  - By default, RSS Quick will automatically load any file named `rss.opml` in the same directory where the program is launched.
  - A default `rss.opml` file is included for you to try out right away.
2. **Import feeds**: Activate "Import OPML File" button 
3. **Browse feeds**: Use arrow keys to navigate, Enter to load headlines
4. **Read articles**: Tab to headlines, browse with arrows, Alt+B to open in browser

## Key Features

### Simple & Fast
- **2-Panel Layout**: Feeds list → Headlines list → External browser
- **No Persistent Storage**: Always fetches fresh content, no cache management
- **OPML Import**: Load comprehensive feed collections instantly
- **Lightweight**: No database overhead or complex configuration

### Smart Content Handling
- **Title Cleaning**: Automatically removes problematic characters that cause braille display issues
- **External Browser**: Articles open in your preferred browser with full accessibility
- **Feed Organization**: Hierarchical categories with clear navigation structure

## Navigation & Keyboard Shortcuts

### Tab Navigation Flow
1. **Import OPML File** button (top)
2. **RSS Feeds** tree (left panel)
3. **Headlines** list (right panel)  
4. **Open in Browser** button

### Within Each Panel
- **Arrow Keys**: Navigate items within current panel
- **Enter**: Activate selected item (load feed or open article)
- **Tab/Shift+Tab**: Move between panels
- **Alt+B**: Open selected headline in browser

### Feed Tree (Left Panel)
- **Arrow Keys**: Navigate between feeds and categories
- **Enter**: Load headlines for selected feed
- **Expand/Collapse**: Standard TreeView navigation

### Headlines List (Right Panel)
- **Arrow Keys**: Browse through headlines
- **Enter**: Open article in external browser
- **Alt+B**: Alternative to Enter for opening articles

## Status Bar Information

The status bar provides contextual information that screen readers can access:

- **Loading**: "Loading feed: BBC News..."
- **Loaded**: "Loaded 45 articles from BBC News"  
- **Navigation**: "BBC News - 12 of 45" (current position)
- **Focus Changes**: "Feed Tree - Reuters selected"

## OPML File Support

RSS Quick supports standard OPML files with hierarchical organization:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>My RSS Feeds</title>
  </head>
  <body>
    <outline text="News" title="News">
      <outline text="BBC News" title="BBC News" 
               type="rss" xmlUrl="http://feeds.bbci.co.uk/news/rss.xml"/>
      <outline text="Reuters" title="Reuters" 
               type="rss" xmlUrl="http://feeds.reuters.com/reuters/topNews"/>
    </outline>
    <outline text="Technology" title="Technology">
      <outline text="Ars Technica" title="Ars Technica" 
               type="rss" xmlUrl="http://feeds.arstechnica.com/arstechnica/index"/>
    </outline>
  </body>
</opml>
```

### Included Sample OPML
The application includes `RSS.opml` with curated feeds across categories:
- **Global News**: NYT, Guardian, Reuters, AP News
- **Technology**: General tech news, development, AI/ML
- **Science**: General science, space, medical research  
- **Culture**: Arts, books, entertainment
- **Sports**: General sports, leagues (NFL, NBA, MLB, etc.)
- **Accessibility**: Focused accessibility and inclusive design news

## Accessibility Features

### Screen Reader Support
- **Clean Announcements**: Headlines without clutter or excessive whitespace
- **Contextual Information**: Feed name and position counters in status bar
- **Logical Focus Flow**: Predictable Tab navigation between interface elements
- **Live Regions**: Status updates announced automatically

## Technical Requirements

- **Platform**: Windows 10/11 (WPF requirement)
- **Runtime**: .NET 8.0 or later
- **Network**: Internet connection for RSS feed fetching
- **Browser**: Default web browser for article viewing

### 🛠️ Development Workflow

#### Daily Development:
```bash
# Quick test
run.cmd

# Or manual
dotnet run
```

#### For Distribution:
1. **Most common**: Double-click `build-simple.cmd`
2. **Multi-platform**: Double-click `build-multi-small.cmd` 
3. **Zero-setup**: Double-click `distribute.cmd`

### 📋 Requirements

#### For Building:
- **Windows 10/11** (WPF requirement)
- **.NET 8.0 SDK** (for development)
- **Internet connection** (to restore packages)

#### For End Users:
- **Windows 10/11**
- **.NET 8.0 Runtime** (for small distributions)
- **Nothing additional** (for self-contained distributions)

**Get .NET 8.0:** https://dotnet.microsoft.com/download/dotnet/8.0

### 🚀 Complete Build Reference

All build scripts work from File Explorer (double-click) or command line:

- `run.cmd` - Quick development testing
- `build.cmd` - Advanced development options
- **`build-simple.cmd`** - Standard distribution (recommended)
- `build-multi-small.cmd` - Multi-platform small distribution  
- `distribute.cmd` - Self-contained distribution
- `distribute-small.cmd` - Single-platform small distribution

**See `HOW-TO-BUILD.md` for detailed instructions.**

## Troubleshooting

### Common Issues

**Application won't start**
- Ensure Windows 10/11 compatibility
- Install .NET 8.0 SDK if building from source

**OPML import fails**
- Verify file is valid XML format
- Check that RSS feed URLs are accessible
- Ensure file contains `type="rss"` attributes

**Headlines don't load**
- Verify internet connection
- Try different feed (some may be temporarily unavailable)
- Check that you pressed Enter on feed, not just selected it

**Navigation feels unresponsive**
- Use Tab/Shift+Tab to move between panels
- Use arrow keys within each panel
- Remember that feed selection doesn't auto-load headlines

### Accessibility Troubleshooting

**Screen reader not announcing properly**
- Check status bar for current context
- Use Insert+Page Down (NVDA/JAWS) to read status bar
- Verify focus is in expected panel

**Tab navigation issues**
- Use standard Tab/Shift+Tab for panel navigation
- Arrow keys for navigation within panels
- Avoid custom keyboard shortcuts that might interfere

## License

MIT License - See LICENSE file for details.

## Contributing

Issues and pull requests welcome. Focus areas:
- Additional RSS feed sources
- Accessibility improvements
- Performance optimizations
- Cross-platform compatibility

---

*RSS Quick v1.0 - Built for accessibility, optimized for efficiency*

## For Developers

### Prerequisites

- **Windows 10/11** (WPF is Windows-specific)
- **.NET 8.0 SDK** or later
  - Download from: https://dotnet.microsoft.com/download/dotnet/8.0
  - Choose "SDK" not just "Runtime"

### Verify Prerequisites

Open Command Prompt or PowerShell and check:

```bash
dotnet --version
```

Should show version 8.0.x or higher.

### Building the Application

#### Quick Build Scripts (Recommended)

The project includes convenient batch files for easy building:

##### `run.cmd` - Simple Build and Run
**Just launch to build and run:**
```cmd
run.cmd
```
- Builds in Release mode for optimal performance
- Runs the application immediately after building
- Shows clear error messages if build fails
- Perfect for quick testing

##### `build.cmd` - Advanced Build Options
**Multiple build modes and options:**

```cmd
# Default: Debug build and run
build.cmd

# Release build and run
build.cmd release

# Create standalone executable (no .NET required)
build.cmd publish

# Clean all build artifacts
build.cmd clean

# Show all available options
build.cmd help
```

**Key Features:**
- ✅ **Standalone Executable**: `build.cmd publish` creates `RSSQuick.exe` that runs without .NET installed
- ✅ **Error Handling**: Stops on build failures with clear messages
- ✅ **Multiple Configurations**: Debug for development, Release for distribution
- ✅ **Easy Cleanup**: `build.cmd clean` removes all build files
- ✅ **User-Friendly**: Progress messages and help documentation

**Standalone Distribution:**
```cmd
build.cmd publish
```
Creates: `bin\Release\net8.0-windows\win-x64\publish\RSSQuick.exe`
- Copy this exe anywhere and run without installing .NET
- Perfect for distributing to end users
- Self-contained with all dependencies included

#### Manual Build Options

##### Option 1: Command Line (Manual)

1. **Open Terminal/Command Prompt**
2. **Navigate to the project folder**:
   ```bash
   cd path\to\RSSReaderWPF
   ```
3. **Build the application**:
   ```bash
   dotnet build
   ```
4. **Run the application**:
   ```bash
   dotnet run
   ```

##### Option 2: Visual Studio

1. **Open** `RSSReaderWPF.csproj` in Visual Studio 2022
2. **Build** → Build Solution (Ctrl+Shift+B)
3. **Run** → Start Without Debugging (Ctrl+F5)

##### Option 3: Visual Studio Code

1. **Open** the RSSReaderWPF folder in VS Code
2. **Terminal** → New Terminal
3. **Run**:
   ```bash
   dotnet build
   dotnet run
   ```

#### Build Comparison Guide

| Method | Best For | Pros | Cons |
|--------|----------|------|------|
| `run.cmd` | **Quick testing** | One-click, Release mode, error handling | Windows only |
| `build.cmd` | **Development** | Multiple options, standalone exe, cleanup | Windows only |
| Manual dotnet | **Cross-platform** | Works everywhere, direct control | More typing |
| Visual Studio | **Full IDE** | Debugging, IntelliSense, project management | Requires VS install |
| VS Code | **Lightweight** | Fast, extensions, integrated terminal | Less IDE features |

#### Distribution Options

**For End Users:**
1. `build.cmd publish` → Creates standalone executable
2. Copy `RSSQuick.exe` + distribute
3. No .NET installation required for end users

**For Developers:**
1. Share source code + `run.cmd` for easy building
2. Use `build.cmd clean` before committing to remove build artifacts
3. `build.cmd debug` for development, `build.cmd release` for testing

### Advanced Build Commands

If you need manual control beyond the batch files:

```bash
# Manual standalone executable creation
dotnet publish -c Release -r win-x64 --self-contained true

# For 32-bit Windows  
dotnet publish -c Release -r win-x86 --self-contained true

# Clean manually
dotnet clean

# Restore packages
dotnet restore
```

**Output Location:** `bin\Release\net8.0-windows\win-x64\publish\`

### Build Troubleshooting

**"SDK not found"**:
- Install .NET 8.0 SDK from Microsoft
- Restart terminal/IDE after installation

**"Package restore failed"**:
```bash
dotnet restore
dotnet build
```

### Build Troubleshooting

**"SDK not found"**:
- Install .NET 8.0 SDK from Microsoft
- Restart terminal/IDE after installation

**"Package restore failed"**:
```bash
dotnet restore
dotnet build
```

### Project Structure

```
RSSReaderWPF/
├── MainWindow.xaml          # UI layout
├── MainWindow.xaml.cs       # Main logic and event handling
├── Models/
│   ├── Feed.cs             # Feed data model
│   ├── FeedItem.cs         # News item model
│   └── MainViewModel.cs    # MVVM view model
├── Converters/
│   └── Converters.cs       # UI value converters
└── RSSReaderWPF.csproj     # Project configuration
```

### Dependencies

- **.NET 8.0 WPF**: UI framework
- **System.ServiceModel.Syndication**: RSS/Atom parsing
- **System.Text.Json**: JSON handling
- **System.Xml**: OPML parsing

### Quick Reference for Developers

```cmd
# Quick build and run
run.cmd

# Development workflow
build.cmd debug           # Debug build and run
build.cmd release         # Release build and run  
build.cmd clean          # Clean build artifacts

# Distribution
build.cmd publish        # Create standalone executable
build.cmd help           # Show all options

# Manual commands (if needed)
dotnet build             # Build only
dotnet run               # Run only  
dotnet clean             # Clean only
dotnet restore           # Restore packages
```

**File Structure:**
- `run.cmd` → Simple one-click build and run
- `build.cmd` → Advanced build options with help
- `MainWindow.xaml` → UI layout
- `MainWindow.xaml.cs` → Main application logic
- `Models/` → Data models and MVVM classes

## License

This project is for experimentation and learning purposes.

## Support

For end users: The application is designed to be simple - just run the executable and import your OPML file.

For developers: Check .NET installation with `dotnet --version`, then `dotnet build` and `dotnet run`.
