#!/bin/bash



####################
#                  #
# USEFUL FUNCTIONS #
#                  #
####################


STATUS=0
ERR_MSG=""
set_error() {
    ERR_MSG="${ERR_MSG}\n    ERROR: ${1}\n"
    STATUS=2
}

err_abort() {
    if [ "${STATUS}" -ne 0 ]; then
	echo -e "${ERR_MSG}"
	exit 2
    fi
}

WARNINGS=""
add_warning() {
    local W_msg="${1}"
    local compact="${2:-false}"
    if [ "${compact^^}" == "TRUE" ]; then
	WARNINGS="${WARNINGS}    WARNING: ${1}\n"
    else
	WARNINGS="${WARNINGS}\n    WARNING: ${1}\n"
    fi
}

print_warnings() {
    local compact="${1:-false}"
    if [ ! -z "${WARNINGS}" ]; then
	if [ "${compact^^}" != "TRUE" ]; then
	    echo -e "\n  WARNINGS:"
	    echo -e "  ---------"
	fi
	echo -e "${WARNINGS}"
	WARNINGS=""
    fi
}

ceil () {
    awk -v value="$1" 'BEGIN {ceiling = int(value); if (value > ceiling) ceiling += 1; print ceiling}'
}

abs() {
    add_leading_zero `echo "if ($1 < 0) -($1) else $1" | bc`
}

change_E_to_bc() {
    echo "${1//E/*10^}"
}

bc_W() {
    local in="{$1}"
    in=$( change_E_to_bc "${in}" )
    out=$( echo "${in}" | bc -l | tr -d '\\\n ' )
    echo "${out}"
}

round_to_dec_places() {
    local input="${1}"
    local dec_places="${2}"
    echo $( printf "%.${dec_places}f" ${input} )
}

check_bc_logical() {
    echo $( echo "$1" | bc -l )
}

check_bc_same_float() {
    local epsilon=0.000001
    local bc_tmp=$( bc_W "${1} - ${2}" )
    bc_tmp=$( abs "${bc_tmp}" )
    if [ $( check_bc_logical " ${bc_tmp} < ${epsilon} " ) ]; then
	echo 1
    else
	echo 0
    fi
}

check_bc_logical_input() {
    if [ 1 -eq $( check_bc_logical "${1}" ) ]; then
	set_error "$2"
    fi
}

check_input_file_exists() {
    if [ ! -f "${1}" ]; then
        set_error "${1} not present."
    fi
}

check_if_logical() {
    for LOG in "$@"; do
	if [ "${LOG^^}" != "TRUE" ] && [ "${LOG^^}" != "FALSE" ]; then
	    set_error "Given ${LOG} when expecting 'true' or 'false'."
	fi
    done
}

check_if_positive() {
    echo $(echo "${1} > 0" | bc)
}

check_if_positive_input() {
    for POS in "$@"; do
	if [ $(check_if_positive "${POS}") -eq 0 ]; then
	    set_error "Given value of ${POS} when expecting positive number."
	fi
    done
}

check_if_string_in_file_uncommented() {
    # Check if a string is in an input file on an uncommented line (ignoring case)
    # Return the number of uncommented lines with the occurance
    local file="${1}"
    local string="${2}"
    echo $( grep -v "^[[:space:]]*#" ${file} | grep -i -e "^[[:space:]]*${string}" | wc -l )
}

get_string_in_file_uncommented() {
    # Get the line in an input file from an uncommented line (ignoring case)
    local file="${1}"
    local string="${2}"
    echo $( grep -v "^[[:space:]]*#" ${file} | grep -i -e "^[[:space:]]*${string}" )
}

remove_duplicates_from_array() {
    # Remove all the duplicates from an input array without changing the order of the array
    declare -A known # For keeping track of previously found elements
    local return_arr=()
    for X in "$@"; do
	if [[ ! "${known[$X]}" ]]; then
	    known["$X"]=1
	    return_arr+=("$X")
	fi
    done
    echo "${return_arr[@]}"
}

get_lowest_integer_from_array() {
    local min="${1}"
    for val in "${@}"; do
	if [[ "${val}" -lt "${min}" ]]; then
	    min="${val}"
	fi
    done
    echo $min
}

add_leading_zero() {
    # Add a leading zero to a string containing a float
    local num="$1"
    if [[ "$num" == .* ]]; then
        num="0${num}"
    fi
    echo $num
}

