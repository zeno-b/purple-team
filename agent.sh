#!/bin/bash

################################################################################
# Purple Team Agent - WSL to Windows Host
# Version: 3.0
# Description: Red team simulation for purple team security exercises
# Usage: ./purple_agent.sh [options]
################################################################################

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="3.0"
readonly LOG_FILE="/tmp/redteam_agent_$(date +%Y%m%d_%H%M%S).log"
readonly JSON_LOG="/tmp/redteam_agent_$(date +%Y%m%d_%H%M%S).json"
readonly WINDOWS_SYSTEM="/mnt/c"
readonly TIMEOUT_SECONDS=30

# Terminal color codes for readable output
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_MAGENTA='\033[0;35m'
readonly C_CYAN='\033[0;36m'
readonly C_WHITE='\033[1;37m'
readonly C_GRAY='\033[0;90m'
readonly C_RESET='\033[0m'

# Status symbols for output clarity
readonly SYM_SUCCESS="✓"
readonly SYM_FAIL="✗"
readonly SYM_WARN="⚠"
readonly SYM_INFO="ℹ"
readonly SYM_ACTION="⚡"

# Track execution statistics
TOTAL_ACTIONS=0
SUCCESSFUL_ACTIONS=0
FAILED_ACTIONS=0
START_TIME=$(date +%s)

# Environment detection results
WSL_VERSION=""
POWERSHELL_CMD=""

# ============================================================================
# HELP AND USAGE
# ============================================================================

show_help() {
    echo -e "${C_CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════╗
║                     PURPLE TEAM AGENT v3.0                               ║
║              WSL to Windows Host Red Team Simulation                     ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
    echo ""
    echo -e "${C_WHITE}USAGE:${C_RESET}"
    echo "    $0 [OPTIONS]"
    echo ""
    echo -e "${C_WHITE}OPTIONS:${C_RESET}"
    echo -e "    ${C_GREEN}-h, --help${C_RESET}              Show this help message"
    echo -e "    ${C_GREEN}-a, --all${C_RESET}               Run all phases (default)"
    echo -e "    ${C_GREEN}-p, --phase <number>${C_RESET}    Run a specific phase (1-11)"
    echo -e "    ${C_GREEN}-l, --list${C_RESET}              List all available phases"
    echo -e "    ${C_GREEN}-q, --quiet${C_RESET}             Minimal output (logs only)"
    echo -e "    ${C_GREEN}-v, --verbose${C_RESET}           Verbose output with details"
    echo ""
    echo -e "${C_WHITE}PHASES:${C_RESET}"
    echo -e "    ${C_CYAN}Phase 1${C_RESET}  - System Information Discovery (T1082)"
    echo -e "    ${C_CYAN}Phase 2${C_RESET}  - Account Discovery (T1087)"
    echo -e "    ${C_CYAN}Phase 3${C_RESET}  - Process Discovery (T1057)"
    echo -e "    ${C_CYAN}Phase 4${C_RESET}  - File and Directory Discovery (T1083)"
    echo -e "    ${C_CYAN}Phase 5${C_RESET}  - Credential Search (T1552.001)"
    echo -e "    ${C_CYAN}Phase 6${C_RESET}  - Registry Enumeration (T1012, T1518)"
    echo -e "    ${C_CYAN}Phase 7${C_RESET}  - Network Discovery (T1049, T1018, T1135)"
    echo -e "    ${C_CYAN}Phase 8${C_RESET}  - Automated Collection (T1119)"
    echo -e "    ${C_CYAN}Phase 9${C_RESET}  - Persistence Reconnaissance (T1547, T1053)"
    echo -e "    ${C_CYAN}Phase 10${C_RESET} - Ransomware-like Behavior (T1486, T1490, T1489)"
    echo -e "    ${C_CYAN}Phase 11${C_RESET} - EICAR AV Detection Test"
    echo ""
    echo -e "${C_WHITE}EXAMPLES:${C_RESET}"
    echo "    # Run all phases"
    echo "    $0 --all"
    echo ""
    echo "    # Run only phase 1"
    echo "    $0 --phase 1"
    echo ""
    echo "    # Run phases 1, 5, and 11"
    echo "    $0 --phase 1,5,11"
    echo ""
    echo "    # List all phases"
    echo "    $0 --list"
    echo ""
    echo -e "${C_WHITE}OUTPUT:${C_RESET}"
    echo -e "    ${C_YELLOW}Screen:${C_RESET}      Color-coded real-time output"
    echo -e "    ${C_YELLOW}Text Log:${C_RESET}    Professional formatted log"
    echo -e "    ${C_YELLOW}JSON Log:${C_RESET}    Machine-readable log"
    echo ""
    echo -e "${C_WHITE}NOTES:${C_RESET}"
    echo "    - This script is for authorized purple team exercises only"
    echo "    - All actions are logged for blue team analysis"
    echo "    - EICAR test files are safe and standard for AV testing"
    echo "    - Ransomware phase performs reconnaissance only (no encryption)"
    echo ""
}

