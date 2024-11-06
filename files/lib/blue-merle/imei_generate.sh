#!/bin/bash

# Function to calculate the Luhn check digit
LUHN_CHECK () {
    local sum=0
    local num_digits=${#1}
    local oddeven=$((num_digits & 1))

    for ((i=0; i<num_digits; i++)); do
        local digit=${1:$i:1}
        if ((!((i & 1) ^ oddeven))); then
            digit=$((digit * 2))
        fi
        if ((digit > 9)); then
            digit=$((digit - 9))
        fi
        sum=$((sum + digit))
    done

    echo $((10 - (sum % 10)))
}

# Function to generate a random IMEI
GENERATE_IMEI () {
    # TACs for different manufacturers
    local tacs=(
        "352073" # Samsung
        "352074" # iPhone
        "352075" # Sony
        "352076" # LG
        "352077" # Nokia
        "352078" # Huawei
        "352079" # Xiaomi
        "352080" # OnePlus
    )

    # Randomly choose a manufacturer
    local tac=${tacs[$RANDOM % ${#tacs[@]}]}

    # Generate FAC, USN
    local fac=$(printf "%02d" $((RANDOM % 90 + 10))) # Final Assembly Code
    local usn=$(printf "%06d" $((RANDOM % 900000 + 100000))) # Unique Serial Number

    # Combine all parts to form the IMEI without the check digit
    local imei_without_check="${tac}${fac}${usn}"

    # Calculate the check digit using the Luhn algorithm
    local check_digit=$(LUHN_CHECK "$imei_without_check")

    # Combine all parts to form the complete IMEI
    local imei="${imei_without_check}${check_digit}"

    echo -n "$imei"
}

# Example usage
GENERATE_IMEI
