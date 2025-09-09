#!/bin/bash

echo "=== COLLECTING HARDWARE SERIALS ==="
echo ""

# Check if we need root
if [ "$EUID" -ne 0 ]; then
    echo "Running with sudo..."
    sudo "$0" "$@"
    exit
fi

# Install required tools if missing
echo "Checking required tools..."
command -v dmidecode >/dev/null 2>&1 || { 
    echo "Installing dmidecode..."; 
    yum install -y dmidecode 2>/dev/null || apt-get install -y dmidecode 2>/dev/null || dnf install -y dmidecode 2>/dev/null; 
}

command -v smartctl >/dev/null 2>&1 || { 
    echo "Installing smartmontools..."; 
    yum install -y smartmontools 2>/dev/null || apt-get install -y smartmontools 2>/dev/null || dnf install -y smartmontools 2>/dev/null; 
}

command -v nvme >/dev/null 2>&1 || { 
    echo "Installing nvme-cli..."; 
    yum install -y nvme-cli 2>/dev/null || apt-get install -y nvme-cli 2>/dev/null || dnf install -y nvme-cli 2>/dev/null; 
}

echo ""
echo "=== SERVER HARDWARE SERIALS ==="
echo ""

# Motherboard Info
echo "MOTHERBOARD:"
if [ -f /sys/class/dmi/id/board_vendor ] && [ -f /sys/class/dmi/id/board_name ]; then
    echo "Model: $(cat /sys/class/dmi/id/board_vendor 2>/dev/null) $(cat /sys/class/dmi/id/board_name 2>/dev/null)"
    echo "Serial: $(cat /sys/class/dmi/id/board_serial 2>/dev/null)"
else
    dmidecode -t baseboard 2>/dev/null | grep -E "Manufacturer:|Product Name:|Serial Number:" | sed 's/^[\t]*//'
fi
echo ""

# CPU Info
echo "CPU:"
lscpu 2>/dev/null | grep "Model name:" | sed 's/Model name:[\t]*//' || dmidecode -t processor 2>/dev/null | grep "Version:" | head -1 | sed 's/^[\t]*//'
echo ""

# RAM Modules - Simplified approach
echo "RAM MODULES:"
dmidecode -t 17 2>/dev/null > /tmp/ram_info.txt
grep -n "Memory Device" /tmp/ram_info.txt | while read line; do
    line_num=$(echo $line | cut -d: -f1)
    
    # Extract info for this memory device
    size=$(sed -n "${line_num},/Memory Device/p" /tmp/ram_info.txt | grep "Size:" | grep -v "No Module" | head -1 | sed 's/.*Size: //' | sed 's/^[\t]*//')
    location=$(sed -n "${line_num},/Memory Device/p" /tmp/ram_info.txt | grep "Locator:" | grep -v "Bank" | head -1 | sed 's/.*Locator: //' | sed 's/^[\t]*//')
    serial=$(sed -n "${line_num},/Memory Device/p" /tmp/ram_info.txt | grep "Serial Number:" | head -1 | sed 's/.*Serial Number: //' | sed 's/^[\t]*//')
    manufacturer=$(sed -n "${line_num},/Memory Device/p" /tmp/ram_info.txt | grep "Manufacturer:" | head -1 | sed 's/.*Manufacturer: //' | sed 's/^[\t]*//')
    
    # Only print if we have valid serial and size
    if [ ! -z "$serial" ] && [ "$serial" != "Not Specified" ] && [ "$serial" != "NO DIMM" ] && [ ! -z "$size" ] && [ "$size" != "No Module Installed" ]; then
        echo "$location: $serial ($manufacturer $size)"
    fi
done
rm -f /tmp/ram_info.txt
echo ""

# Storage Drives
echo "STORAGE DRIVES:"

# NVMe drives
for nvme in /dev/nvme[0-9]n[0-9]; do
    if [ -e "$nvme" ]; then
        serial=$(nvme id-ctrl "$nvme" 2>/dev/null | grep "^sn" | cut -d: -f2 | xargs)
        model=$(nvme id-ctrl "$nvme" 2>/dev/null | grep "^mn" | cut -d: -f2 | xargs)
        size=$(lsblk -b "$nvme" 2>/dev/null | grep -E "^nvme" | head -1 | awk '{printf "%.1fTB", $4/1000000000000}')
        if [ ! -z "$serial" ]; then
            echo "$(basename $nvme): $serial ($model $size)"
        fi
    fi
done

# SATA/SAS drives
for disk in /dev/sd[a-z]; do
    if [ -e "$disk" ]; then
        serial=$(smartctl -i "$disk" 2>/dev/null | grep "Serial Number:" | cut -d: -f2 | xargs)
        model=$(smartctl -i "$disk" 2>/dev/null | grep "Device Model:" | cut -d: -f2 | xargs)
        if [ -z "$model" ]; then
            model=$(smartctl -i "$disk" 2>/dev/null | grep "Product:" | cut -d: -f2 | xargs)
        fi
        size=$(lsblk -b "$disk" 2>/dev/null | grep -E "^sd[a-z]" | head -1 | awk '{printf "%.1fTB", $4/1000000000000}')
        if [ ! -z "$serial" ]; then
            echo "$(basename $disk): $serial ($model $size)"
        fi
    fi
done

echo ""
echo "=== COLLECTION COMPLETE ==="