list_phases() {
    echo -e "${C_CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════╗
║                        AVAILABLE PHASES                                  ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
    echo ""
    echo -e "${C_WHITE}[1]${C_RESET}  ${C_GREEN}System Information Discovery${C_RESET}"
    echo "     MITRE ATT&CK: T1082"
    echo "     Description: Enumerate OS version, patches, security products"
    echo "     Duration: ~15 seconds"
    echo ""
    echo -e "${C_WHITE}[2]${C_RESET}  ${C_GREEN}Account Discovery${C_RESET}"
    echo "     MITRE ATT&CK: T1087.001, T1087.002"
    echo "     Description: List local users, groups, and privileges"
    echo "     Duration: ~20 seconds"
    echo ""
    echo -e "${C_WHITE}[3]${C_RESET}  ${C_GREEN}Process Discovery${C_RESET}"
    echo "     MITRE ATT&CK: T1057, T1007"
    echo "     Description: Enumerate running processes and services"
    echo "     Duration: ~15 seconds"
    echo ""
    echo -e "${C_WHITE}[4]${C_RESET}  ${C_GREEN}File and Directory Discovery${C_RESET}"
    echo "     MITRE ATT&CK: T1083"
    echo "     Description: Search for sensitive files and directories"
    echo "     Duration: ~25 seconds"
    echo ""
    echo -e "${C_WHITE}[5]${C_RESET}  ${C_GREEN}Credential Search${C_RESET}"
    echo "     MITRE ATT&CK: T1552.001, T1555.003"
    echo "     Description: Hunt for passwords and credential stores"
    echo "     Duration: ~30 seconds"
    echo ""
    echo -e "${C_WHITE}[6]${C_RESET}  ${C_GREEN}Registry Enumeration${C_RESET}"
    echo "     MITRE ATT&CK: T1012, T1518"
    echo "     Description: Query registry for software and persistence"
    echo "     Duration: ~20 seconds"
    echo ""
    echo -e "${C_WHITE}[7]${C_RESET}  ${C_GREEN}Network Discovery${C_RESET}"
    echo "     MITRE ATT&CK: T1049, T1018, T1135, T1016"
    echo "     Description: Map network topology and connections"
    echo "     Duration: ~25 seconds"
    echo ""
    echo -e "${C_WHITE}[8]${C_RESET}  ${C_GREEN}Automated Collection${C_RESET}"
    echo "     MITRE ATT&CK: T1119"
    echo "     Description: Collect files for exfiltration"
    echo "     Duration: ~20 seconds"
    echo ""
    echo -e "${C_WHITE}[9]${C_RESET}  ${C_GREEN}Persistence Reconnaissance${C_RESET}"
    echo "     MITRE ATT&CK: T1547, T1053, T1543"
    echo "     Description: Identify persistence mechanisms"
    echo "     Duration: ~15 seconds"
    echo ""
    echo -e "${C_WHITE}[10]${C_RESET} ${C_MAGENTA}Ransomware-like Behavior${C_RESET}"
    echo "     MITRE ATT&CK: T1486, T1490, T1489"
    echo "     Description: Simulate ransomware TTPs (no encryption)"
    echo "     Duration: ~30 seconds"
    echo -e "     ${C_YELLOW}Note: Creates indicators only, no actual encryption${C_RESET}"
    echo ""
    echo -e "${C_WHITE}[11]${C_RESET} ${C_CYAN}EICAR AV Detection Test${C_RESET}"
    echo "     Description: Test antivirus detection capabilities"
    echo "     Duration: ~20 seconds"
    echo -e "     ${C_YELLOW}Note: Uses safe EICAR test files${C_RESET}"
    echo ""
    echo -e "${C_GRAY}Total estimated time for all phases: ~4-5 minutes${C_RESET}"
    echo ""
}

# ============================================================================
# LOGGING FUNCTIONS
# These functions handle dual output: colorful terminal and structured logs
# ============================================================================

# Write structured entry to the main log file
log_to_file() {
    local level="$1"
    local technique="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] [${technique:-GENERAL}] $message" >> "$LOG_FILE"
}

# Append JSON-formatted entry for machine parsing
log_to_json() {
    local status="$1"
    local technique="$2"
    local description="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat >> "$JSON_LOG" <<EOF
{
  "timestamp": "$timestamp",
  "status": "$status",
  "technique": "$technique",
  "description": "$description",
  "execution_time": "$(($(date +%s) - START_TIME))"
},
EOF
}

# Print success message to terminal and log it
print_success() {
    local message="$1"
    local technique="${2:-INFO}"
    echo -e "${C_GREEN}[${SYM_SUCCESS}]${C_RESET} ${C_WHITE}$message${C_RESET}"
    log_to_file "SUCCESS" "$technique" "$message"
    log_to_json "SUCCESS" "$technique" "$message"
    ((SUCCESSFUL_ACTIONS++))
}

# Print error message to terminal and log it
print_error() {
    local message="$1"
    local technique="${2:-ERROR}"
    echo -e "${C_RED}[${SYM_FAIL}]${C_RESET} ${C_RED}$message${C_RESET}"
    log_to_file "ERROR" "$technique" "$message"
    log_to_json "FAILED" "$technique" "$message"
    ((FAILED_ACTIONS++))
}

# Print warning message to terminal and log it
print_warning() {
    local message="$1"
    local technique="${2:-WARN}"
    echo -e "${C_YELLOW}[${SYM_WARN}]${C_RESET} ${C_YELLOW}$message${C_RESET}"
    log_to_file "WARNING" "$technique" "$message"
}

# Print informational message to terminal and log it
print_info() {
    local message="$1"
    local technique="${2:-INFO}"
    echo -e "${C_CYAN}[${SYM_INFO}]${C_RESET} ${C_GRAY}$message${C_RESET}"
    log_to_file "INFO" "$technique" "$message"
}

# Print action message indicating something is being executed
print_action() {
    local message="$1"
    local technique="${2:-ACTION}"
    echo -e "${C_MAGENTA}[${SYM_ACTION}]${C_RESET} ${C_MAGENTA}$message${C_RESET}"
    log_to_file "ACTION" "$technique" "$message"
}

# Print a phase section header with visual separation
print_section() {
    local title="$1"
    local technique="$2"
    echo ""
    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET} ${C_WHITE}$title${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET} ${C_GRAY}MITRE ATT&CK: $technique${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    
    # Write structured header to log file
    log_to_file "PHASE_START" "$technique" "$title"
    {
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "PHASE: $title"
        echo "MITRE ATT&CK: $technique"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    } >> "$LOG_FILE"
}

# ============================================================================
# UTILITY FUNCTIONS
# Helper functions for file operations and searching
# ============================================================================

# Safely search for files with timeout and result limiting
safe_find() {
    local path="$1"
    local pattern="$2"
    local max_results="${3:-20}"
    
    # Return early if directory doesn't exist
    [ ! -d "$path" ] && return 1
    
    # Search with 10 second timeout and limit results
    timeout 10 find "$path" -type f -name "$pattern" 2>/dev/null | head -n "$max_results"
}

# Safely search file contents with timeout and result limiting
safe_grep() {
    local pattern="$1"
    local path="$2"
    local max_results="${3:-10}"
    
    # Return early if directory doesn't exist
    [ ! -d "$path" ] && return 1
    
    # Search with 10 second timeout and limit results
    timeout 10 grep -r -i -l "$pattern" "$path" 2>/dev/null | head -n "$max_results"
}