remove_padding_spaces() {
    local no_padding_spaces="$1"
    no_padding_spaces="${no_padding_spaces#"${no_padding_spaces%%[![:space:]]*}"}"
    no_padding_spaces="${no_padding_spaces%"${no_padding_spaces##*[![:space:]]}"}"
    echo "${no_padding_spaces}"
}

is_value_in_array() {
    local to_check_for=$1
    shift
    local arr_to_check=("$@")
    for V in "${arr_to_check[@]}"; do
	if [ "$(remove_padding_spaces "${V}")" == "$(remove_padding_spaces "${to_check_for}")" ]; then
	    echo 1
	    return
	fi
    done
    echo 0
}

run_process() {
    # For use with xargs to allow for parellel calls to CASTP
    PROCESS_CMD=$1
    PROCESS_SEED=$2
    echo "Running CASTEP calculation for ${PROCESS_SEED} by executing:"
    echo "        ${PROCESS_CMD} ${PROCESS_SEED}"
    $PROCESS_CMD $PROCESS_SEED
    if [ -f "${PROCESS_SEED}*.err" ]; then
	echo ""
	echo "! WARNING: ${PROCESS_SEED} exited with an error"
	echo ""
    fi
    echo "        Calculation finished for ${PROCESS_CMD} ${PROCESS_SEED}"
    echo ""
}

read_input() {
    # Check to see if the input string is present in a non-commented line in the input file
    # If present return value and if not return default value
    local input_file="$1"
    local input_string="$2"
    local exclude_from_equals_test=("castep_cmd") # To allow for '=' in things like the castep command
    default_value=()
    shift 2
    if [[ $# -gt 0 ]]; then
        default_value=("$@")
    fi
    # Grep for the line containing the command that is not commented
    local num_valid_inputs=$( grep -i "^[^0-9#]*${input_string}" ${input_file} | wc -l )
    # If we haven't found any valid inputs return the default
    if [ $num_valid_inputs -eq 0 ]; then
	echo "${default_value[@]}"
	return
    elif [ $num_valid_inputs -gt 1 ]; then
	echo "! ERROR: More than one entry in input file found for keyword ${input_string}."
	return
    else
	# Right number of input lines so read the input value, checking that the string on the line contains a valid delimeter
	local full_line=$( grep -i "^[^0-9#]*${input_string}" ${input_file} )
	local num_equals=$( grep -o "=" <<< "${full_line}" | wc -l )
	if [ $(is_value_in_array "${full_line%%=*}" "${exclude_from_equals_test[@]}") -eq 1 ]; then
	    # If excluded from further tests just return trimmed output
	    local trimmed="$(remove_padding_spaces "${full_line#*=}")"
	    echo "$trimmed"
	    return
	elif [ $num_equals -eq 1 ]; then
	    # This is correct so just return the value in the input file
	    local trimmed="$(remove_padding_spaces "${full_line#*=}")"
	    echo "$trimmed"
	    return
	elif  [ $num_equals -eq 0 ]; then
	    # Need an equals sign as a delimeter
	    echo "! ERROR: No '=' in the input line for ${input_string}."
	    return
	else
	    # More than one equals, so something a bit off
	    echo "! ERROR: More than one '=' in the input line for ${input_string}."
	    return
	fi
    fi
}

read_inputs_single() {
    # Read all the input from the input array to the given gloabl variables
    # Takes in a string that is the string of a variable name, and resets this variable with the
    # associated value from the input file
    local options_input_file="$1"
    shift
    for I in "$@"; do
	TMP=$( read_input ${options_input_file} ${I} ${!I} )
	declare -g "${I}=${TMP}"
	echo "    - ${I} = ${TMP}"
    done
}

read_inputs_three() {
    # Read all the input from the input array to the given gloabl variables
    # Takes in a string that is the string of a variable name, and resets this variable with the
    # associated value from the input file
    # For when the variable is an array of length 3, a few extra considerations need to be taken if this is the case
    local options_input_file="$1"
    shift
    for I in "$@"; do
	J="${I}[@]"
	TMP=($( read_input ${options_input_file} ${I} ${!J} ))
        array_string=" "
        for item in "${TMP[@]}"; do
            array_string+="${item} "
        done
	declare -ag "${I}=(${array_string})"
	echo "    - ${I} =${array_string}"
    done
}

check_input () {
    # Check the string input from the read_input command, exiting if there is an error
    local check_input="$1"
    local error_prefix="!"
    check_input="${check_input#"${check_input%%[![:space:]]*}"}" # Remove leading spaces
    if [[ "${check_input:0:1}" == "${error_prefix}" ]]; then
	echo ""
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "! ERROR: Error found in input file, see above variable defenitions. !"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo ""
	exit 1
    fi
}

generate_seed() {
    # Generate a seed for the current kpoint and cutoff
    local seed="$1"
    local cut="$2"
    local kpoint="$3"
    local fine_gmax=$( printf "%.4f" "$4" )
    local generated_seed="${seed}_cutoff_${cut}_kpoint_${kpoint}_fGmax_${fine_gmax}"
    echo "${generated_seed}"
}

castep_output_completed() {
    # Check if the <seed>.castep output file has completed
    local seed="$1"
    local S="${seed}.castep"
    if [ -f "${S}" ]; then
	# Assume if Total time is in the output it has completed
        if [ $(grep "Total time          =" "$S" | wc -l) -gt 0 ]; then
            echo 1
        else
            echo 0
        fi
    else
	# If the file does not exist it certainly hasn't completed
	echo 0
    fi
}

modify_param_file() {
    # Modify the param file for the correct cutoff
    local seed="$1"
    local cut_off_add="$2"
    local fine_gmax_add="$3"
    local stress_converge="$4"
    local collinear_spin_converge="$5"
    local vector_spin_converge="$6"
    local reuse="$7"
    local supress_excess="$8"

    local flags_to_delete=("task" "cut_off_energy" "calculate_stress" "reuse" "fine_grid_scale" "fine_gmax" "comment")
    if [ "${collinear_spin_converge^^}" == "TRUE" ]; then
	flags_to_delete+=("spin_treatment" "spin_polarised" "spin_polarized")
    fi
    if [ "${vector_spin_converge^^}" == "TRUE" ]; then
	flags_to_delete+=("spin_treatment" "spin_polarised" "spin_polarized")
    fi
    if [ "${reuse^^}" == "TRUE" ]; then
	flags_to_delete+=("write_none" "write_checkpoint")
    fi
    if [ "${supress_excess^^}" == "TRUE" ]; then
	flags_to_delete+=("write_checkpoint" "write_cst_esp" "write_bands" "write_bib")
    fi

    local S="${seed}.param"

    # Check convergence inputs
    if [ "${stress_converge^^}" != "TRUE" ] && [ "${stress_converge^^}" != "FALSE" ]; then
	set_error "Converge stress input (input 4) must be either 'true' or 'false'."
    fi
    if [ "${collinear_spin_converge^^}" != "TRUE" ] && [ "${collinear_spin_converge^^}" != "FALSE" ]; then
	set_error "Collinear spin converge input (input 5) must be either 'true' or 'false'."
    fi
    if [ "${vector_spin_converge^^}" != "TRUE" ] && [ "${vector_spin_converge^^}" != "FALSE" ]; then
	set_error "Vector spin converge input (input 6) must be either 'true' or 'false'."
    fi
    if [ "${vector_spin_converge^^}" == "TRUE" ] && [ "${collinear_spin_converge^^}" == "TRUE" ]; then
	set_error "Collinear spin converge input (input 5) and vector spin converge input (input 6) cannot both be true."
    fi
    if [ "${reuse^^}" != "TRUE" ] && [ "${reuse^^}" != "FALSE" ]; then
	set_error "Reuse input (input 7) must be either 'true' or 'false'."
    fi
    if [ "${supress_excess^^}" != "TRUE" ] && [ "${supress_excess^^}" != "FALSE" ]; then
	set_error " input (input 8) must be either 'true' or 'false'."
    fi

    # Check if the file exists
    if [ ! -f "$S" ]; then
        set_error "'$S' does not exist."
    fi

    # Use sed to delete lines containing any of the flags that need removing
    for flag in "${flags_to_delete[@]}"; do
	sed -i "/$flag/Id" "$S"
    done

    # Add in all the relevant lines
    echo "" >> $S
    echo "##############################" >> $S
    echo "# ADDED FOR CONVERGENCE TEST #" >> $S
    echo "##############################" >> $S
    echo "" >> $S
    echo "TASK                   = SINGLEPOINT" >> $S
    echo "CUT_OFF_ENERGY         = ${cut_off_add} eV" >> $S
    echo "FINE_GMAX              = ${fine_gmax_add} 1/ang" >> $S
    echo "CALCULATE_STRESS       = ${stress_converge^^}" >> $S
    if [ "${collinear_spin_converge^^}" == "TRUE" ]; then
	echo "SPIN_POLARISED         = ${collinear_spin_converge^^}" >> $S
	echo "SPIN_TREATMENT         = COLLINEAR" >> $S
    fi
    if [ "${vector_spin_converge^^}" == "TRUE" ]; then
	echo "SPIN_ORBIT_COUPLING    = TRUE" >> $S
	echo "SPIN_TREATMENT         = VECTOR" >> $S
	echo "RELATIVISTIC_TREATMENT = DIRAC" >> $S
    fi
    if [ "${reuse^^}" == "TRUE" ]; then
	echo "WRITE_CHECKPOINT       = TRUE" >> $S
    fi
    if [ "${supress_excess^^}" == "TRUE" ]; then
	if [ "${reuse^^}" == "FALSE" ]; then
	    echo "WRITE_CHECKPOINT       = NONE" >> $S
	fi
	echo "WRITE_CST_ESP          = FALSE" >> $S
	echo "WRITE_BANDS            = FALSE" >> $S
	echo "WRITE_BIB              = FALSE" >> $S
    fi
}

modify_param_file_reuse() {
    local seed="${1}"
    local reuse_seed="${2}"
    local S="${seed}.param"
    echo "REUSE                  = ${reuse_seed}.check" >> $S
}

check_if_string_contains_substring() {
    local string="${1}"
    local substring="${2}"
    if [ $( echo "${string}" | grep -i -e "${substring}" | wc -l ) -eq 1 ]; then
	echo 1
    else
	echo 0
    fi
}

modify_param_file_comment() {
    local seed="${1}"
    local comment="${2}"
    local S="${seed}.param"
    # Check if the string comment is in the param file on an uncommented line,
    # if it is append it, otherwise write the comment keyword as well
    if [ $( check_if_string_in_file_uncommented "${S}" "comment" ) -eq 1 ]; then
	if [ $( check_if_string_contains_substring "`grep ${S} -i -e "COMMENT"`" "${comment}" ) -eq 0 ]; then
            sed -i "/[Cc][Oo][Mm][Mm][Ee][Nn][Tt]/s/$/_${comment}/i" "${S}"
	fi
    elif [ $( check_if_string_in_file_uncommented "${S}" "comment" ) -eq 0 ]; then
	echo "COMMENT                = ${comment}" >> $S
    else
	set_error "String 'COMMENT' occurs more than once in param file"
    fi
}

modify_cell_file() {
    # Modify the cell file for the correct kpoint
    local seed="$1"
    local flags_to_delete=( \
			   "KPOINTS_LIST" "KPOINTS_MP_GRID" "KPOINTS_MP_SPACING" "KPOINTS_MP_OFFSET" \
					  "KPOINT_LIST" "KPOINT_MP_GRID" "KPOINT_MP_SPACING" "KPOINT_MP_OFFSET")
    local S="${seed}.cell"

    # Check if the file exists
    if [ ! -f "$S" ]; then
        echo "ERROR '$S' does not exist."
        exit 3
    fi

    # Use sed to delete lines containing any of the flags that need removing
    for flag in "${flags_to_delete[@]}"; do
	sed -i "/$flag/Id" "$S"
    done

    # Add in all the relevant lines
    echo "" >> $S
    echo "##############################" >> $S
    echo "# ADDED FOR CONVERGENCE TEST #" >> $S
    echo "##############################" >> $S
    echo "" >> $S
    echo "KPOINT_MP_GRID : ${2} ${3} ${4}" >> $S
    echo "" >> $S
}

kpoint_grid_iterate() {

    local new_min="${1}"
    local grid=(${2} ${3} ${4})
    local old_min=$(get_lowest_integer_from_array ${grid[@]})
    local out_grid=()
    for K in "${grid[@]}"; do
	out_grid+=($(ceil `echo " ( ${new_min} / ${old_min} ) * ${K} " | bc -l`))
    done
    echo ${out_grid[@]}
}

kpoint_grid_string() {
    # Convert the kpoint into a string, This either returns the singular value of the kpoint spacing
    # or it converts to axbxc for a grid
    if [ $# -eq 1 ]; then
	echo ${1}
    elif [ $# -eq 3 ]; then
	echo "${1}x${2}x${3}"
    else
	echo "ERROR: Must have 1 or 3 inputs, input given ${@}."
	exit 3
    fi
}

find_num_with_largest_magnitude() {
    # Return the number with the largest magnitude based on a series of inputs
    local mag_largest=0
    local largest=0
    for num in "$@"; do
        # Get magnitude by removing the "-" character if present
        local abs=$( echo "$num" | tr -d - )
        if [ $(echo "$abs > $mag_largest" | bc) -eq 1 ]; then
            largest=$num
            mag_largest=$abs
        fi
    done
    echo "$largest"
}

check_if_argument_in_file() {
    # Check if an argument is in the cell file on a non-comment line
    local cell_file="${1}"
    local arg_flag="${2}"
    echo $( check_if_string_in_file_uncommented "${cell_file}" "${arg_flag}" )
}

check_if_argument_in_cell() {
    # Check if an argument is in the cell file on a non-comment line
    local cell_file="${1}.cell"
    local arg_flag="${2}"
    echo $( check_if_string_in_file_uncommented "${cell_file}" "${arg_flag}" )
}

check_if_argument_in_param() {
    # Check if an argument is in the param file on a non-comment line
    local param_file="${1}.param"
    local arg_flag="${2}"
    echo $( check_if_argument_in_file "${param_file}" "${arg_flag}" )
}

get_numerical_argument_from_file() {
    local file="${1}"
    local arg_flag="${2}"
    if [ $( check_if_argument_in_file "${file}" "${arg_flag}" ) -ne 1 ]; then
	set_error "There must be one (and only one) occurance of the argument flag in the file ${file}"
    else
	echo $( grep ${file} -ie "${arg_flag}" | sed -E 's/.*[^0-9]([0-9]+(\.[0-9]+)?).*$/\1/' )
    fi
}

get_numerical_argument_from_param() {
    # Get a numerical value from a param file for a given argument
    local param_file="${1}.param"
    local arg_flag="${2}"
    echo $( get_numerical_argument_from_file "${param_file}" "${arg_flag}" )
}

check_file_for_different_arg_val() {
    local file="${1}"
    local argument_name="${2}"
    local argument_value="${3}"

    if [ $( check_if_string_in_file_uncommented "${file}" "${argument_name}" ) -eq 0 ]; then
	# If the argument is not in the param file
	if [ $( check_bc_logical " ${argument_value} < 0 " ) -eq 1 ]; then
	    # If not given in input cell/param and not used in input file (as negative) then use default
	    RETURN="-1"
	else
	    RETURN="${argument_value}"
	fi
    elif [ $( check_if_string_in_file_uncommented "${file}" "${argument_name}" ) -gt 1 ]; then
	# This should not occur so set an error
	set_error "Multiple uncommented occurances of ${argument_name} in ${file}."
    else
	# Otherwise it is in the file, so use the value in the file if not given in the main input here
	add_warning "${argument_name} given in ${file}, it is advised to set this in the castep_converger input file."
	if [ $( check_bc_logical " ${argument_value} < 0 " ) -eq 1 ]; then
	    # If the value is not set in the main input file then just use the value from the .param input file
	    RETURN="$( get_numerical_argument_from_file "${file}" "${argument_name}" )"
	    add_warning "Value for ${argument_name} found in ${file} and corresponding value not set in castep converger input file.\n             Using value of ${RETURN} from ${file}."
	else
	    # Otherwise the value is set in two input files, so use the castep converger file value
	    add_warning "Value for ${argument_name} found both in ${file} AND in castep converger input file.\n             Using value of ${argument_value} from the castep converger input file."
	    RETURN="${argument_value}"
	fi
    fi
}

warn_about_input_arg() {
    local file="${1}"
    local argument="${2}"
    if [ $( check_if_argument_in_file "${file}" "${argument}" ) -gt 1 ]; then
	set_error "More than one occurance of cut_off_energy in param file"
    elif [ $( check_if_argument_in_file "${file}" "${argument}" ) -eq 1 ]; then
	TMP=$( get_numerical_argument_from_file "${file}" "${argument}" )
	add_warning "${argument} of ${TMP} given in main param file,\n             This will be overwritten for convergence tests."
    fi
}

radius_from_E_to_k() {
    # Radius in reciprocal space based on DeBroglie wavelength in recoprocal space for cutoff energy electron
    local E_cut="${1}" # Cutoff energy in eV
    k_out=$( add_leading_zero `bc_W "scale=100; sqrt( ( 2 * $m_e * $e * $E_cut ) / ( 10^20 * $hbar * $hbar ) )"` )
    echo $( round_to_dec_places ${k_out} 16 )
}

delete_old_run() {
    local run_seed="${1}"
    local auto_delete="${2}"
    if [ $( find . -type f -name "${run_seed}*" | wc -l ) -ne 0 ]; then
	if [ "${auto_delete^^}" == "TRUE" ]; then
	    add_warning "Files found for incomplete run ${run_seed}, DELETING." "TRUE"
	    rm ${run_seed}* 2>/dev/null
	else
	    read -p "Found data for incomplete run ${run_seed}. Do you want to delete it? (y/n): " input
	    if [ "$input" = "y" ]; then
		rm ${run_seed}* 2>/dev/null
		echo "Removed old data from ${run_seed}."
	    else
		set_error "Cannot continue without removing old data, please examine file ${run_seed} to see why it can't be removed."
	    fi
	fi
    fi
}

get_current_fine_Gmax() {
    local fine_Gmax="${1}"
    local fine_grid_scale="${2}"
    local cut_off_energy="${3}"
    if [ $(check_if_positive "${fine_Gmax}") -eq 1 ]; then
	# If the input gmax is positive then we already know what it is, so just return it
	echo "${fine_Gmax}"
    elif [ $(check_if_positive "${fine_grid_scale}") -le 0 ]; then
	set_error "fine_Gmax and fine_grid_scale both -ve, this should not be possible if input checks are working correctly."
    else
	# Otherwise we must actually calculate the gmax
	local TMP=$( radius_from_E_to_k "${cut_off_energy}" )
	echo $( bc_W " ${TMP} * ${fine_grid_scale} " )
    fi
}

count_num_true() {
    local ctr=0
    for X in "$@"; do
	if [ "${X^^}" == "TRUE" ]; then
	    ((ctr++))
	fi
    done
}



echo ""
echo "===================================================================================================="
echo ""
echo "                           ╔═╗╔═╗╔═╗╔╦╗╔═╗╔═╗  ┌─┐┌─┐┌┐┌┬  ┬┌─┐┬─┐┌─┐┌─┐┬─┐"
echo "                           ║  ╠═╣╚═╗ ║ ║╣ ╠═╝  │  │ ││││└┐┌┘├┤ ├┬┘│ ┬├┤ ├┬┘"
echo "                           ╚═╝╩ ╩╚═╝ ╩ ╚═╝╩    └─┘└─┘┘└┘ └┘ └─┘┴└─└─┘└─┘┴└─"
echo ""
echo "===================================================================================================="
echo ""



#############
#           #
# CONSTANTS #
#           #
#############

e=1.602176634E-19
m_e=9.1093837015E-31
hbar=1.054571817E-34

# Make sure formatted for bc
e=$( add_leading_zero `change_E_to_bc "${e}"` )
m_e=$( add_leading_zero `change_E_to_bc "${m_e}"` )
hbar=$( add_leading_zero `change_E_to_bc "${hbar}"` )

DEFAULT_FINE_GRID_SCALE=1.75 # Current CASTEP fine_grid_scale default

####################
#                  #
#      INPUTS      #
#                  #
####################


echo "Reading/Setting Parameters"
echo "--------------------------"
echo ""

###################################
# Set defaults for the parameters #
###################################

# Root directory postfix, all files will be stored in <SEED>_${ROOT_DIR_POSTFIX}
ROOT_DIR_POSTFIX="converger"

# Command used to call castep
CASTEP_CMD="castep.serial"

# Seed of base files
SEED="Si"

# What convergence methods should be ran
RUN_CUTOFF="true"
RUN_KPOINT="true"
RUN_FINE_GMAX="false"

# Reuse previous calculations from .cehck files?
REUSE="false"

# Should stresses be converged (with higher cost)
CONVERGE_ENERGY="true"
CONVERGE_FORCE="true"
CONVERGE_STRESS="true"
CONVERGE_COLLINEAR_SPIN="false"
CONVERGE_VECTOR_SPIN="false"

# Convergence parameters, used in graphing
ENERGY_TOL="0.00002" # Total energy tol, will be multiplied by the number of ions in the cell
FORCE_TOL="0.05"
STRESS_TOL="0.1"

# Cutoffs to check in eV
CUTOFF_MIN=300
CUTOFF_MAX=1000
CUTOFF_STEP=100
CUTOFF_KPOINT=( 3 3 3 ) # NOTE : This must be a grid or a spacing based on option

# Kpoint minimum/maximum and kpoint step, which will run in steps for all min <= k <= max.
# NOTE: The kpoint step will increment the smallest kpoint dimension and scale all other kpoint
#       grid directions such that the ratio fo smallest to each other dimension is constant.
#       Note the ceil will be taken of all ratios in case of any non-integers.
#       E.g. for initial kpoint grid of ( 1 2 3 ) in steps of 2 to 6 will test the kpoint grids:
#           ( 1 2 2 ) , ( 3 6 9 ) , ( 5 10 15 )
#       NOTE : This will round up to the nearest integer if required,
#       NOTE : The minimum kpoint grid should be given as an arry of 3 integers, whereas the max value
#              should be the smallest kpoint in the last grid to evaluate.
KPOINT_GRID_MIN=( 3 3 3 )
KPOINT_GRID_STEP=2
KPOINT_GRID_MAX=11
KPOINT_CUTOFF=300

# Fine Gmax or fine grid scale to be used for the kpoint and cutoff convergenve tests
# Set to -1 to not use here and read from the main param file
# If not given either here or in default the default fine grid scale of 1.75 will be used.
CUT_KPT_FINE_GMAX=-1
CUT_KPT_FINE_GRID_SCALE=1.75

# Fine Gmax convergence parameters, only used if RUN_FINE_GMAX == true
# N.B. if set to -1 then will be calcualted from the input parameter fine grid
# N.B. cutoff must be given in eV (but without the units suffix)
FINE_GMAX_CUTOFF=300
FINE_GMAX_KPOINT=( 3 3 3 )
FINE_GMAX_MIN=-1
FINE_GMAX_MAX=-1
FINE_GMAX_STEP=-1
FINE_GRID_MIN=-1
FINE_GRID_MAX=-1
FINE_GRID_STEP=-1

# Should duplicate files be deleted automatically, without asking for user input
DEFAULT_DELETE="false"

# Should we supress output files that are not directly required for convergenge test
SUPRESS_EXCESS_FILES="false"

# Run all parts of the convergence test by default
RUN_GENERATION="true"
RUN_CASTEP="true"
RUN_DATA_ANALYSIS="true"

# Asynchronous parellism option, give number of threads
NUM_PROCESSES=1

##########################################################################
# Check for an input file based on either the defualt or the input value #
##########################################################################

# If the only command line input has given use this as the input file, otherwise use default
if [ $# -eq 0 ]; then
    # Default option
    OPTIONS_INPUTS="castep_converger.inputs"
elif [ $# -eq 1 ]; then
    OPTIONS_INPUTS="${1}"
else
    echo ""
    echo "ERROR: More than one input given, should be called with:"
    echo "           castep_converger.sh <OPTIONS INPUT FILE>"
    echo "       where <OPTIONS INPUT FILE> is an optional input pointing to"
    echo "       the file containing the options for castep_converger."
    echo "       This defaults to 'castep_converger.inputs'"
    echo ""
fi

if [ ! -f ${OPTIONS_INPUTS} ]; then
    echo "ERROR: No input file '${OPTIONS_INPUTS}' found, input file required"
    exit 1
fi

echo ""
echo "  Input file containing castep_converger options : ${OPTIONS_INPUTS}"
echo ""

################################################################################
# Read in the seed from the input file and check that the required files exist #
################################################################################

echo "  General in/outs:"
read_inputs_single "${OPTIONS_INPUTS}" "SEED"
echo ""
check_input_file_exists "${SEED}.cell"
check_input_file_exists "${SEED}.param"

##############################################################################
# Read in from the input files, if they exist, and wrtie out to command line #
##############################################################################

echo "  General in/outs:"
read_inputs_single "${OPTIONS_INPUTS}" "CASTEP_CMD" "RUN_CUTOFF" "RUN_KPOINT" "SUPRESS_EXCESS_FILES"
echo ""
echo "  Attempt to reuse old check files:"
read_inputs_single "${OPTIONS_INPUTS}" "REUSE"
echo ""
echo "  Convergence targets:"
read_inputs_single "${OPTIONS_INPUTS}" "CONVERGE_ENERGY" "CONVERGE_FORCE" "CONVERGE_STRESS" "RUN_FINE_GMAX" "CONVERGE_COLLINEAR_SPIN" "CONVERGE_VECTOR_SPIN"
echo ""
echo "  Convergence tolerances:"
read_inputs_single "${OPTIONS_INPUTS}" "ENERGY_TOL" "FORCE_TOL" "STRESS_TOL"
echo ""
echo "  Cutoff steps:"
read_inputs_single "${OPTIONS_INPUTS}" "CUTOFF_MIN" "CUTOFF_MAX" "CUTOFF_STEP"
read_inputs_three "${OPTIONS_INPUTS}" "CUTOFF_KPOINT"
echo ""
echo "  Kpoint steps:"
read_inputs_three "${OPTIONS_INPUTS}" "KPOINT_GRID_MIN"
read_inputs_single "${OPTIONS_INPUTS}" "KPOINT_GRID_MAX" "KPOINT_GRID_STEP" "KPOINT_CUTOFF"
echo ""
echo "  Cutoff and Kpoint convergence Gmax:"
read_inputs_single "${OPTIONS_INPUTS}" "CUT_KPT_FINE_GMAX" "CUT_KPT_FINE_GRID_SCALE"
echo ""
echo "  Fine Gmax options (only used if converge fine Gmax == true):"
read_inputs_single "${OPTIONS_INPUTS}" "FINE_GMAX_CUTOFF"
read_inputs_three "${OPTIONS_INPUTS}" "FINE_GMAX_KPOINT"
read_inputs_single "${OPTIONS_INPUTS}" "FINE_GMAX_MIN" "FINE_GMAX_MAX" "FINE_GMAX_STEP"
read_inputs_single "${OPTIONS_INPUTS}" "FINE_GRID_MIN" "FINE_GRID_MAX" "FINE_GRID_STEP"
echo ""
echo "  Parellism options:"
read_inputs_single "${OPTIONS_INPUTS}" "NUM_PROCESSES"
echo ""
echo "  Misc options:"
read_inputs_single "${OPTIONS_INPUTS}" "DEFAULT_DELETE" "RUN_GENERATION" "RUN_CASTEP" "RUN_DATA_ANALYSIS"

# Double check all inputs for an error
INPUT_VARIABLE_ARRAY=( "${SEED}" "${CASTEP_CMD}" "${RUN_CUTOFF}" "${RUN_KPOINT}" "${REUSE}" "${CONVERGE_ENERGY}" "${CONVERGE_FORCE}" "${CONVERGE_STRESS}" "${ENERGY_TOL}" "${FORCE_TOL}" "${STRESS_TOL}" "${CUTOFF_MIN}" "${CUTOFF_MAX}" "${CUTOFF_STEP}" "${CUTOFF_KPOINT}" "${KPOINT_GRID_MIN}" "${KPOINT_GRID_MAX}" "${KPOINT_GRID_STEP}" "${KPOINT_CUTOFF}" "${DEFAULT_DELETE}" "${RUN_GENERATION}" "${RUN_CASTEP}" "${RUN_DATA_ANALYSIS}" "${CONVERGE_COLLINEAR_SPIN}" "${NUM_PROCESSES}" "${CONVERGE_VECTOR_SPIN}" "${RUN_FINE_GMAX}" "${FINE_GMAX_CUTOFF}" "${FINE_GMAX_KPOINT}" "${FINE_GMAX_MIN}" "${FINE_GMAX_MAX}" "${FINE_GMAX_STEP}" "${FINE_GRID_MIN}" "${FINE_GRID_MAX}" "${FINE_GRID_STEP}" "${CUT_KPT_FINE_GMAX}" "${CUT_KPT_FINE_GRID_SCALE}" "${SUPRESS_EXCESS_FILES}" )
for INPUT_VAR in "${INPUT_VARIABLE_ARRAY[@]}"; do
    check_input "${INPUT_VAR}"
done



##########################
#                        #
#      CHECK INPUTS      #
#                        #
##########################

check_bc_logical_input "$CUTOFF_MIN < 0" "CUTOFF_MIN < 0"
check_bc_logical_input "$CUTOFF_MAX < 0" "CUTOFF_MAX < 0"
check_bc_logical_input "$CUTOFF_MIN > $CUTOFF_MAX" "CUTOFF_MIN > CUTOFF_MAX"
check_bc_logical_input "$CUTOFF_MAX - $CUTOFF_MIN < $CUTOFF_STEP" "CUTOFF_MAX - CUTOFF_MIN < CUTOFF_STEP"
check_bc_logical_input "$NUM_PROCESSES < 1" "NUM_PROCESSES < 1"
check_bc_logical_input "$FINE_GMAX_MIN > 0 && $FINE_GRID_MIN > 0" "Can't use both fine_grid_min and fine_gmax_min, please set at least one to -ve value to ignore it"
check_bc_logical_input "$FINE_GMAX_MAX > 0 && $FINE_GRID_MAX > 0" "Can't use both fine_grid_max and fine_gmax_max, please set at least one to -ve value to ignore it"
check_bc_logical_input "$FINE_GMAX_STEP > 0 && $FINE_GRID_STEP > 0" "Can't use both fine_grid_step and fine_gmax_step, please set at least one to -ve value to ignore it"
check_bc_logical_input "$CUT_KPT_FINE_GMAX > 0 && $CUT_KPT_FINE_GRID_SCALE > 0" "Can't use both cutoff_kpoint_fine_gmax and cutoff_kpoint_fine_grid_scale, please set at least one to -ve value to ignore it"
check_if_logical "${RUN_CUTOFF}" "${RUN_KPOINT}" "${REUSE}" "${CONVERGE_ENERGY}" "${CONVERGE_FORCE}" "${CONVERGE_STRESS}" "${CONVERGE_COLLINEAR_SPIN}" "${DEFAULT_DELETE}" "${RUN_GENERATION}" "${RUN_CASTEP}" "${RUN_DATA_ANALYSIS}" "${CONVERGE_VECTOR_SPIN}" "${RUN_FINE_GMAX}" "${SUPRESS_EXCESS_FILES}"
check_if_positive_input "${CUTOFF_MIN}" "${CUTOFF_MAX}" "${CUTOFF_STEP}" "${CUTOFF_KPOINT}" "${KPOINT_GRID_STEP}" "${KPOINT_GRID_MAX}" "${KPOINT_CUTOFF}" "${NUM_PROCESSES}"
err_abort

# Can only converge collinear or non-collinear spin
if [ "${CONVERGE_COLLINEAR_SPIN^^}" == "TRUE" ] && [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "! Cannot converge both collinear and non-collinear spin.                !"
    echo "! Please set:                                                           !"
    echo "! converge_collinear_spin = false  AND/OR  converge_vector_spin = false !"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    exit 1
fi

# Currently we can only reuse calculations when running serial calculations
if [ $NUM_PROCESSES -gt 1 ] && [ "${REUSE^^}" == "TRUE" ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "! Cannot currently use reuse==true with asynchronous parellism !"
    echo "! Please set NUM_PROCESSES = 1 and/or REUSE = FALSE            !"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    exit 1
fi


##########################################################################
# Convert any values that may be given in scientific notation to decimal #
# (for easy use with bc)						 #
##########################################################################

CUTOFF_MIN=$( change_E_to_bc $CUTOFF_MIN )
CUTOFF_MAX=$( change_E_to_bc $CUTOFF_MAX )
CUTOFF_STEP=$( change_E_to_bc $CUTOFF_STEP )
KPOINT_CUTOFF=$( change_E_to_bc $KPOINT_CUTOFF )
FINE_GMAX_CUTOFF=$( change_E_to_bc $FINE_GMAX_CUTOFF )
FINE_GMAX_MIN=$( change_E_to_bc $FINE_GMAX_MIN )
FINE_GMAX_MAX=$( change_E_to_bc $FINE_GMAX_MAX )
FINE_GMAX_STEP=$( change_E_to_bc $FINE_GMAX_STEP )


############################################################################################################
# Special checks carried out for values in the param file.						   #
# This informs a user that some of the variables will be overwritten during the convergence test (if set). #
# It also accounts for fine_grid_scale and fine_gmax both being given, or being given in the .param as	   #
#   well as the castep_converger input file.								   #
############################################################################################################

# Double check if inputs are in the param file that will be changed or overwritten
warn_about_input_arg "${SEED}.param" "cut_off_energy"
err_abort

if [ $( check_if_argument_in_cell "${SEED}" "kpoint_mp_grid" ) -eq 1 ] || [ $( check_if_argument_in_cell "${SEED}" "kpoint_mp_spacing" ) -eq 1 ]; then
    add_warning "Kpoint grid information given in main cell file,\n             This will be overwritten for convergence tests."
fi
err_abort

if [ $( check_if_argument_in_param "${SEED}" "grid_scale" ) -eq 1 ] && [ $( check_if_argument_in_param "${SEED}" "fine_gmax" ) -eq 1 ]; then
    set_error "Cannot have grid_scale and fine_gmax given in the param file for convergence tests"
fi
err_abort

# Get the cutoff/kpoint convergence fine grid scale and fine Gmax values
check_file_for_different_arg_val "${SEED}.param" "fine_gmax" "${CUT_KPT_FINE_GMAX}"
CUT_KPT_FINE_GMAX="${RETURN}"
check_file_for_different_arg_val "${SEED}.param" "fine_grid_scale" "${CUT_KPT_FINE_GRID_SCALE}"
CUT_KPT_FINE_GRID_SCALE="${RETURN}"
err_abort

# If both are negative, then nothing set, so default to the default fine grid scale
if [ $( check_bc_logical "${CUT_KPT_FINE_GRID_SCALE} < 0" ) -eq 1 ] \
       && [ $( check_bc_logical "${CUT_KPT_FINE_GMAX} < 0" ) -eq 1 ]; then
    CUT_KPT_FINE_GRID_SCALE="${DEFAULT_FINE_GRID_SCALE}"
    add_warning "No fine_grid_scale or fine_gmax set for use with cutoff and kpoint convergence, using default fine_grid_scale : ${DEFAULT_FINE_GRID_SCALE}."
fi

# Check if both the fine grid scale and fine gmax are set and give long error message if they are
if [ $( check_bc_logical "${CUT_KPT_FINE_GRID_SCALE} > 0" ) -eq 1 ] \
       && [ $( check_bc_logical "${CUT_KPT_FINE_GMAX} > 0" ) -eq 1 ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "! ERROR: Cannot have both fine grid scale and fine Gmax set for a convergence test. !"
    echo "!        Check that they aren't set in the .param input file.                       !"
    echo "!        Also check only one is set (positive) in the castep converger input file.  !"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    exit 2
fi

# Print out the fine grid scale and fine Gmax values that will be used in cutoff and kpoint convergence tests
echo -e "\n  Cutoff and kpoint convergence chosen Gmax/fine grid scale:"
if [ $( check_bc_logical " ${CUT_KPT_FINE_GMAX} > 0 ") -eq 1 ]; then
    echo "    - Using fine Gmax of ${CUT_KPT_FINE_GMAX} 1/ang for all cutoff and kpoint convergence tests."
elif [ $( check_bc_logical " ${CUT_KPT_FINE_GRID_SCALE} > 0 ") -eq 1 ]; then
    TMP=$( radius_from_E_to_k "${KPOINT_CUTOFF}" )
    TMP=$( bc_W " ${TMP} * ${CUT_KPT_FINE_GRID_SCALE} " )
    echo "    - Using fine grid scale of ${CUT_KPT_FINE_GRID_SCALE} for all cutoff and kpoint convergence tests."
    echo "      E.g. equivalent to ${TMP} 1/ang at ${KPOINT_CUTOFF} eV cutoff."
else
    set_error "Cutoff/kpoint convergence fine grid scale (${CUT_KPT_FINE_GRID_SCALE}) and fine Gmax (${CUT_KPT_FINE_GMAX}) both > 0 or < 0. Must use one (and only one) at a time."
fi
err_abort

# Print out any warnings that the user should know about
print_warnings


#################################################################
# Set all the fine Gmax convergence test values based on inputs #
# or generate based on defaults or convert fine_grid inputs to  #
# Gmax values.						        #
#################################################################

# Only need to bother with the following if we are using the Gmax convergence testing
if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then

    echo -e "\n  Extras for Gmax convergance:"
    echo      "  ----------------------------"

    FINE_GRID_SCALE=$DEFAULT_FINE_GRID_SCALE
    K_CUT=$( radius_from_E_to_k ${FINE_GMAX_CUTOFF} )
    MIN_GMAX_POSSIBLE=$( bc_W "${K_CUT} * ${FINE_GRID_SCALE}" )

    echo -e "\n    K_cut = ${K_CUT} 1/ang"

    #
    # Get the minimum fine_Gmax value based on inputs or generation
    #

    if [ $( check_if_positive $FINE_GMAX_MIN ) -eq 1 ]; then
	# If positive then the fine GMax min value has been given, check that it is valid
	if [ $( check_bc_logical "${MIN_GMAX_POSSIBLE} > ${FINE_GMAX_MIN}" ) -eq 1 ]; then
	    set_error "Fine Gmax min of ${FINE_GMAX_MIN} lower than minimum of ${MIN_GMAX_POSSIBLE}\n    (i.e. the fine Gmax from a fine_grid_scale of 1.75)"
	fi
    elif [ $( check_if_positive $FINE_GRID_MIN ) -eq 1 ]; then
	# Fine grid min has been given, so calculate the minimum Gmax from this value and the
	# cutoff for the Gmax convergence run
	if [ $( check_bc_logical "${FINE_GRID_MIN} < 1.75" ) -eq 1 ]; then
	    set_error "Can't have minimum fine grid < 1.75"
	else
	    # Set based on the current cutoff and this grid
	    FINE_GMAX_MIN=$( bc_W " ${K_CUT} * ${FINE_GRID_MIN} " )
	fi
    else
	# If negative then set the min to the default value based on the grid scale
	FINE_GMAX_MIN=${MIN_GMAX_POSSIBLE}
    fi
    err_abort

    TMP=$( round_to_dec_places `bc_W " ${FINE_GMAX_MIN} / ${K_CUT} "` 4 )
    echo -e "\n    fine_gmax_min set to : ${FINE_GMAX_MIN} 1/ang"
    echo "    (Equivalent to fine_grid_scale of ${TMP} for ${FINE_GMAX_CUTOFF} eV cutoff)"

    #
    # Get the Gmax step based on the inputs (or generate with a default of 1 fine grid step
    #

    if [ $( check_if_positive $FINE_GMAX_STEP ) -eq 1 ]; then
	# If positive then the fine GMax step has been given so just use it
	echo -e "\n    Using fine_gmax_step from input of ${FINE_GMAX_STEP} 1/ang"
    elif [ $( check_if_positive $FINE_GRID_STEP ) -eq 1 ]; then
	# Fine grid step given, must be positive so just use it
	# Set based on the current cutoff and this grid
	FINE_GMAX_STEP=$( bc_W " ${K_CUT} * ${FINE_GRID_STEP} " )
    else
	# If negative then set the min to the default value based on the grid scale
	FINE_GMAX_STEP=${K_CUT}
    fi

    TMP=$( round_to_dec_places `bc_W " ${FINE_GMAX_STEP} / ${K_CUT} "` 4 )
    echo -e "\n    fine_gmax_step set to : ${FINE_GMAX_STEP} 1/ang"
    echo "    (Equivalent to fine_grid_scale of ${TMP} for ${FINE_GMAX_CUTOFF} eV cutoff)"

    #
    # Get the Gmax maximum based on inputs or generate from defaults and this cutoff
    #

    if [ $( check_if_positive $FINE_GMAX_MAX ) -eq 1 ]; then
	# If positive then the fine GMax min value has been given, check that it is valid
	if [ $( check_bc_logical "${FINE_GMAX_MIN} > ${FINE_GMAX_MAX}" ) -eq 1 ]; then
	    set_error "Fine Gmax min of ${FINE_GMAX_MIN} larger than input fine Gmax max of ${FINE_GMAX_MAX}"
	elif [ $( check_bc_logical "${FINE_GMAX_MAX} < ${FINE_GMAX_MIN} + ${FINE_GMAX_STEP}" ) -eq 1 ]; then
	    set_error "Fine grid step plus fine grid min less than fine Gmax max of ${FINE_GMAX_MAX}"
	fi
    elif [ $( check_if_positive $FINE_GRID_MAX ) -eq 1 ]; then
	# Calculate the fine_Gmax maximum from the input fine grid max
	FINE_GMAX_MAX=$( bc_W " ${K_CUT} * ${FINE_GRID_MAX} " )
	if [ $( check_bc_logical "${FINE_GMAX_MAX} < ${FINE_GMAX_MIN} + ${FINE_GMAX_STEP}" ) -eq 1 ]; then
	    set_error "Fine grid step plus fine grid min less than fine Gmax max of ${FINE_GMAX_MAX} (calculated from fine_grid_max of ${FINE_GRID_MAX})"
	fi
    else
	# If negative then set the min to the default value based on the grid scale
	FINE_GMAX_MIN=${MIN_GMAX_POSSIBLE}
	echo -e "\n    fine_gmax_min automatically set to : ${FINE_GMAX_MIN} 1/ang"
	echo "    (1.75 * k_cut for ${FINE_GMAX_CUTOFF} eV cutoff)"
    fi
    err_abort

    TMP=$( round_to_dec_places `bc_W " ${FINE_GMAX_MAX} / ${K_CUT} "` 4 )
    echo -e "\n    fine_gmax_max set to : ${FINE_GMAX_MAX} 1/ang"
    echo "    (Equivalent to fine_grid_scale of ${TMP} for ${FINE_GMAX_CUTOFF} eV cutoff)"

fi

echo -e "\n All input tests completed successfully"



#####################
#                   #
# SETUP ENVIRONMENT #
#                   #
#####################

# If the directory for storing all of the convergence tests does not exist create it
if [ ! -d "${SEED}_${ROOT_DIR_POSTFIX}" ]; then
    mkdir ${SEED}_${ROOT_DIR_POSTFIX}
fi

# And into the directory where we will perform all of the required calcualtions
cd ${SEED}_${ROOT_DIR_POSTFIX}

# Copy over any pseudopotential files that were in the root directory
pspot_formats=(".usp" ".uspcc" ".uspso" ".recpot" ".upf" ".DAT" ".data")
for FMT in "${pspot_formats[@]}"; do
    cp ../*${FMT} . 2>/dev/null
done



######################################
#                                    #
#      GENERATE ALL INPUT FILES      #
#                                    #
######################################

SEED_TMP_ARR=() # Used so we don't duplicate runs
if [ "${RUN_GENERATION^^}" == "TRUE" ]; then

    echo ""
    echo "===================================================================================================="
    echo ""
    echo "Generating Input Files"
    echo "----------------------"
    echo ""


    #############################################
    # Create the kpoint convergence input files #
    #############################################

    if [ "${RUN_KPOINT^^}" == "TRUE" ]; then

	#####################################################################################################
	# There are two options for the kpoint grid runs, running based off kpoint grids or kpoint spacings #
	#####################################################################################################

	FIRST_LOOP=1

	# Loop over all the required kpoint grids
	KPT=$( get_lowest_integer_from_array ${KPOINT_GRID_MIN[@]} )
	while [ $KPT -le $KPOINT_GRID_MAX ]; do

	    # Generate the new kpoint grid
	    if [ $KPT -eq $(get_lowest_integer_from_array ${KPOINT_GRID_MIN[@]}) ]; then
		# On the initial loop, so neednt change the kpoint grid
		KPT_GRID=(${KPOINT_GRID_MIN[@]})
	    else
		# Iterate the next kpoint grid
		KPT_GRID=($(kpoint_grid_iterate $KPT ${KPOINT_GRID_MIN[@]}))
	    fi

	    # Get a string version of the kpoint grid
	    KPT_STRING="${KPT_GRID[0]}x${KPT_GRID[1]}x${KPT_GRID[2]}"

	    # Generate a seed for this cutoff and kpoint grid
	    KPT_FINE_GMAX=$( get_current_fine_Gmax "$CUT_KPT_FINE_GMAX" "$CUT_KPT_FINE_GRID_SCALE" "$KPOINT_CUTOFF" )
	    KPT_SEED=$( generate_seed $SEED $KPOINT_CUTOFF $KPT_STRING $KPT_FINE_GMAX )
	    SEED_TMP_ARR+=("${KPT_SEED}")

	    # If the output file extists and has completed then we are done, so cycle to the nest one
	    if [ $(castep_output_completed $KPT_SEED) -eq 1 ]; then
		add_warning "Found valid output .castep file for ${KPT_SEED}, skipping" "TRUE"
		KPT=$( echo "$KPT + $KPOINT_GRID_STEP" | bc ) # Remember to iterate
		modify_param_file_comment $KPT_SEED "KPT"
		print_warnings "TRUE"
		err_abort
		continue
	    fi

	    echo "    Generating input files for kpoint grid ${KPT_STRING}; ${KPT_SEED}"

	    # Delete all of the files corresponding to the current seed if the previous run was incomplete
	    delete_old_run "${KPT_SEED}" "${DEFAULT_DELETE}"

	    # Copy over the master parameter files
	    cp ../${SEED}.cell  ${KPT_SEED}.cell
	    cp ../${SEED}.param ${KPT_SEED}.param

	    # Modify the cell and param files based on current cutoff and kpoint grid
	    modify_param_file $KPT_SEED $KPOINT_CUTOFF $KPT_FINE_GMAX $CONVERGE_STRESS $CONVERGE_COLLINEAR_SPIN $CONVERGE_VECTOR_SPIN $REUSE $SUPRESS_EXCESS_FILES
	    modify_param_file_comment $KPT_SEED "KPT"
	    modify_cell_file  $KPT_SEED ${KPT_GRID[@]}

	    # Add in checkfiles for reusing if option given for all but first or if a checkfile exists
	    if [ "${REUSE^^}" == "TRUE" ]; then
		# Required temp vars
		KPT_GRID_TMP=($(kpoint_grid_iterate `echo "$KPT - $KPOINT_GRID_STEP" | bc` ${KPOINT_GRID_MIN[@]}))
		KPT_STRING_TMP="${KPT_GRID_TMP[0]}x${KPT_GRID_TMP[1]}x${KPT_GRID_TMP[2]}"
		PREV_SEED=$( generate_seed $SEED $KPOINT_CUTOFF $KPT_STRING_TMP )
		if [ -f "${PREV_SEED}.check" ] || [ $FIRST_LOOP != 1 ]; then
		    modify_param_file_reuse $KPT_SEED $PREV_SEED
		fi
	    fi
	    FIRST_LOOP=0

	    print_warnings "TRUE"
	    err_abort

	    # Iterate
	    KPT=$( echo "$KPT + $KPOINT_GRID_STEP" | bc )

	done

    fi

    #######################################
    # Create the cutoff convergence files #
    #######################################

    if [ "${RUN_CUTOFF^^}" == "TRUE" ]; then

	# Loop over all the required cutoffs
	CUT=$CUTOFF_MIN
	while [ $CUT -le $CUTOFF_MAX ]; do

	    # Generate a seed for this cutoff and kpoint grid
	    CUT_FINE_GMAX=$( get_current_fine_Gmax "$CUT_KPT_FINE_GMAX" "$CUT_KPT_FINE_GRID_SCALE" "$CUT" )
	    CUT_SEED=$( generate_seed $SEED $CUT `kpoint_grid_string ${CUTOFF_KPOINT[@]}` $CUT_FINE_GMAX )

	    # Check if we have already generated inputs for this as a part of the kpoint convergence
	    for VAL in "${SEED_TMP_ARR[@]}"; do
		if [[ "$CUT_SEED" == "$VAL" ]]; then
		    add_warning "Inputs generated as part of kpoint convergence test for ${CUT_SEED}, skipping" "TRUE"
		    CUT=$((CUT+CUTOFF_STEP)) # Remember to iterate
		    modify_param_file_comment $CUT_SEED "CUT"
		    print_warnings "TRUE"
		    err_abort
		    continue 2
		fi
	    done

	    # If the output file extists and has completed then we are done, so cycle to the nest one
	    if [ $(castep_output_completed $CUT_SEED) -eq 1 ]; then
		add_warning "Found valid output .castep file for ${CUT_SEED}, skipping" "TRUE"
		CUT=$((CUT+CUTOFF_STEP)) # Remember to iterate
		modify_param_file_comment $CUT_SEED "CUT"
		print_warnings "TRUE"
		err_abort
		continue
	    fi

	    echo "    Generating input files for cutoff ${CUT} eV; ${CUT_SEED}"

	    # Delete all of the files corresponding to the current seed if the previous run was incomplete
	    delete_old_run "${CUT_SEED}" "${DEFAULT_DELETE}"

	    # Copy over the master parameter files
	    cp ../${SEED}.cell  ${CUT_SEED}.cell
	    cp ../${SEED}.param ${CUT_SEED}.param
	    SEED_TMP_ARR+=("${CUT_SEED}")

	    # Modify the cell and param files based on current cutoff and kpoint grid
	    modify_param_file $CUT_SEED $CUT $CUT_FINE_GMAX $CONVERGE_STRESS $CONVERGE_COLLINEAR_SPIN $CONVERGE_VECTOR_SPIN $REUSE $SUPRESS_EXCESS_FILES
	    modify_param_file_comment $CUT_SEED "CUT"
	    modify_cell_file  $CUT_SEED ${CUTOFF_KPOINT[@]}

	    # Add in checkfiles for reusing if option given for all but first or if a checkfile exists
	    if [ "${REUSE^^}" == "TRUE" ]; then
		PREV_SEED=$( generate_seed $SEED $((CUT-CUTOFF_STEP)) `kpoint_grid_string ${CUTOFF_KPOINT[@]}` )
		if [ -f "${PREV_SEED}.check" ] || [ $CUT -ne $CUTOFF_MIN ]; then
		    modify_param_file_reuse $CUT_SEED $PREV_SEED
		fi
	    fi

	    print_warnings "TRUE"
	    err_abort

	    # Iterate
	    CUT=$((CUT+CUTOFF_STEP))

	done

    fi

    ##########################################
    # Create the fine Gmax convergence files #
    ##########################################

    if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then

	# Loop over all the required cutoffs
	FINE_GMAX=$FINE_GMAX_MIN
	while [ $( check_bc_logical " $FINE_GMAX < $FINE_GMAX_MAX " ) -eq 1 ]; do

	    # Generate a seed for this cutoff and kpoint grid
	    GMAX_SEED=$( generate_seed $SEED $FINE_GMAX_CUTOFF `kpoint_grid_string ${FINE_GMAX_KPOINT[@]}` $FINE_GMAX )

	    # Check if we have already generated inputs for this as a part of the kpoint convergence
	    for VAL in "${SEED_TMP_ARR[@]}"; do
		if [[ "$GMAX_SEED" == "$VAL" ]]; then
		    add_warning "Inputs generated as part of kpoint/cutoff convergence test for ${GMAX_SEED}, skipping" "TRUE"
		    FINE_GMAX=$( bc_W " $FINE_GMAX + $FINE_GMAX_STEP " ) # Remember to iterate
		    modify_param_file_comment $GMAX_SEED "FGMAX"
		    print_warnings "TRUE"
		    err_abort
		    continue 2
		fi
	    done

	    # If the output file extists and has completed then we are done, so cycle to the nest one
	    if [ $(castep_output_completed $GMAX_SEED) -eq 1 ]; then
		add_warning "Found valid output .castep file for ${GMAX_SEED}, skipping" "TRUE"
		FINE_GMAX=$( bc_W " $FINE_GMAX + $FINE_GMAX_STEP " ) # Remember to iterate
		modify_param_file_comment $GMAX_SEED "FGMAX"
		print_warnings "TRUE"
		err_abort
		continue
	    fi

	    echo "    Generating input files for fine Gmax $( round_to_dec_places ${FINE_GMAX} 4 ) 1/ang; ${GMAX_SEED}"

	    # Delete all of the files corresponding to the current seed if the previous run was incomplete
	    delete_old_run "${GMAX_SEED}" "${DEFAULT_DELETE}"

	    # Copy over the master parameter files
	    cp ../${SEED}.cell  ${GMAX_SEED}.cell
	    cp ../${SEED}.param ${GMAX_SEED}.param
	    SEED_TMP_ARR+=("${GMAX_SEED}")

	    # Modify the cell and param files based on current cutoff and kpoint grid
	    modify_param_file $GMAX_SEED $FINE_GMAX_CUTOFF $FINE_GMAX $CONVERGE_STRESS $CONVERGE_COLLINEAR_SPIN $CONVERGE_VECTOR_SPIN $REUSE $SUPRESS_EXCESS_FILES
	    modify_param_file_comment $GMAX_SEED "FGMAX"
	    modify_cell_file  $GMAX_SEED ${FINE_GMAX_KPOINT[@]}

	    # Add in checkfiles for reusing if option given for all but first or if a checkfile exists
	    if [ "${REUSE^^}" == "TRUE" ]; then
		PREV_SEED=$( generate_seed $SEED $FINE_GMAX_CUTOFF `kpoint_grid_string ${FINE_GMAX_KPOINT[@]}` $(bc_W " $FINE_GMAX - $FINE_GMAX_STEP ") )
		if [ -f "${PREV_SEED}.check" ] || [ $( check_bc_same_float $FINE_GMAX $FINE_GMAX_MIN ) -eq 0 ]; then
		    modify_param_file_reuse $GMAX_SEED $PREV_SEED
		fi
	    fi

	    print_warnings "TRUE"
	    err_abort

	    FINE_GMAX=$( bc_W " $FINE_GMAX + $FINE_GMAX_STEP " ) # Remember to iterate

	done

    fi

fi



###########################################
#                                         #
#      RUN CASTEP ON RELEVANT INPUTS      #
#                                         #
###########################################



if [ "${RUN_CASTEP^^}" == "TRUE" ]; then

    echo ""
    echo "===================================================================================================="
    echo ""
    echo "Performing CASTEP Calculations"
    echo "------------------------------"
    echo ""

    # Create an empty array for all seedas to be ran to be placed in
    SEEDS_TO_RUN=()

    # Run for the cutoff convergence
    if [ "${RUN_CUTOFF^^}" == "TRUE" ]; then
	# Loop over all the required cutoffs
	CUT=$CUTOFF_MIN
	while [ $CUT -le $CUTOFF_MAX ]; do
	    # Generate a seed for this cutoff and kpoint grid
	    CUT_FINE_GMAX=$( get_current_fine_Gmax "$CUT_KPT_FINE_GMAX" "$CUT_KPT_FINE_GRID_SCALE" "$CUT" )
	    SEEDS_TO_RUN+=($( generate_seed $SEED $CUT `kpoint_grid_string ${CUTOFF_KPOINT[@]}` $CUT_FINE_GMAX ))
	    CUT=$((CUT+CUTOFF_STEP)) # Iterate
	done
    fi

    # Create or modify the cutoff convergence tests (if required)
    if [ "${RUN_KPOINT^^}" == "TRUE" ]; then

	# Loop over all the required kpoint grids
	KPT=$( get_lowest_integer_from_array ${KPOINT_GRID_MIN[@]} )
	while [ $KPT -le $KPOINT_GRID_MAX ]; do

	    # Generate the new kpoint grid
	    if [ $KPT -eq $(get_lowest_integer_from_array ${KPOINT_GRID_MIN[@]}) ]; then
		# On the initial loop, so neednt change the kpoint grid
		KPT_GRID=(${KPOINT_GRID_MIN[@]})
	    else
		# Iterate the next kpoint grid
		KPT_GRID=($(kpoint_grid_iterate $KPT ${KPOINT_GRID_MIN[@]}))
	    fi

	    # Get a string version of the kpoint grid
	    KPT_STRING="${KPT_GRID[0]}x${KPT_GRID[1]}x${KPT_GRID[2]}"

	    # Generate a seed for this cutoff and kpoint grid
	    KPT_FINE_GMAX=$( get_current_fine_Gmax "$CUT_KPT_FINE_GMAX" "$CUT_KPT_FINE_GRID_SCALE" "$KPOINT_CUTOFF" )
	    SEEDS_TO_RUN+=($( generate_seed $SEED $KPOINT_CUTOFF $KPT_STRING $KPT_FINE_GMAX ))
	    KPT=$( echo "$KPT + $KPOINT_GRID_STEP" | bc ) # Iterate

	done

    fi

    if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then
	# Loop over all the required fine Gmax
	FINE_GMAX=$FINE_GMAX_MIN
	while [ $( check_bc_logical " $FINE_GMAX < $FINE_GMAX_MAX " ) -eq 1 ]; do
	    # Generate a seed for this cutoff and kpoint grid
	    SEEDS_TO_RUN+=($( generate_seed $SEED $FINE_GMAX_CUTOFF `kpoint_grid_string ${FINE_GMAX_KPOINT[@]}` $FINE_GMAX ))
	    FINE_GMAX=$( bc_W " $FINE_GMAX + $FINE_GMAX_STEP " ) # iterate
	done
    fi

    # Remove any duplicates from the array of seeds to run, can double up if we have the same kpoint grid
    # and cutoff in the kpoint and cutoff convergence tests
    SEEDS_TO_RUN=( $( remove_duplicates_from_array "${SEEDS_TO_RUN[@]}" ) )

    # Use xargs to perform all CASTEP calculations, with parellism if requested
    # Need to export the command to all subshells so it can be accessed by xargs
    castep_converger_castep_command="${CASTEP_CMD}"
    export castep_converger_castep_command

    # The following script is what is batched out to subshells
    # NOTE: I am using eval here, but only in a subshell, so this should be ok...?
    run_castep_fn() {
	if [ $(castep_output_completed $1) -eq 1 ]; then
            echo "CASTEP calculation found for cutoff $1, skipping"
	else
            echo "Running CASTEP calculation for $1 by executing:"
            echo "        ${castep_converger_castep_command} ${1}"
            echo ""
            ${castep_converger_castep_command} ${1}
            echo ""
            if [ -f "${1}*.err" ]; then
		echo "! WARNING: ${1} exited with an error"
            else
		echo "        Calculation finished for ${castep_converger_castep_command} ${1}"
            fi
	fi
	echo ""
    }
    export -f run_castep_fn
    export -f castep_output_completed

    # Use xargs to asynchronously parellise over a number of processes
    printf "%s\n" "${SEEDS_TO_RUN[@]}" | xargs -P "${NUM_PROCESSES}" -I '{}' bash -c 'run_castep_fn "$@"' _ '{}'

fi



###########################################
#                                         #
#      PERFORM CONVERGENCE ANALYSIS       #
#                                         #
###########################################



if [ "${RUN_DATA_ANALYSIS^^}" == "TRUE" ]; then

    echo ""
    echo "===================================================================================================="
    echo ""
    echo "Analysing Convergence"
    echo "---------------------"
    echo ""

    # Go back out to the root directory
    cd ../

    # Iterate through all output files that have completed and copy the convergence parameter
    # Initially this is the cell enthalpy
    echo "Getting convergence parameters from all .castep output files, i.e. ${SEED}_${ROOT_DIR_POSTFIX}/*.castep"
    echo ""
    OUTPUT_FILES=(${SEED}_${ROOT_DIR_POSTFIX}/*.castep)
    DATA_FILE="${SEED}_converger.dat"

    # Check if we need to clean up old data
    if [ -f $DATA_FILE ]; then
	if [ "${DEFAULT_DELETE^^}" == "TRUE" ]; then
	    echo "! WARNING: Found ${DATA_FILE}, deleting as DEFAULT_DELETE == TRUE."
	    rm "$DATA_FILE"
	else
	    read -p "Found '$DATA_FILE'. Do you want to delete it? (y/n): " input
	    if [ "$input" = "y" ]; then
		rm "$DATA_FILE"
		echo "Removed old $DATA_FILE."
	    else
		echo "Will append to current $DATA_FILE."
	    fi
	fi
	echo ""
    fi

    # Read data from each output file
    for F in "${OUTPUT_FILES[@]}"; do

	S="${F%.castep}"
	OUTPUT_STRING=""

	# Make sure the .castep output file completed successfully
	if [ $(castep_output_completed $S) -ne 1 ]; then
	    echo "! WARNING : ${S}.castep did not complete successfully !"
	    echo ""
	    continue
	fi

	echo "Getting convergence data from $S"

	# Get the units used
	UNIT_ENERGY=$( grep $F -e "output         energy unit" | tail -n 1 | awk '{ print $5}' )
	UNIT_FORCE=$( grep $F -e "output          force unit" |  tail -n 1 |awk '{ print $5}' )
	UNIT_PRESSURE=$( grep $F -e "output       pressure unit" | tail -n 1 | awk '{ print $5}' )
	UNIT_SPIN=$( grep $F -e "output           spin unit" | tail -n 1 | awk '{ print $5}' )
	UNIT_RECIP_LEN=$( grep $F -e "output     inv_length unit" | tail -n 1 | awk '{ print $5}' )

	# If there isnt an output file then create one and add header row
	if [ ! -f $DATA_FILE ]; then

	    OUTPUT_STRING+="Cutoff_(${UNIT_ENERGY}/ion) Kpoint fine_Gmax_(${UNIT_RECIP_LEN}) fine_grid_scale"
	    OUTPUT_STRING+=" Total_time_(s) Peak_memory_(kB)"
	    OUTPUT_STRING+=" Cutoff_run Kpt_run fGmax_run"
	    [ "${CONVERGE_ENERGY^^}" == "TRUE" ] && OUTPUT_STRING+=" Energy_(${UNIT_ENERGY}/ion)"
	    [ "${CONVERGE_FORCE^^}"  == "TRUE" ] && OUTPUT_STRING+=" Force_(${UNIT_FORCE})"
	    [ "${CONVERGE_STRESS^^}" == "TRUE" ] && OUTPUT_STRING+=" Stress_(${UNIT_PRESSURE})"
	    [ "${CONVERGE_COLLINEAR_SPIN^^}" == "TRUE" ] && OUTPUT_STRING+=" Spin_(${UNIT_SPIN}) |Spin|_(${UNIT_SPIN})"
	    if [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then
		OUTPUT_STRING+=" Spin_x Spin_y Spin_z"
		OUTPUT_STRING+=" |Spin_x| |Spin_y| |Spin_z|"
	    fi

	    echo $OUTPUT_STRING > $DATA_FILE
	    OUTPUT_STRING=""

	fi

	# Get the current cutoff, kpoint grid and fine gmax
	O_CUTOFF=$( grep $F -e "plane wave basis set cut-off" | tail -n 1 | awk '{ print $7 }' )
	O_KPOINT=$( grep $F -e "MP grid size for SCF calculation is" | tail -n 1 | awk '{ print $8 "x" $9 "x" $10 }' )
	O_FINE_GMAX=$( grep $F -e "size of   fine   gmax" | tail -n 1 | awk '{ print $6 }' )
	OUTPUT_STRING+="${O_CUTOFF} ${O_KPOINT} ${O_FINE_GMAX}"

	# Get the current fine_grid_scale from the current cutoff and finr_Gmax values
	K_CUT=$( radius_from_E_to_k "${O_CUTOFF}" )
	CURR_FINE_GRID_SCALE=$( round_to_dec_places `bc_W "${O_FINE_GMAX} / ${K_CUT} "` 2 )
	OUTPUT_STRING+=" ${CURR_FINE_GRID_SCALE}"

	# Get the cost approximation for time and memory use
	O_TOT_TIME=$( grep $F -e "Total time          =" | tail -n 1 | awk '{ print $4 }' )
	O_TOT_MEM=$( grep $F -e "Peak Memory Use     =" | tail -n 1 | awk '{ print $5 }' )
	OUTPUT_STRING+=" ${O_TOT_TIME} ${O_TOT_MEM}"

	# Get the information as to what type of convergence runs this is being used in
	PARAM_COMMENT=$( get_string_in_file_uncommented ${S}.param "COMMENT" )

	if [ $( check_if_string_contains_substring "${PARAM_COMMENT}" "CUT" ) -eq 1 ]; then
	    OUTPUT_STRING+=" T"
	else
	    OUTPUT_STRING+=" F"
	fi
	if [ $( check_if_string_contains_substring "${PARAM_COMMENT}" "KPT" ) -eq 1 ]; then
	    OUTPUT_STRING+=" T"
	else
	    OUTPUT_STRING+=" F"
	fi
	if [ $( check_if_string_contains_substring "${PARAM_COMMENT}" "FGMAX" ) -eq 1 ]; then
	    OUTPUT_STRING+=" T"
	else
	    OUTPUT_STRING+=" F"
	fi

	# Get the number of ions, we will generally need this
	NUM_IONS=$( grep $F -e "Total number of ions in cell =" | tail -n 1 | awk '{ print $8 }')

	# Get total corrected energy per ion
	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    TOT_E_ION=$( echo " $( grep $F -e "Final energy" | tail -n 1 | awk '{ print $(NF-1) }' ) / $NUM_IONS " | bc -l )
	    OUTPUT_STRING+=" ${TOT_E_ION}"
	fi

	# Get the maximum force
	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    MAX_FORCE=$( grep $F -e "*** Forces ***" -A $(($NUM_IONS+5)) | tail -n $NUM_IONS | \
			     awk '{ elements = elements $4 " " $5 " " $6 " " } END { print elements }')
	    MAX_FORCE=$( find_num_with_largest_magnitude $MAX_FORCE )
	    MAX_FORCE=$( abs $MAX_FORCE )
	    OUTPUT_STRING+=" ${MAX_FORCE}"
	fi

	# If stresses calculated then find those
	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    if [ $( grep $F -e "*** Stress Tensor ***" | wc -l ) -eq 1 ]; then
		MAX_STRESS=$( grep $F -e "*** Stress Tensor ***" -A 8 | tail -n 3 | \
				  awk '{ elements = elements $3 " " $4 " " $5 " " } END { print elements }')
		MAX_STRESS=$( find_num_with_largest_magnitude $MAX_STRESS )
		MAX_STRESS=$( abs $MAX_STRESS )
	    else
		echo "! WARNING : Converge stress option set to true, but no stresses in ${F}.castep,"
		echo "!           Assigning arbirary stress of 0."
		MAX_STRESS="0"
	    fi
	    OUTPUT_STRING+=" ${MAX_STRESS}"
	fi

	# If Converging spins, then look for the last integrated spin and integrated spin magnitude
	if [ "${CONVERGE_COLLINEAR_SPIN^^}" == "TRUE" ]; then
	    if [ $( grep $F -e "Integrated Spin Density" | wc -l ) -ge 1 ]; then
		INT_SPIN=$( grep $F -e "Integrated Spin Density" | tail -n 1 | awk '{ print $5 }' )
		INT_MAG_SPIN=$( grep $F -e "Integrated |Spin Density|" | tail -n 1 | awk '{ print $5 }' )
	    else
		echo "! WARNING : Converge collinear spin option set to true, but no integrated spin densities in ${F}.castep,"
		echo "!           Assigning arbirary spin of 0."
		INT_SPIN="0"
		INT_MAG_SPIN="0"
	    fi
	    OUTPUT_STRING+=" ${INT_SPIN} ${INT_MAG_SPIN}"
	fi

	# If converging the collinear spin we need all the final collinear spin values
	if [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then

	    if [ $( grep $F -e "2*Integrated Spin Density (Sx,Sy,Sz)" | wc -l ) -ge 1 ]; then
		INT_SPIN=$( grep $F -e "2*Integrated Spin Density (Sx,Sy,Sz)" | tail -n 1 | awk '{ print $6 " " $7 " " $8 }' )
		INT_MAG_SPIN=$( grep $F -e "2*Integrated |Spin Density| (|Sx|,|Sy|,|Sz|)" | tail -n 1 | awk '{ print $6 " " $7 " " $8 }' )
	    else
		echo "! WARNING : Converge vector spin option set to true, but no integrated spin densities in ${F}.castep,"
		echo "!           Assigning arbirary spin of 0 0 0."
		INT_SPIN="0 0 0"
		INT_MAG_SPIN="0 0 0"
	    fi
	    OUTPUT_STRING+=" ${INT_SPIN} ${INT_MAG_SPIN}"

	fi

	# Output the data from this .castep file
	echo $OUTPUT_STRING >> $DATA_FILE

    done


    ###############################################
    #                                             #
    # CREATE SCRIPT TO PLOT ALL THE RELEVANT DATA #
    #                                             #
    ###############################################



    PLOT_SCRIPT="${SEED}_converger.py"
    ENERGY_TOL_TOTAL=$( add_leading_zero `echo " ${ENERGY_TOL} * ${NUM_IONS} " | bc -l` )
    SYMLOG_CUTOFF="1e-8"
    NUM_GRAPHS=$( count_num_true "${RUN_CUTOFF}" "${RUN_KPOINT}" "${RUN_FINE_GMAX}" )

    echo "import matplotlib.pyplot as plt" > $PLOT_SCRIPT
    echo "from matplotlib.ticker import LogLocator" >> $PLOT_SCRIPT
    echo "import pandas as pd" >> $PLOT_SCRIPT
    echo "import numpy as np" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "def multiply_kpoint_strings(K):" >> $PLOT_SCRIPT
    echo "    kpoints = K.split('x')" >> $PLOT_SCRIPT
    echo "    total_K = 1" >> $PLOT_SCRIPT
    echo "    for kpt in kpoints:" >> $PLOT_SCRIPT
    echo "        total_K *= int(kpt)" >> $PLOT_SCRIPT
    echo "    return total_K" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "def smallest_magnitude(arr):" >> $PLOT_SCRIPT
    echo "    threshold = 1E-21" >> $PLOT_SCRIPT
    echo "    above_threshold = [x for x in arr if x > threshold]" >> $PLOT_SCRIPT
    echo "    if len(above_threshold) == 0:" >> $PLOT_SCRIPT
    echo "        return 1" >> $PLOT_SCRIPT
    echo "    else:" >> $PLOT_SCRIPT
    echo "        smallest_magnitude_value = abs(min(above_threshold, key=abs))" >> $PLOT_SCRIPT
    echo "        rounded_magnitude = 10 ** (int(np.log10(smallest_magnitude_value)) - 1)" >> $PLOT_SCRIPT
    echo "        return rounded_magnitude" >> $PLOT_SCRIPT
    if [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then
	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "def euclidean_distance(V1,V2):" >> $PLOT_SCRIPT
	echo "    return np.linalg.norm(V1-V2)" >> $PLOT_SCRIPT
    fi
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "df = pd.read_csv('${DATA_FILE}',sep=' ',header=0)" >> $PLOT_SCRIPT
    echo "height_base = 4" >> $PLOT_SCRIPT
    if [ "${RUN_CUTOFF^^}" == "TRUE" ] && [ "${RUN_KPOINT^^}" == "TRUE" ]; then
	if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then
            echo "fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(10, height_base*3))" >> $PLOT_SCRIPT
	else
            echo "fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, height_base*2))" >> $PLOT_SCRIPT
	fi
    elif [ "${RUN_CUTOFF^^}" == "TRUE" ]; then
	if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then
            echo "fig, (ax1, ax3) = plt.subplots(2, 1, figsize=(10, height_base*2))" >> $PLOT_SCRIPT
	else
            echo "fig, ax1 = plt.subplots(1, 1, figsize=(10, height_base))" >> $PLOT_SCRIPT
	fi
    elif [ "${RUN_KPOINT^^}" == "TRUE" ]; then
	if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then
            echo "fig, (ax2, ax3) = plt.subplots(2, 1, figsize=(10, height_base*2))" >> $PLOT_SCRIPT
	else
            echo "fig, ax2 = plt.subplots(1, 1, figsize=(10, height_base))" >> $PLOT_SCRIPT
	fi
    elif [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then
	echo "fig, ax3 = plt.subplots(1, 1, figsize=(10, height_base))" >> $PLOT_SCRIPT
    fi
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT
    if [ "${RUN_CUTOFF^^}" == "TRUE" ]; then
	echo "# Top subplot - Cutoff vs. Convergence Parameters" >> $PLOT_SCRIPT
	echo "second_smallest_val = []" >> $PLOT_SCRIPT
	echo "cutoff_df = df[df.duplicated('Kpoint', keep=False) & (df['Cutoff_run'] == 'T')] # Keep only rows where there is more than one cutoff convergence value" >> $PLOT_SCRIPT
	echo "for name, group in cutoff_df.groupby('Kpoint'):" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    if len(group.index) < 2: continue # Only bother for groups with > 1 member" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    max_cutoff = group['Cutoff_(${UNIT_ENERGY}/ion)'].max() # Max cutoff value over this varying cutoff" >> $PLOT_SCRIPT
	echo "    group = group.sort_values(by='Cutoff_(${UNIT_ENERGY}/ion)', ascending=True) # Sort by cutoff" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Get the set value for either fine G max or fine grid scale used in convergence test, just for adding to legend" >> $PLOT_SCRIPT
	echo "    if group['fine_grid_scale'].value_counts().max() == len(group.index):" >> $PLOT_SCRIPT
	echo "        # All the fine grid scales are the same, so must be using constant fine gris scale for this convergence test" >> $PLOT_SCRIPT
	echo "        Gmax_legend=f\"fGridScale {group['fine_grid_scale'].iloc[0]}\"" >> $PLOT_SCRIPT
	echo "    else:" >> $PLOT_SCRIPT
	echo "        # There are some different fine grid scales, so we must be using fine Gmax as a lower bound" >> $PLOT_SCRIPT
	echo "        Gmax_legend=f\"fGmax {group['fine_Gmax_(${UNIT_RECIP_LEN})'].mode().values[0]}\"" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Plot the cost of each calculation" >> $PLOT_SCRIPT
	echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], group['Total_time_(s)'], label=f'Total time (s), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	echo "    second_smallest_val.append(smallest_magnitude(group['Total_time_(s)'].iloc[:-1]))" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Calculate the difference between the current value and that at the max cutoff for the given kpoint grid" >> $PLOT_SCRIPT
	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    echo "    energy_diff = np.absolute(group['Energy_(${UNIT_ENERGY}/ion)'] - group[group['Cutoff_(${UNIT_ENERGY}/ion)'] == max_cutoff]['Energy_(${UNIT_ENERGY}/ion)'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], energy_diff, label=f'|Energy diff| (${UNIT_ENERGY}/ion), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    echo "    force_diff = np.absolute(group['Force_(${UNIT_FORCE})'] - group[group['Cutoff_(${UNIT_ENERGY}/ion)'] == max_cutoff]['Force_(${UNIT_FORCE})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], force_diff, label=f'|Force diff| (${UNIT_FORCE}), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    echo "    stress_diff = np.absolute(group['Stress_(${UNIT_PRESSURE})'] - group[group['Cutoff_(${UNIT_ENERGY}/ion)'] == max_cutoff]['Stress_(${UNIT_PRESSURE})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], stress_diff, label=f'|Stress diff| (${UNIT_PRESSURE}), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_COLLINEAR_SPIN^^}" == "TRUE" ]; then
	    echo "    spin_diff = np.absolute(group['Spin_(${UNIT_SPIN})'] - group[group['Cutoff_(${UNIT_ENERGY}/ion)'] == max_cutoff]['Spin_(${UNIT_SPIN})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], spin_diff, label=f'|Spin diff| (${UNIT_SPIN}), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	    echo "    spin_mag_diff = np.absolute(group['|Spin|_(${UNIT_SPIN})'] - group[group['Cutoff_(${UNIT_ENERGY}/ion)'] == max_cutoff]['|Spin|_(${UNIT_SPIN})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], spin_mag_diff, label=f'||Spin| diff| (${UNIT_SPIN}), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_mag_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then
	    echo "    spin_diff = group.apply(lambda row: euclidean_distance(row[['Spin_x', 'Spin_y', 'Spin_z']],group[group['Cutoff_(${UNIT_ENERGY}/ion)'] == max_cutoff][['Spin_x', 'Spin_y', 'Spin_z']].iloc[0]),axis=1)" >> $PLOT_SCRIPT
	    echo "    ax1.plot(group['Cutoff_(${UNIT_ENERGY}/ion)'], spin_diff, label=f'Euclid Dist Between Spin Vecs, {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	echo "" >> $PLOT_SCRIPT
	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    echo "ax1.axhline(y=${ENERGY_TOL_TOTAL}, color='k', linestyle='--', label='Energy tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${ENERGY_TOL_TOTAL}]))" >> $PLOT_SCRIPT
	fi
	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    echo "ax1.axhline(y=${FORCE_TOL}, color='k', linestyle='-.', label='Force tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${FORCE_TOL}]))" >> $PLOT_SCRIPT
	fi
	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    echo "ax1.axhline(y=${STRESS_TOL}, color='k', linestyle=':', label='Stress tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${STRESS_TOL}]))" >> $PLOT_SCRIPT
	fi
	echo "" >> $PLOT_SCRIPT
	echo "ax1.set_ylim(ymin=0)" >> $PLOT_SCRIPT
	echo "ax1.set_yscale('symlog', linthresh=np.min(second_smallest_val))" >> $PLOT_SCRIPT
	echo "ax1.yaxis.set_minor_locator(LogLocator(base=10,subs=np.arange(2, 10)))" >> $PLOT_SCRIPT
	echo "ax1.set_title('Cutoff Convergence')" >> $PLOT_SCRIPT
	echo "ax1.set_xlabel('Cutoff (${UNIT_ENERGY})')" >> $PLOT_SCRIPT
	echo "ax1.set_ylabel(f'Value, diff or absolute\n(log scale for |y|>{np.min(second_smallest_val):.1e})')" >> $PLOT_SCRIPT
	echo "ax1.legend(loc='center left', bbox_to_anchor=(1, 0.5))" >> $PLOT_SCRIPT
	echo "ax1.grid(True,which='both',linewidth=0.4)" >> $PLOT_SCRIPT

	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
    fi



    if [ "${RUN_KPOINT^^}" == "TRUE" ]; then
	echo "# Middle subplot - Kpoint vs. Convergence Parameters" >> $PLOT_SCRIPT
	echo "second_smallest_val = []" >> $PLOT_SCRIPT
	echo "all_x_tick_positions = []" >> $PLOT_SCRIPT
	echo "all_x_tick_labels = []" >> $PLOT_SCRIPT
	echo "df['kpt_mult'] = df['Kpoint'].apply(multiply_kpoint_strings) # Add a row with number kpoints" >> $PLOT_SCRIPT
	echo "kpt_df = df[df.duplicated('Cutoff_(${UNIT_ENERGY}/ion)', keep=False) & (df['Kpt_run'] == 'T')] # Keep only rows where there is more than one kpoint convergence value" >> $PLOT_SCRIPT
	echo "for name, group in kpt_df.groupby('Cutoff_(${UNIT_ENERGY}/ion)'):" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    if len(group.index) < 2: continue # Only bother for groups with > 1 member" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    max_kpt = group['kpt_mult'].max() # Max kpointvalue over all varying cutoffs" >> $PLOT_SCRIPT
	echo "    group = group.sort_values(by='kpt_mult', ascending=True) # Sort by kpoint" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Get the set value for either fine G max or fine grid scale used in convergence test, just for adding to legend" >> $PLOT_SCRIPT
	echo "    if group['fine_grid_scale'].value_counts().max() == len(group.index) and group['fine_Gmax_(1/A)'].value_counts().max() != len(group.index):" >> $PLOT_SCRIPT
	echo "        # All the fine grid scales are the same, so must be using constant fine gris scale for this convergence test" >> $PLOT_SCRIPT
	echo "        Gmax_legend=f\"fGridScale {group['fine_grid_scale'].iloc[0]}\"" >> $PLOT_SCRIPT
	echo "    else:" >> $PLOT_SCRIPT
	echo "        # There are some different fine grid scales, so we must be using fine Gmax as a lower bound" >> $PLOT_SCRIPT
	echo "        Gmax_legend=f\"fGmax {group['fine_Gmax_(1/A)'].mode().values[0]}\"" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Plot the cost of each calculation" >> $PLOT_SCRIPT
	echo "    ax2.plot(group['kpt_mult'], group['Total_time_(s)'], label=f'Total time (s), {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	echo "    second_smallest_val.append(smallest_magnitude(group['Total_time_(s)'].iloc[:-1]))" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Calculate the difference between the current value and that at the max kpoint for the given cutoff" >> $PLOT_SCRIPT

	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    echo "    energy_diff = np.absolute(group['Energy_(${UNIT_ENERGY}/ion)'] - group[group['kpt_mult'] == max_kpt]['Energy_(${UNIT_ENERGY}/ion)'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax2.plot(group['kpt_mult'], energy_diff, label=f'Energy (${UNIT_ENERGY}/ion), {name} ${UNIT_ENERGY}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    echo "    force_diff = np.absolute(group['Force_(${UNIT_FORCE})'] - group[group['kpt_mult'] == max_kpt]['Force_(${UNIT_FORCE})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax2.plot(group['kpt_mult'], force_diff, label=f'Force (${UNIT_FORCE}), {name} ${UNIT_ENERGY}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    echo "    stress_diff = np.absolute(group['Stress_(${UNIT_PRESSURE})'] - group[group['kpt_mult'] == max_kpt]['Stress_(${UNIT_PRESSURE})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax2.plot(group['kpt_mult'], stress_diff, label=f'Stress (${UNIT_PRESSURE}), {name} ${UNIT_ENERGY}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_COLLINEAR_SPIN^^}" == "TRUE" ]; then
	    echo "    spin_diff = np.absolute(group['Spin_(${UNIT_SPIN})'] - group[group['kpt_mult'] == max_kpt]['Spin_(${UNIT_SPIN})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax2.plot(group['kpt_mult'], spin_diff, label=f'Spin, (${UNIT_SPIN}) {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	    echo "    spin_mag_diff = np.absolute(group['|Spin|_(${UNIT_SPIN})'] - group[group['kpt_mult'] == max_kpt]['|Spin|_(${UNIT_SPIN})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax2.plot(group['kpt_mult'], spin_mag_diff, label=f'|Spin|, (${UNIT_SPIN}) {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_mag_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then
	    echo "    spin_diff = group.apply(lambda row: euclidean_distance(row[['Spin_x', 'Spin_y', 'Spin_z']],group[group['kpt_mult'] == max_kpt][['Spin_x', 'Spin_y', 'Spin_z']].iloc[0]),axis=1)" >> $PLOT_SCRIPT
	    echo "    ax2.plot(group['kpt_mult'], spin_diff, label=f'Euclid Dist Between Spin Vecs, {name}, {Gmax_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	echo "" >> $PLOT_SCRIPT
	echo "    # Get the kpt_mult values where there is a valid Kpoint value for this group" >> $PLOT_SCRIPT
	echo "    x_tick_positions = group[group['Kpoint'].notnull()]['kpt_mult']" >> $PLOT_SCRIPT
	echo "    # Get the Kpoint values where they are not null for this group" >> $PLOT_SCRIPT
	echo "    x_tick_labels = group[group['Kpoint'].notnull()]['Kpoint']" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Extend the x tick lists with the kpoint labels for this group" >> $PLOT_SCRIPT
	echo "    all_x_tick_positions.extend(x_tick_positions)" >> $PLOT_SCRIPT
	echo "    all_x_tick_labels.extend(x_tick_labels)" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    echo "ax2.axhline(y=${ENERGY_TOL_TOTAL}, color='k', linestyle='--', label='Energy tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${ENERGY_TOL_TOTAL}]))" >> $PLOT_SCRIPT
	fi
	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    echo "ax2.axhline(y=${FORCE_TOL}, color='k', linestyle='-.', label='Force tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${FORCE_TOL}]))" >> $PLOT_SCRIPT
	fi
	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    echo "ax2.axhline(y=${STRESS_TOL}, color='k', linestyle=':', label='Stress tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${STRESS_TOL}]))" >> $PLOT_SCRIPT
	fi
	echo "" >> $PLOT_SCRIPT
	echo "# Set the x ticks to be from the kpoint labels not total kpoints" >> $PLOT_SCRIPT
	echo "ax2.set_xticks(all_x_tick_positions)" >> $PLOT_SCRIPT
	echo "ax2.set_xticklabels(all_x_tick_labels,rotation=90)" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "ax2.set_ylim(ymin=0)" >> $PLOT_SCRIPT
	echo "ax2.set_yscale('symlog', linthresh=np.min(second_smallest_val))" >> $PLOT_SCRIPT
	echo "ax2.yaxis.set_minor_locator(LogLocator(base=10,subs=np.arange(2, 10)))" >> $PLOT_SCRIPT
	echo "ax2.set_title('Kpoint Convergence')" >> $PLOT_SCRIPT
	echo "ax2.set_xlabel('Kpoint Grid')" >> $PLOT_SCRIPT
	echo "ax2.set_ylabel(f'|Difference from Maximum|\n(log scale for |y|>{np.min(second_smallest_val):.1e})')" >> $PLOT_SCRIPT
	echo "ax2.legend(loc='center left', bbox_to_anchor=(1, 0.5))" >> $PLOT_SCRIPT
	echo "ax2.grid(True,which='both',linewidth=0.4)" >> $PLOT_SCRIPT

	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
    fi



    if [ "${RUN_FINE_GMAX^^}" == "TRUE" ]; then
	echo "# Bottom subplot - Fine GMax vs. Convergence Parameters" >> $PLOT_SCRIPT
	echo "second_smallest_val = []" >> $PLOT_SCRIPT
	echo "gmax_df = df[df.duplicated('Kpoint', keep=False) & (df['fGmax_run'] == 'T')] # Keep only rows where there is more than one kpoint convergence value" >> $PLOT_SCRIPT
	echo "for name, group in gmax_df.groupby('Cutoff_(${UNIT_ENERGY}/ion)'):" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    if len(group.index) < 2: continue # Only bother for groups with > 1 member" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    max_Gmax = group['fine_Gmax_(${UNIT_RECIP_LEN})'].max() # Max cutoff value over this varying cutoff" >> $PLOT_SCRIPT
	echo "    group = group.sort_values(by='fine_Gmax_(${UNIT_RECIP_LEN})', ascending=True) # Sort by cutoff" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Plot the cost of each calculation" >> $PLOT_SCRIPT
	echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], group['Total_time_(s)'], label=f'Total time (s)', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	echo "    second_smallest_val.append(smallest_magnitude(group['Total_time_(s)'].iloc[:-1]))" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    Kpt_legend=f\"{group['Kpoint'].iloc[0]}\"" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "    # Calculate the difference between the current value and that at the max cutoff for the given kpoint grid" >> $PLOT_SCRIPT
	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    echo "    energy_diff = np.absolute(group['Energy_(${UNIT_ENERGY}/ion)'] - group[group['fine_Gmax_(${UNIT_RECIP_LEN})'] == max_Gmax]['Energy_(${UNIT_ENERGY}/ion)'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], energy_diff, label=f'Energy (${UNIT_ENERGY}/ion), {name} ${UNIT_ENERGY}, {Kpt_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(energy_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    echo "    force_diff = np.absolute(group['Force_(${UNIT_FORCE})'] - group[group['fine_Gmax_(${UNIT_RECIP_LEN})'] == max_Gmax]['Force_(${UNIT_FORCE})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], force_diff, label=f'Force (${UNIT_FORCE}), {name} ${UNIT_ENERGY}, {Kpt_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(force_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    echo "    stress_diff = np.absolute(group['Stress_(${UNIT_PRESSURE})'] - group[group['fine_Gmax_(${UNIT_RECIP_LEN})'] == max_Gmax]['Stress_(${UNIT_PRESSURE})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], stress_diff, label=f'Stress (${UNIT_PRESSURE}), {name} ${UNIT_ENERGY}, {Kpt_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(stress_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_COLLINEAR_SPIN^^}" == "TRUE" ]; then
	    echo "    spin_diff = np.absolute(group['Spin_(${UNIT_SPIN})'] - group[group['fine_Gmax_(${UNIT_RECIP_LEN})'] == max_Gmax]['Spin_(${UNIT_SPIN})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], spin_diff, label=f'Spin (${UNIT_SPIN}), {name} ${UNIT_ENERGY}, {Kpt_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	    echo "    spin_mag_diff = np.absolute(group['|Spin|_(${UNIT_SPIN})'] - group[group['fine_Gmax_(${UNIT_RECIP_LEN})'] == max_Gmax]['|Spin|_(${UNIT_SPIN})'].values[0])" >> $PLOT_SCRIPT
	    echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], spin_mag_diff, label=f'|Spin| (${UNIT_SPIN}), {name} ${UNIT_ENERGY}, {Kpt_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_mag_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	if [ "${CONVERGE_VECTOR_SPIN^^}" == "TRUE" ]; then
	    echo "    spin_diff = group.apply(lambda row: euclidean_distance(row[['Spin_x', 'Spin_y', 'Spin_z']],group[group['fine_Gmax_(${UNIT_RECIP_LEN})'] == max_Gmax][['Spin_x', 'Spin_y', 'Spin_z']].iloc[0]),axis=1)" >> $PLOT_SCRIPT
	    echo "    ax3.plot(group['fine_Gmax_(${UNIT_RECIP_LEN})'], spin_diff, label=f'Euclid Dist Between Spin Vecs, {name} ${UNIT_ENERGY}, {Kpt_legend}', marker='x', linestyle='-', markersize=8)" >> $PLOT_SCRIPT
	    echo "    second_smallest_val.append(smallest_magnitude(spin_diff.iloc[:-1]))" >> $PLOT_SCRIPT
	fi

	echo "" >> $PLOT_SCRIPT
	if [ "${CONVERGE_ENERGY^^}" == "TRUE" ]; then
	    echo "ax3.axhline(y=${ENERGY_TOL_TOTAL}, color='k', linestyle='--', label='Energy tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${ENERGY_TOL_TOTAL}]))" >> $PLOT_SCRIPT
	fi
	if [ "${CONVERGE_FORCE^^}" == "TRUE" ]; then
	    echo "ax3.axhline(y=${FORCE_TOL}, color='k', linestyle='-.', label='Force tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${FORCE_TOL}]))" >> $PLOT_SCRIPT
	fi
	if [ "${CONVERGE_STRESS^^}" == "TRUE" ]; then
	    echo "ax3.axhline(y=${STRESS_TOL}, color='k', linestyle=':', label='Stress tolerance')" >> $PLOT_SCRIPT
	    echo "second_smallest_val.append(smallest_magnitude([${STRESS_TOL}]))" >> $PLOT_SCRIPT
	fi
	echo "" >> $PLOT_SCRIPT
	echo "ax3.set_ylim(ymin=0)" >> $PLOT_SCRIPT
	echo "ax3.set_yscale('symlog', linthresh=np.min(second_smallest_val))" >> $PLOT_SCRIPT
	echo "ax3.yaxis.set_minor_locator(LogLocator(base=10,subs=np.arange(2, 10)))" >> $PLOT_SCRIPT
	echo "ax3.set_title('Fine Gmax Convergence')" >> $PLOT_SCRIPT
	echo "ax3.set_xlabel('Fine Gmax (${UNIT_RECIP_LEN})')" >> $PLOT_SCRIPT
	echo "ax3.set_ylabel(f'|Difference from Maximum|\n(log scale for |y|>{np.min(second_smallest_val):.1e})')" >> $PLOT_SCRIPT
	echo "ax3.legend(loc='center left', bbox_to_anchor=(1, 0.5))" >> $PLOT_SCRIPT
	echo "ax3.grid(True,which='both',linewidth=0.4)" >> $PLOT_SCRIPT

	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
	echo "" >> $PLOT_SCRIPT
    fi

    echo "# Adjust layout and display the plot" >> $PLOT_SCRIPT
    echo "plt.tight_layout()" >> $PLOT_SCRIPT
    echo "plt.savefig('${SEED}_converger.png')" >> $PLOT_SCRIPT
    echo "plt.show()" >> $PLOT_SCRIPT
    echo "" >> $PLOT_SCRIPT

fi

echo ""