# ============================================================================
# POWERSHELL EXECUTION WRAPPER
# This function handles all PowerShell command execution with proper
# error handling, timeouts, and logging
# ============================================================================

execute_powershell() {
    local command="$1"
    local technique="$2"
    local description="$3"
    
    ((TOTAL_ACTIONS++))
    
    print_action "$description"
    
    # Create temporary files for capturing output and errors
    local temp_output=$(mktemp)
    local temp_error=$(mktemp)
    local exit_code=0
    
    # Execute PowerShell command with timeout
    if timeout $TIMEOUT_SECONDS $POWERSHELL_CMD -NoProfile -NonInteractive -Command "$command" > "$temp_output" 2> "$temp_error"; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Check if execution was successful and produced output
    if [ $exit_code -eq 0 ] && [ -s "$temp_output" ]; then
        print_success "$description completed" "$technique"
        
        # Write structured output to log file
        {
            echo "  ┌─ Action: $description"
            echo "  │  Technique: $technique"
            echo "  │  Status: SUCCESS"
            echo "  │  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "  │"
            echo "  │  Output:"
            sed 's/^/  │    /' "$temp_output"
            echo "  └─"
            echo ""
        } >> "$LOG_FILE"
        
        rm -f "$temp_output" "$temp_error"
        return 0
    else
        # Determine specific error message
        local error_msg="Failed"
        [ -s "$temp_error" ] && error_msg="$(head -1 "$temp_error")"
        [ $exit_code -eq 124 ] && error_msg="Timeout (${TIMEOUT_SECONDS}s)"
        
        print_error "$description failed: $error_msg" "$technique"
        
        # Write error details to log file
        {
            echo "  ┌─ Action: $description"
            echo "  │  Technique: $technique"
            echo "  │  Status: FAILED"
            echo "  │  Error: $error_msg"
            echo "  │  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "  └─"
            echo ""
        } >> "$LOG_FILE"
        
        rm -f "$temp_output" "$temp_error"
        return 1
    fi
}

# ============================================================================
# ENVIRONMENT DETECTION
# Verify we're running in WSL and can access Windows and PowerShell
# ============================================================================

detect_environment() {
    print_section "Environment Detection" "T1082"
    
    # Check if running in WSL by examining /proc/version
    if grep -qi microsoft /proc/version; then
        if grep -qi "WSL2" /proc/version; then
            WSL_VERSION="WSL2"
        else
            WSL_VERSION="WSL1"
        fi
        print_success "Running on $WSL_VERSION" "T1082"
    else
        print_error "Not running in WSL environment" "T1082"
        exit 1
    fi
    
    # Locate Windows filesystem mount point
    if [ ! -d "$WINDOWS_SYSTEM" ]; then
        print_warning "Standard mount /mnt/c not found, searching for Windows filesystem..."
        for mount in /mnt/*; do
            if [ -d "$mount/Windows" ]; then
                WINDOWS_SYSTEM="$mount"
                print_info "Found Windows at: $WINDOWS_SYSTEM"
                break
            fi
        done
        
        if [ ! -d "$WINDOWS_SYSTEM/Windows" ]; then
            print_error "Cannot locate Windows filesystem" "T1082"
            exit 1
        fi
    fi
    
    print_success "Windows filesystem accessible: $WINDOWS_SYSTEM" "T1082"
    
    # Determine which PowerShell executable is available
    if command -v powershell.exe &> /dev/null; then
        POWERSHELL_CMD="powershell.exe"
        print_success "PowerShell.exe detected" "T1082"
    elif command -v pwsh.exe &> /dev/null; then
        POWERSHELL_CMD="pwsh.exe"
        print_success "PowerShell Core detected" "T1082"
    else
        print_error "No PowerShell executable found" "T1082"
        exit 1
    fi
    
    # Test that PowerShell actually works
    if ! timeout $TIMEOUT_SECONDS $POWERSHELL_CMD -Command "Write-Output 'test'" &> /dev/null; then
        print_error "PowerShell execution test failed" "T1082"
        exit 1
    fi
    
    print_success "PowerShell execution verified" "T1082"
}

# ============================================================================
# PHASE 1: SYSTEM INFORMATION DISCOVERY
# Gather information about the target Windows system
# ============================================================================

phase_system_discovery() {
    print_section "PHASE 1: System Information Discovery" "T1082"
    
    # Get basic OS version information
    execute_powershell \
        "[System.Environment]::OSVersion | Format-List" \
        "T1082" \
        "Querying Windows OS version"
    
    # Get detailed computer information
    execute_powershell \
        "Get-ComputerInfo | Select-Object CsName,WindowsVersion,OsArchitecture,OsTotalVisibleMemorySize | Format-List" \
        "T1082" \
        "Collecting system information"
    
    # Check Windows Defender status
    execute_powershell \
        "Get-MpComputerStatus | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,IoavProtectionEnabled | Format-List" \
        "T1082" \
        "Checking Windows Defender status"
    
    # List recent security patches
    execute_powershell \
        "Get-HotFix | Select-Object -First 10 HotFixID,Description,InstalledOn | Format-Table" \
        "T1082" \
        "Enumerating installed hotfixes"
    
    # Check how long system has been running
    execute_powershell \
        "(Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime" \
        "T1082" \
        "Checking system uptime"
}

# ============================================================================
# PHASE 2: ACCOUNT DISCOVERY
# Enumerate user accounts, groups, and privileges
# ============================================================================

phase_account_discovery() {
    print_section "PHASE 2: Account Discovery" "T1087"
    
    # List all local user accounts
    execute_powershell \
        "Get-LocalUser | Select-Object Name,Enabled,LastLogon,PasswordLastSet | Format-Table -AutoSize" \
        "T1087.001" \
        "Enumerating local user accounts"
    
    # Get detailed information about current user
    execute_powershell \
        "whoami /all" \
        "T1087" \
        "Gathering current user privileges"
    
    # List members of local Administrators group
    execute_powershell \
        "Get-LocalGroupMember -Group 'Administrators' 2>\$null" \
        "T1087.001" \
        "Enumerating local administrators"
    
    # List all local groups
    execute_powershell \
        "Get-LocalGroup | Select-Object Name,Description | Format-Table" \
        "T1087.001" \
        "Enumerating local groups"
    
    # Check if system is joined to a domain
    execute_powershell \
        "(Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain" \
        "T1087.002" \
        "Checking domain membership status"
}

# ============================================================================
# PHASE 3: PROCESS DISCOVERY
# Identify running processes and services
# ============================================================================

phase_process_discovery() {
    print_section "PHASE 3: Process Discovery" "T1057"
    
    # List all running processes
    execute_powershell \
        "Get-Process | Select-Object Name,Id,Path,Company | Sort-Object Name | Format-Table -AutoSize" \
        "T1057" \
        "Listing all running processes"
    
    # Specifically look for security software
    execute_powershell \
        "Get-Process | Where-Object {\$_.Name -match 'defender|msmpeng|mssense|windefend|sense|av|edr|crowdstrike|carbon|sentinel|sophos|symantec|mcafee|kaspersky|avast|avg'} | Select-Object Name,Id,Path | Format-Table" \
        "T1057" \
        "Identifying security software processes"
    
    # List running Windows services
    execute_powershell \
        "Get-Service | Where-Object {\$_.Status -eq 'Running'} | Select-Object Name,DisplayName,Status | Format-Table -AutoSize" \
        "T1007" \
        "Enumerating running services"
}

# ============================================================================
# PHASE 4: FILE AND DIRECTORY DISCOVERY
# Search for interesting files and directories
# ============================================================================

phase_file_discovery() {
    print_section "PHASE 4: File and Directory Discovery" "T1083"
    
    ((TOTAL_ACTIONS++))
    print_action "Searching for interesting files in user directories..."
    
    local found_files=0
    local search_patterns=("*.txt" "*.pdf" "*.doc" "*.docx" "*.xls" "*.xlsx")
    local search_locations=(
        "$WINDOWS_SYSTEM/Users/*/Desktop"
        "$WINDOWS_SYSTEM/Users/*/Documents"
        "$WINDOWS_SYSTEM/Users/*/Downloads"
    )
    
    # Start logging file discovery results
    {
        echo "  ┌─ File Discovery Results"
        echo "  │"
    } >> "$LOG_FILE"
    
    # Search each location for each file pattern
    for location in "${search_locations[@]}"; do
        if [ -d "$location" ]; then
            for pattern in "${search_patterns[@]}"; do
                while IFS= read -r file; do
                    echo "  │  [FOUND] $file" >> "$LOG_FILE"
                    ((found_files++))
                done < <(safe_find "$location" "$pattern" 10)
            done
        fi
    done
    
    # Close file discovery log section
    {
        echo "  │"
        echo "  │  Total files found: $found_files"
        echo "  └─"
        echo ""
    } >> "$LOG_FILE"
    
    if [ $found_files -gt 0 ]; then
        print_success "Found $found_files interesting files" "T1083"
    else
        print_error "No accessible files found" "T1083"
    fi
    
    # Search for SSH keys which may contain credentials
    ((TOTAL_ACTIONS++))
    print_action "Searching for SSH keys..."
    
    local ssh_found=0
    for ssh_dir in "$WINDOWS_SYSTEM/Users/"*/.ssh; do
        if [ -d "$ssh_dir" ]; then
            {
                echo "  ┌─ SSH Directory Found"
                echo "  │  Location: $ssh_dir"
                echo "  │  Contents:"
                ls -la "$ssh_dir" 2>/dev/null | sed 's/^/  │    /'
                echo "  └─"
                echo ""
            } >> "$LOG_FILE"
            ((ssh_found++))
        fi
    done
    
    if [ $ssh_found -gt 0 ]; then
        print_success "Found $ssh_found SSH directories" "T1083"
    else
        print_info "No SSH directories found"
        ((FAILED_ACTIONS++))
    fi
}

# ============================================================================
# PHASE 5: CREDENTIAL SEARCH
# Hunt for passwords and credential stores
# ============================================================================

phase_credential_search() {
    print_section "PHASE 5: Credential Search" "T1552.001"
    
    ((TOTAL_ACTIONS++))
    print_action "Hunting for credentials in files..."
    
    # Common keywords that indicate credential information
    local cred_keywords=("password" "passwd" "pwd" "credential" "secret" "token" "api_key")
    local found_creds=0
    
    {
        echo "  ┌─ Credential Search Results"
        echo "  │"
    } >> "$LOG_FILE"
    
    # Search for files containing credential keywords
    for keyword in "${cred_keywords[@]}"; do
        while IFS= read -r file; do
            echo "  │  [POTENTIAL] $file (keyword: $keyword)" >> "$LOG_FILE"
            ((found_creds++))
        done < <(safe_grep "$keyword" "$WINDOWS_SYSTEM/Users/*/Documents" 5)
    done
    
    {
        echo "  │"
        echo "  │  Total potential credential files: $found_creds"
        echo "  └─"
        echo ""
    } >> "$LOG_FILE"
    
    if [ $found_creds -gt 0 ]; then
        print_success "Found $found_creds potential credential files" "T1552.001"
    else
        print_info "No credential files found"
        ((FAILED_ACTIONS++))
    fi
    
    # Check for Chrome's credential database
    execute_powershell \
        "Get-ChildItem 'C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Login Data' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime" \
        "T1555.003" \
        "Checking for Chrome credential database"
    
    # Check for PowerShell command history which may contain credentials
    execute_powershell \
        "Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime" \
        "T1552.001" \
        "Checking for PowerShell history file"
}

# ============================================================================
# PHASE 6: REGISTRY ENUMERATION
# Query Windows Registry for software and persistence mechanisms
# ============================================================================

phase_registry_query() {
    print_section "PHASE 6: Registry Enumeration" "T1012, T1518"
    
    # List installed software from registry
    execute_powershell \
        "Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate | Where-Object {\$_.DisplayName} | Sort-Object DisplayName | Format-Table -AutoSize" \
        "T1518" \
        "Enumerating installed software from registry"
    
    # Check system-wide Run key for persistence
    execute_powershell \
        "Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List" \
        "T1012" \
        "Checking HKLM Run registry key"
    
    # Check user-specific Run key for persistence
    execute_powershell \
        "Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List" \
        "T1012" \
        "Checking HKCU Run registry key"
    
    # Get Windows version details from registry
    execute_powershell \
        "Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName,CurrentVersion,CurrentBuild | Format-List" \
        "T1012" \
        "Querying Windows version from registry"
}

# ============================================================================
# PHASE 7: NETWORK DISCOVERY
# Map network configuration and active connections
# ============================================================================

phase_network_discovery() {
    print_section "PHASE 7: Network Discovery" "T1049, T1018, T1135"
    
    # List all established network connections
    execute_powershell \
        "Get-NetTCPConnection | Where-Object {\$_.State -eq 'Established'} | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess | Format-Table -AutoSize" \
        "T1049" \
        "Enumerating established network connections"
    
    # List network adapters
    execute_powershell \
        "Get-NetAdapter | Select-Object Name,Status,MacAddress,LinkSpeed | Format-Table" \
        "T1016" \
        "Enumerating network adapters"
    
    # Get IP configuration for each adapter
    execute_powershell \
        "Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv6Address,DNSServer | Format-List" \
        "T1016" \
        "Getting IP configuration"
    
    # List SMB shares on the system
    execute_powershell \
        "Get-SmbShare | Select-Object Name,Path,Description | Format-Table" \
        "T1135" \
        "Enumerating SMB shares"
    
    # Display ARP cache (local network hosts)
    execute_powershell \
        "Get-NetNeighbor | Where-Object {\$_.State -ne 'Unreachable'} | Select-Object IPAddress,LinkLayerAddress,State | Format-Table" \
        "T1018" \
        "Displaying ARP cache"
    
    # Display DNS cache (recently resolved hostnames)
    execute_powershell \
        "Get-DnsClientCache | Select-Object -First 20 Entry,RecordName,Status | Format-Table" \
        "T1016" \
        "Displaying DNS client cache"
}

# ============================================================================
# PHASE 8: AUTOMATED COLLECTION
# Collect files that could be exfiltrated
# ============================================================================

phase_automated_collection() {
    print_section "PHASE 8: Automated Collection" "T1119"
    
    ((TOTAL_ACTIONS++))
    
    # Create directory to store collected files
    local collection_dir="/tmp/collected_data_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$collection_dir" 2>/dev/null
    
    if [ ! -d "$collection_dir" ]; then
        print_error "Failed to create collection directory" "T1119"
        return 1
    fi
    
    print_action "Collecting files to: $collection_dir"
    
    local collected_count=0
    local file_size_limit=10240  # Only collect files smaller than 10KB
    
    {
        echo "  ┌─ Automated Collection"
        echo "  │  Target Directory: $collection_dir"
        echo "  │"
        echo "  │  Collected Files:"
    } >> "$LOG_FILE"
    
    # Copy small text files from Desktop
    for file in $(safe_find "$WINDOWS_SYSTEM/Users/*/Desktop" "*.txt" 5); do
        if [ -f "$file" ] && [ -r "$file" ]; then
            local size=$(stat -c%s "$file" 2>/dev/null || echo 999999)
            if [ "$size" -lt "$file_size_limit" ]; then
                cp "$file" "$collection_dir/" 2>/dev/null && {
                    echo "  │    [COLLECTED] $file ($size bytes)" >> "$LOG_FILE"
                    ((collected_count++))
                }
            fi
        fi
    done
    
    {
        echo "  │"
        echo "  │  Total collected: $collected_count files"
        echo "  └─"
        echo ""
    } >> "$LOG_FILE"
    
    if [ $collected_count -gt 0 ]; then
        print_success "Collected $collected_count files" "T1119"
    else
        print_error "No files collected (may indicate access restrictions)" "T1119"
        rmdir "$collection_dir" 2>/dev/null
    fi
}

# ============================================================================
# PHASE 9: PERSISTENCE RECONNAISSANCE
# Identify common persistence mechanisms
# ============================================================================

phase_persistence_recon() {
    print_section "PHASE 9: Persistence Reconnaissance" "T1547, T1053"
    
    # Check user startup folders
    execute_powershell \
        "Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup' -ErrorAction SilentlyContinue | Select-Object FullName,LastWriteTime" \
        "T1547.001" \
        "Checking user startup folders"
    
    # List scheduled tasks
    execute_powershell \
        "Get-ScheduledTask | Where-Object {\$_.State -eq 'Ready'} | Select-Object TaskName,TaskPath,State | Format-Table -AutoSize" \
        "T1053.005" \
        "Enumerating scheduled tasks"
    
    # List services that auto-start
    execute_powershell \
        "Get-Service | Where-Object {\$_.StartType -eq 'Automatic' -and \$_.Status -eq 'Running'} | Select-Object -First 20 Name,DisplayName,StartType | Format-Table" \
        "T1543.003" \
        "Enumerating auto-start services"
}

# ============================================================================
# PHASE 10: RANSOMWARE-LIKE BEHAVIOR
# Simulate ransomware reconnaissance without actually encrypting anything
# ============================================================================

phase_ransomware_behavior() {
    print_section "PHASE 10: Ransomware-like Behavior ${C_YELLOW}(Simulation Only)${C_RESET}" "T1486, T1490, T1489"
    
    print_warning "Ransomware TTP demonstration - NO ACTUAL ENCRYPTION WILL OCCUR"
    echo ""
    
    # Check for Volume Shadow Copies (ransomware typically deletes these)
    print_action "T1490: Checking for shadow copies"
    execute_powershell \
        "Get-WmiObject Win32_ShadowCopy | Select-Object ID,VolumeName,InstallDate | Format-Table" \
        "T1490" \
        "Enumerating Volume Shadow Copies"
    
    # Check Windows backup status
    execute_powershell \
        "Get-WBSummary -ErrorAction SilentlyContinue | Select-Object LastSuccessfulBackupTime,LastBackupTime,NextBackupTime | Format-List" \
        "T1490" \
        "Checking Windows backup status"
    
    # Identify backup-related services that ransomware might stop
    print_action "T1489: Identifying backup services"
    execute_powershell \
        "Get-Service | Where-Object {\$_.Name -match 'backup|vss|sql|exchange|vmware|veeam'} | Select-Object Name,DisplayName,Status,StartType | Format-Table" \
        "T1489" \
        "Enumerating backup-related services"
    
    # Enumerate files that ransomware typically targets
    print_action "T1486: Enumerating potential encryption targets"
    ((TOTAL_ACTIONS++))
    
    {
        echo "  ┌─ Ransomware Target Enumeration"
        echo "  │  NOTE: File enumeration only - NO ENCRYPTION WILL BE PERFORMED"
        echo "  │"
    } >> "$LOG_FILE"
    
    # File extensions commonly targeted by ransomware
    local target_extensions=("*.docx" "*.xlsx" "*.pdf" "*.jpg" "*.png" "*.pptx" "*.zip")
    local target_count=0
    
    for ext in "${target_extensions[@]}"; do
        for location in "$WINDOWS_SYSTEM/Users/*/Documents" "$WINDOWS_SYSTEM/Users/*/Desktop"; do
            if [ -d "$location" ]; then
                while IFS= read -r file; do
                    echo "  │  [TARGET] $file" >> "$LOG_FILE"
                    ((target_count++))
                done < <(safe_find "$location" "$ext" 10)
            fi
        done
    done
    
    {
        echo "  │"
        echo "  │  Total targets identified: $target_count"
        echo "  └─"
        echo ""
    } >> "$LOG_FILE"
    
    if [ $target_count -gt 0 ]; then
        print_success "Identified $target_count potential targets" "T1486"
    else
        print_error "No target files identified" "T1486"
    fi
    
    # Create a ransom note as an indicator (clearly marked as simulation)
    print_action "T1486: Creating ransom note indicator"
    ((TOTAL_ACTIONS++))
    
    local ransom_note="/tmp/RANSOMWARE_NOTE_PURPLETEAM.txt"
    cat > "$ransom_note" <<'RANSOMNOTE'
╔══════════════════════════════════════════════════════════════╗
║          PURPLE TEAM EXERCISE INDICATOR                      ║
║             RANSOMWARE NOTE SIMULATION                       ║
╚══════════════════════════════════════════════════════════════╝

⚠ THIS IS A SIMULATED RANSOMWARE NOTE FOR TRAINING ⚠

NO FILES HAVE BEEN ENCRYPTED.
NO DATA HAS BEEN HARMED.
THIS IS A PURPLE TEAM SECURITY EXERCISE.

In a real ransomware attack, this note would contain:
  • Information about encrypted files
  • Payment instructions (Bitcoin address)
  • Threats and deadlines
  • Contact information for "support"

Blue Team Detection Opportunities:
  ✓ File creation in unusual locations
  ✓ Suspicious file naming patterns
  ✓ Text file creation across multiple directories
  ✓ Unusual process behavior (WSL spawning PowerShell)

MITRE ATT&CK Technique: T1486 (Data Encrypted for Impact)
Purple Team Exercise Timestamp: $(date '+%Y-%m-%d %H:%M:%S')

For questions about this exercise, contact your security team.
RANSOMNOTE
    
    if [ -f "$ransom_note" ]; then
        print_success "Ransom note indicator created at $ransom_note" "T1486"
        {
            echo "  ┌─ Ransom Note Created"
            echo "  │  Location: $ransom_note"
            echo "  │"
            echo "  │  Content:"
            sed 's/^/  │    /' "$ransom_note"
            echo "  └─"
            echo ""
        } >> "$LOG_FILE"
    else
        print_error "Failed to create ransom note indicator" "T1486"
    fi
    
    # Check event log configuration (ransomware often clears logs)
    execute_powershell \
        "Get-EventLog -List | Select-Object Log,MaximumKilobytes,OverflowAction | Format-Table" \
        "T1490" \
        "Checking event log configuration"
    
    # Identify database services (ransomware targets these)
    execute_powershell \
        "Get-Service | Where-Object {\$_.Name -match 'mssql|mysql|postgres|oracle|mongodb'} | Select-Object Name,DisplayName,Status | Format-Table" \
        "T1489" \
        "Enumerating database services"
    
    # Check for mapped network drives (ransomware spreads to these)
    execute_powershell \
        "Get-SmbMapping -ErrorAction SilentlyContinue | Select-Object LocalPath,RemotePath,Status | Format-Table" \
        "T1135" \
        "Enumerating mapped network drives"
    
    # Check Volume Shadow Copy Service status
    execute_powershell \
        "Get-Service VSS | Select-Object Name,DisplayName,Status,StartType | Format-List" \
        "T1490" \
        "Checking Volume Shadow Copy Service status"
    
    print_warning "Ransomware TTP demonstration complete - no files were harmed"
}

# ============================================================================
# PHASE 11: EICAR AV DETECTION TEST
# Test antivirus detection using the safe EICAR test file
# ============================================================================

phase_eicar_test() {
    print_section "PHASE 11: EICAR AV Detection Test" "AV-TEST"
    
    print_warning "Testing AV detection with EICAR (a safe, standard test file)"
    echo ""
    
    # EICAR is a standard test string recognized by all antivirus software
    # It is NOT malware - it's specifically designed for AV testing
    local eicar='X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
    
    {
        echo "  ┌─ EICAR AV Detection Test"
        echo "  │  NOTE: EICAR is a SAFE, industry-standard test file"
        echo "  │"
    } >> "$LOG_FILE"
    
    # Test 1: Create EICAR file in WSL filesystem
    ((TOTAL_ACTIONS++))
    print_action "Creating EICAR test file in WSL filesystem..."
    
    local eicar_tmp="/tmp/eicar_test_$(date +%Y%m%d_%H%M%S).com"
    
    if echo "$eicar" > "$eicar_tmp" 2>/dev/null; then
        if [ -f "$eicar_tmp" ]; then
            print_success "EICAR created in WSL: $eicar_tmp" "AV-TEST"
            echo "  │  [WSL] Created: $eicar_tmp" >> "$LOG_FILE"
            
            # Wait and check if AV deleted it
            sleep 2
            if [ -f "$eicar_tmp" ]; then
                print_warning "EICAR still exists - AV may not be monitoring WSL filesystem"
                echo "  │  [WSL] File persists - possible AV coverage gap" >> "$LOG_FILE"
            else
                print_success "EICAR was deleted - AV is monitoring WSL filesystem" "AV-TEST"
                echo "  │  [WSL] File deleted by AV" >> "$LOG_FILE"
            fi
        fi
    else
        print_success "EICAR blocked in WSL - AV is active" "AV-TEST"
        echo "  │  [WSL] Blocked immediately" >> "$LOG_FILE"
    fi
    
    # Test 2: Create EICAR file on Windows filesystem
    ((TOTAL_ACTIONS++))
    print_action "Creating EICAR test file on Windows filesystem..."
    
    local eicar_win="$WINDOWS_SYSTEM/Users/Public/Documents/eicar_test.com"
    
    if echo "$eicar" > "$eicar_win" 2>/dev/null; then
        sleep 1
        if [ -f "$eicar_win" ]; then
            print_warning "EICAR exists on Windows filesystem - AV may be inactive" "AV-TEST"
            echo "  │  [WINDOWS] File persists - AV may be disabled" >> "$LOG_FILE"
            rm -f "$eicar_win" 2>/dev/null
        else
            print_success "EICAR was deleted from Windows - AV is active" "AV-TEST"
            echo "  │  [WINDOWS] File deleted by AV" >> "$LOG_FILE"
        fi
    else
        print_success "EICAR blocked on Windows filesystem - AV is active" "AV-TEST"
        echo "  │  [WINDOWS] Blocked immediately" >> "$LOG_FILE"
    fi
    
    # Test 3: Try EICAR with different file extensions
    print_action "Testing EICAR detection with various file extensions..."
    ((TOTAL_ACTIONS++))
    
    local extensions=("txt" "exe" "com" "bat" "ps1")
    local detected=0
    local missed=0
    
    for ext in "${extensions[@]}"; do
        local test_file="/tmp/eicar_test.$ext"
        echo "$eicar" > "$test_file" 2>/dev/null
        sleep 1
        
        if [ -f "$test_file" ]; then
            echo "  │  [.$ext] Not detected/deleted" >> "$LOG_FILE"
            ((missed++))
            rm -f "$test_file" 2>/dev/null
        else
            echo "  │  [.$ext] Detected and removed" >> "$LOG_FILE"
            ((detected++))
        fi
    done
    
    {
        echo "  │"
        echo "  │  Detection Summary:"
        echo "  │    Detected: $detected/${#extensions[@]}"
        echo "  │    Missed: $missed/${#extensions[@]}"
        echo "  └─"
        echo ""
    } >> "$LOG_FILE"
    
    if [ $detected -eq ${#extensions[@]} ]; then
        print_success "AV detected all EICAR test file variations" "AV-TEST"
    elif [ $detected -gt 0 ]; then
        print_warning "AV detected $detected/${#extensions[@]} EICAR variations - some gaps exist" "AV-TEST"
    else
        print_error "AV did not detect any EICAR files - AV may not be active" "AV-TEST"
    fi
    
    # Verify Windows Defender configuration
    print_action "Verifying Windows Defender configuration..."
    
    execute_powershell \
        "Get-MpComputerStatus | Select-Object AntivirusEnabled,AMServiceEnabled,RealTimeProtectionEnabled,IoavProtectionEnabled | Format-List" \
        "AV-TEST" \
        "Checking Windows Defender status"
    
    execute_powershell \
        "Get-MpPreference | Select-Object DisableRealtimeMonitoring,DisableBehaviorMonitoring,DisableBlockAtFirstSeen | Format-List" \
        "AV-TEST" \
        "Checking Windows Defender preferences"
}

# ============================================================================
# BANNER AND INITIALIZATION
# Display script information and initialize log files
# ============================================================================

show_banner() {
    clear
    echo -e "${C_CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                                                                   ║
    ║   ██████╗ ██╗   ██╗██████╗ ██████╗ ██╗     ███████╗              ║
    ║   ██╔══██╗██║   ██║██╔══██╗██╔══██╗██║     ██╔════╝              ║
    ║   ██████╔╝██║   ██║██████╔╝██████╔╝██║     █████╗                ║
    ║   ██╔═══╝ ██║   ██║██╔══██╗██╔═══╝ ██║     ██╔══╝                ║
    ║   ██║     ╚██████╔╝██║  ██║██║     ███████╗███████╗              ║
    ║   ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝              ║
    ║                                                                   ║
    ║   ████████╗███████╗ █████╗ ███╗   ███╗                           ║
    ║   ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║                           ║
    ║      ██║   █████╗  ███████║██╔████╔██║                           ║
    ║      ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║                           ║
    ║      ██║   ███████╗██║  ██║██║ ╚═╝ ██║                           ║
    ║      ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝                           ║
    ║                                                                   ║
    ║               Red Team Simulation Framework                      ║
    ║                    WSL → Windows Host                            ║
    ║                                                                   ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${C_RESET}"
    echo -e "${C_WHITE}    Version: ${C_CYAN}${SCRIPT_VERSION}${C_RESET}"
    echo -e "${C_WHITE}    Target:  ${C_CYAN}Windows Host via WSL${C_RESET}"
    echo -e "${C_WHITE}    Purpose: ${C_CYAN}Authorized Purple Team Exercise${C_RESET}"
    echo ""
    echo -e "${C_YELLOW}    ⚠  FOR AUTHORIZED SECURITY TESTING ONLY  ⚠${C_RESET}"
    echo ""
    
    # Initialize log files with header information
    {
        echo "╔═══════════════════════════════════════════════════════════════════╗"
        echo "║           PURPLE TEAM AGENT EXECUTION LOG                        ║"
        echo "╚═══════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Execution Details:"
        echo "  Script Version: $SCRIPT_VERSION"
        echo "  Start Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "  Log File: $LOG_FILE"
        echo "  JSON Log: $JSON_LOG"
        echo "  Operator: $(whoami)"
        echo "  Hostname: $(hostname)"
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
    } > "$LOG_FILE"
    
    # Initialize JSON log array
    echo "[" > "$JSON_LOG"
}

# ============================================================================
# SUMMARY AND CLEANUP
# Display execution summary and finalize logs
# ============================================================================

generate_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    # Display summary to terminal
    echo ""
    echo -e "${C_CYAN}╔═══════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}                    ${C_WHITE}EXECUTION SUMMARY${C_RESET}                              ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚═══════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE}Duration:${C_RESET}       ${minutes}m ${seconds}s"
    echo -e "  ${C_WHITE}Total Actions:${C_RESET}  $TOTAL_ACTIONS"
    echo -e "  ${C_GREEN}Successful:${C_RESET}     $SUCCESSFUL_ACTIONS"
    echo -e "  ${C_RED}Failed:${C_RESET}         $FAILED_ACTIONS"
    
    if [ $TOTAL_ACTIONS -gt 0 ]; then
        local success_rate=$(awk "BEGIN {printf \"%.1f\", ($SUCCESSFUL_ACTIONS/$TOTAL_ACTIONS)*100}")
        echo -e "  ${C_CYAN}Success Rate:${C_RESET}   ${success_rate}%"
    fi
    
    echo ""
    echo -e "${C_YELLOW}📋 Output Files:${C_RESET}"
    echo -e "  ${C_WHITE}Professional Log:${C_RESET} $LOG_FILE"
    echo -e "  ${C_WHITE}JSON Log:${C_RESET}         $JSON_LOG"
    
    if [ -f "/tmp/RANSOMWARE_NOTE_PURPLETEAM.txt" ]; then
        echo -e "  ${C_WHITE}Ransom Note:${C_RESET}      /tmp/RANSOMWARE_NOTE_PURPLETEAM.txt"
    fi
    
    if ls -d /tmp/collected_data_* &>/dev/null; then
        echo -e "  ${C_WHITE}Collected Data:${C_RESET}   $(ls -d /tmp/collected_data_* 2>/dev/null | tail -1)"
    fi
    
    echo ""
    echo -e "${C_CYAN}🔍 Blue Team Detection Hints:${C_RESET}"
    echo ""
    echo -e "${C_WHITE}  Standard Indicators:${C_RESET}"
    echo "    • PowerShell EventID 4104 (Script Block Logging)"
    echo "    • Process Creation EventID 4688 (WSL → PowerShell)"
    echo "    • File Access EventID 4663"
    echo "    • Registry Access EventID 4657"
    echo "    • Network Connection EventID 5156"
    echo ""
    echo -e "${C_WHITE}  Ransomware-Specific:${C_RESET}"
    echo "    • Volume Shadow Copy enumeration/deletion"
    echo "    • Mass file enumeration patterns"
    echo "    • Ransom note creation (.txt files)"
    echo "    • Service stop attempts (backup/database services)"
    echo "    • Event log tampering attempts"
    echo ""
    
    # Write summary to log file
    {
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "EXECUTION SUMMARY"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "Completion Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Total Duration: ${minutes}m ${seconds}s"
        echo ""
        echo "Statistics:"
        echo "  Total Actions:    $TOTAL_ACTIONS"
        echo "  Successful:       $SUCCESSFUL_ACTIONS"
        echo "  Failed:           $FAILED_ACTIONS"
        if [ $TOTAL_ACTIONS -gt 0 ]; then
            echo "  Success Rate:     $(awk "BEGIN {printf \"%.1f\", ($SUCCESSFUL_ACTIONS/$TOTAL_ACTIONS)*100}")%"
        fi
        echo ""
        echo "Environment:"
        echo "  WSL Version:      $WSL_VERSION"
        echo "  PowerShell:       $POWERSHELL_CMD"
        echo "  Windows Mount:    $WINDOWS_SYSTEM"
        echo ""
        echo "Output Files:"
        echo "  Text Log:         $LOG_FILE"
        echo "  JSON Log:         $JSON_LOG"
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
    } >> "$LOG_FILE"
    
    # Finalize JSON log with summary
    echo '{"summary": {"duration": '$duration', "total": '$TOTAL_ACTIONS', "successful": '$SUCCESSFUL_ACTIONS', "failed": '$FAILED_ACTIONS'}}]' >> "$JSON_LOG"
    
    echo -e "${C_GREEN}${SYM_SUCCESS} Purple Team exercise completed successfully${C_RESET}"
    echo ""
}

# ============================================================================
# MAIN EXECUTION LOGIC
# Parse command line arguments and execute requested phases
# ============================================================================

main() {
    local run_all=true
    local phases_to_run=()
    local quiet_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_phases
                exit 0
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -p|--phase)
                run_all=false
                IFS=',' read -ra phases_to_run <<< "$2"
                shift 2
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                echo -e "${C_RED}Unknown option: $1${C_RESET}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Display banner unless in quiet mode
    if [ "$quiet_mode" = false ]; then
        show_banner
        sleep 1
    fi
    
    # Always run environment detection first
    detect_environment
    sleep 1
    
    # Execute all phases or specific ones based on arguments
    if [ "$run_all" = true ]; then
        phase_system_discovery
        sleep 1
        phase_account_discovery
        sleep 1
        phase_process_discovery
        sleep 1
        phase_file_discovery
        sleep 1
        phase_credential_search
        sleep 1
        phase_registry_query
        sleep 1
        phase_network_discovery
        sleep 1
        phase_automated_collection
        sleep 1
        phase_persistence_recon
        sleep 1
        phase_ransomware_behavior
        sleep 1
        phase_eicar_test
        sleep 1
    else
        # Run only the specified phases
        for phase in "${phases_to_run[@]}"; do
            case $phase in
                1) phase_system_discovery ;;
                2) phase_account_discovery ;;
                3) phase_process_discovery ;;
                4) phase_file_discovery ;;
                5) phase_credential_search ;;
                6) phase_registry_query ;;
                7) phase_network_discovery ;;
                8) phase_automated_collection ;;
                9) phase_persistence_recon ;;
                10) phase_ransomware_behavior ;;
                11) phase_eicar_test ;;
                *)
                    print_error "Invalid phase number: $phase (valid range: 1-11)"
                    ;;
            esac
            sleep 1
        done
    fi
    
    # Generate and display final summary
    generate_summary
}

# ============================================================================
# ERROR HANDLING
# Catch script interruption and generate summary before exit
# ============================================================================

trap 'print_error "Script interrupted by user"; generate_summary; exit 1' INT TERM ERR

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

main "$@"
exit 0
