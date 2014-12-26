#!/bin/bash
#set -x

################################################################################
#                      S C R I P T    D E F I N I T I O N
################################################################################
#

#-------------------------------------------------------------------------------
# Revision History
#-------------------------------------------------------------------------------
# 20141014     Jason W. Plummer          Original: A simple script to create
#                                        ZFS VDEVs
# 20141015     Jason W. Plummer          Added support for adding VDEVs to an
#                                        existing storage pool
# 20141016     Jason W. Plummer          Modified available_disk detection such
#                                        that the list is sorted by disk size.
#                                        Human readable disk size is calculated
#                                        and presented as a colon delimited KV
#                                        pair
# 20141017     Jason W. Plummer          Fixed data sanitization issues with all
#                                        f__dev2xxx function innards
# 20141020     Jason W. Plummer          Added CLI passthrough capability
# 20141021     Jason W. Plummer          Added logging capability
# 20141023     Jason W. Plummer          Modified to fit this documentation
#                                        format.  Also fixed issue with excluded
#                                        disk detection while scraping the 
#                                        output of 'zpool status'.  Added
#                                        support for using disk partitions. 
#                                        Checks that invoking user is id=0.
#                                        Improved error checking.
# 20141226     Jason W. Plummer          Fixed errors regarding rawdisk and
#                                        and partition exclusion detection

################################################################################
# DESCRIPTION
################################################################################
#

# Name: zfshelper.sh

# This script does the following:
#
# 1. (Without arguments): Guides the invoking user through ZFS volume creation/
#    modification.  A menu of choices is presented, and simple integer entry
#    steps the invoking user through VDEV manipulation.
# 2. (With arguments): Behaves as a wrapper around 'zpool'
# 3. Logs all operations to ${LOG_DIR}/${LOG_FILE}

# Usage: /usr/local/bin/zfshelper.sh <optional arguments>
#
#    Where: optional arguments are:
#
#        partitions
#            - Changes the disk detection mode from whole raw disks to disk
#              partitions.  Script then proceeds through a guided menu
#
#        <anything else>
#            - Script assumes properly formatted zpool arguments and passes
#              them verbatim to the zpool command

################################################################################
# CONSTANTS
################################################################################
#

TERM=vt100
PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin
export TERM PATH

SUCCESS=0
ERROR=1

# ZFS Guided menu options
GUIDED_MENU[0]="create new ZFS Pool"
GUIDED_MENU[1]="add disks to an existing ZFS Pool"

# ZFS command verbs
GUIDED_COMMAND[0]="create"
GUIDED_COMMAND[1]="add"

ALL_VDEV_TYPES="mirror raidz1 raidz2 raidz3 log cache spare"
VDEV_TYPE=(${ALL_VDEV_TYPES})

OFFSET="    "

LOG_DIR=/var/log/zfs
LOG_FILE=zfshelper.log

################################################################################
# VARIABLES
################################################################################
#

exit_code=${SUCCESS}
err_msg=""

guided_command_extras=""

################################################################################
# SUBROUTINES
################################################################################

# WHAT: Subroutine f__check_command
# WHY:  This subroutine checks the contents of lexically scoped ${1} and then
#       searches ${PATH} for the command.  If found, a variable of the form
#       my_${1} is created.
# NOTE: Lexically scoped ${1} should not be null, otherwise the command for
#       which we are searching is not present via the defined ${PATH} and we
#       should complain
#
f__check_command() {
    return_code=${SUCCESS}
    my_command="${1}"

    if [ "${my_command}" != "" ]; then
        my_command_check=`unalias "${1}" > /dev/null 2>&1 ; which "${1}" 2> /dev/null`

        if [ "${my_command_check}" = "" ]; then
            return_code=${ERROR}
        else
            eval my_${my_command}="${my_command_check}"
        fi

    else
        err_msg="No command was specified"
        return_code=${ERROR}
    fi

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__id2dev
# WHY:  This subroutine locates the /dev/<entry> device associated with
#       a /dev/disk/by-id/<entry>
#
f__id2dev() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/disk/by-id/ | ${my_egrep} "${item_name}" | ${my_awk} -F'/' '{print $NF}' | ${my_sed} -e 's/[0-9]//g' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__dev2id
# WHY:  This subroutine locates the /dev/disk/by-id/<entry> associated with
#       a /dev/<entry>
#
f__dev2id() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/disk/by-id/ | ${my_egrep} "/${item_name}$" | ${my_awk} '{print $9}' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__uuid2dev
# WHY:  This subroutine locates the /dev/<entry> device associated with
#       a /dev/disk/by-uuid/<entry>
#
f__uuid2dev() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/disk/by-uuid/ | ${my_egrep} "${item_name}" | ${my_awk} -F'/' '{print $NF}' | ${my_sed} -e 's/[0-9]//g' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__dev2uuid
# WHY:  This subroutine locates the /dev/disk/by-uuid/<entry> associated with
#       a /dev/<entry>
#
f__dev2uuid() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/disk/by-uuid/ | ${my_egrep} "/${item_name}$" | ${my_awk} '{print $9}' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__path2dev
# WHY:  This subroutine locates the /dev/<entry> device associated with
#       a /dev/disk/by-path/<entry>
#
f__path2dev() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/disk/by-path/ | ${my_egrep} "${item_name}" | ${my_awk} -F'/' '{print $NF}' | ${my_sed} -e 's/[0-9]//g' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__dev2path
# WHY:  This subroutine locates the /dev/disk/by-path/<entry> associated with
#       a /dev/<entry>
#
f__dev2path() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/disk/by-path/ | ${my_egrep} "/${item_name}$" | ${my_awk} '{print $9}' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__dev2dev
# WHY:  This subroutine locates the /dev/<entry> device associated with <entry>
#
f__dev2dev() {
    item_name="${1}"
    item=""
    
    if [ "${item_name}" != "" ]; then
        item=`${my_ls} -altr /dev/ | ${my_egrep} "${item_name}$" | ${my_awk} '{print $NF}' | ${my_sed} -e 's/[0-9]//g' | ${my_sort} -u | ${my_tail} -1`
    fi

    echo "${item}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__guided
# WHY:  This subroutine walks the invoking user through the steps necessary
#       for creating a ZFS storage pool
#
f__guided() {
    return_code=${SUCESS}
    available_items=`f__available_disks`

    if [ "${available_items}" != "" ]; then
        echo
        echo -ne "${OFFSET}Available disks:"

        for i in ${available_items} ; do
            echo -ne " ${i}"
        done

        echo
        echo

        guided_menu=""

        # Offer choices
        while [ "${guided_menu}" = "" ]; do
            counter=0
            echo "What would you like to do?"
            echo

            while [ "${GUIDED_MENU[$counter]}" != "" ]  ; do
                echo "${OFFSET}${counter}) ${GUIDED_MENU[$counter]}"
                let counter=${counter}+1
            done

            echo 
            read -p "Choose a value: " user_input

            # Sanitize this input
            user_input=`echo "${user_input}" | ${my_sed} -e 's/[^0-9]//g'`

            if [ "${user_input}" != "" ]; then

                if [ ${user_input} -lt 0 -o ${user_input} -ge ${counter} ]; then
                    echo "Invalid selection"
                else
                    guided_menu="${user_input}"
                    let zpool_check=${user_input}

                    if [ ${zpool_check} -gt 0 ]; then
                        let zpools_exist=`${my_zpool} status 2>&1 | ${my_egrep} -c "pool:"`

                        if [ ${zpools_exist} -eq 0 ]; then
                            echo "No pools available"
                            guided_menu=""
                        fi

                    fi

                fi

            fi

        done

        # If we get here then we have something to do ...
        echo "${OFFSET}You chose option: ${guided_menu}) ${GUIDED_MENU[$guided_menu]}"
        echo

        # ... And our first zpool argument can be discerned, so ...
        guided_command="${GUIDED_COMMAND[$guided_menu]}"

        # ... we must prompt for a ZFS Pool name!
        zpool_name=""

        # guided_menu=0 => New ZFS Pool name
        # guided_menu=1 => Add to existing ZFS Pool

        case ${guided_menu} in

            0)
                while [ "${zpool_name}" = "" ]; do
                    read -p "${OFFSET}Enter a name for this new ZFS Pool: " user_input

                    # Sanitize this input
                    user_input=`echo "${user_input}" | ${my_sed} -e 's/[^a-zA-Z0-9_\-]//g'`

                    if [ "${user_input}" != "" ]; then
                        read -p "${OFFSET}${OFFSET}You have entered: \"${user_input}\", is this correct? (y/n) " confirm

                        # Sanitize this input
                        confirm=`echo "${confirm}" | ${my_tr} '[A-Z]' '[a-z]' | ${my_sed} -e 's/{^yn]//g'`

                        case ${confirm} in

                            y)
                                zpool_name="${user_input}"
                            ;;

                            *)
                                user_input=""
                            ;;

                        esac

                    fi

                done

            ;;

            1)
                existing_pools=`${my_zpool} status | ${my_egrep} -i "pool:" | ${my_awk} '{print $NF}'`
                EXISTING_POOL=(${existing_pools})
                zpool_name=""
        
                # Offer choices
                while [ "${zpool_name}" = "" ]; do
                    counter=0
                    echo "Please choose an existing ZFS Pool:"
                    echo
        
                    while [ "${EXISTING_POOL[$counter]}" != "" ]  ; do
                        echo "${OFFSET}${counter}) ${EXISTING_POOL[$counter]}"
                        let counter=${counter}+1
                    done
        
                    echo 
                    read -p "Choose a value: " user_input
        
                    # Sanitize this input
                    user_input=`echo "${user_input}" | ${my_sed} -e 's/[^0-9]//g'`
        
                    if [ "${user_input}" != "" ]; then
        
                        if [ ${user_input} -lt 0 -o ${user_input} -ge ${counter} ]; then
                            echo "Invalid selection"
                        else
                            zpool_name="${EXISTING_POOL[$user_input]}"
                        fi
        
                    fi
        
                done

            ;;

        esac

        # Now, we must prompt for a VDEV type!
        vdev_type=""

        # Offer choices
        while [ "${vdev_type}" = "" ]; do
            counter=0
            echo
            echo "${OFFSET}Select one of the following VDEV Types"

            while [ "${VDEV_TYPE[$counter]}" != "" ]  ; do
                echo "${OFFSET}${OFFSET}${counter}) ${VDEV_TYPE[$counter]}"
                let counter=${counter}+1
            done

            echo 
            read -p "${OFFSET}Choose a value: " user_input

            # Sanitize this input
            user_input=`echo "${user_input}" | ${my_sed} -e 's/[^0-9]//g'`

            if [ "${user_input}" != "" ]; then

                if [ ${user_input} -lt 0 -o ${user_input} -ge ${counter} ]; then
                    echo "Invalid selection"
                else
                    vdev_type="${VDEV_TYPE[$user_input]}"

                    if [ "${guided_command}" = "create" ]; then

                        case ${vdev_type} in

                            log|cache|spare)
                                echo "Top level VDEV cannot be cache, log, or spare"
                                vdev_type=""
                            ;;

                        esac

                    fi

                fi

            fi

        done

        # If we get here then we can select disks for the VDEV!
        echo "${OFFSET}${OFFSET}You chose option: ${user_input}) ${vdev_type}"
        counter=0

        # Create an ordered array of the available disk based on size
        AVAILABLE_DISK=(${available_items})
        vdev_elements=""

        while [ "${vdev_elements}" = "" ] ; do
            echo
            echo "${OFFSET}${OFFSET}${OFFSET}The following disks are available for use:"
            echo

            counter=0
            column_count=0

            for item in ${AVAILABLE_DISK[*]} ; do

                if [ ${column_count} -eq 0 ]; then
                    echo -ne "${OFFSET}${OFFSET}${counter}) ${item}\t"
                    let column_count=${column_count}+1
                elif [ ${column_count} -lt 2 ]; then
                    echo -ne "${counter}) ${item}\t"
                    let column_count=${column_count}+1
                else
                    echo "${counter}) ${item}"
                    column_count=0
                fi

                let counter=${counter}+1
            done

            echo
            echo
            echo "${OFFSET}${OFFSET}Please select the desired disks.  Mulitple selections can be made,"
            read -p "${OFFSET}${OFFSET}each separated by a space (Ex: 0 3 4 7): " input
            echo

            # Sanitize this input
            input=`echo "${input}" | ${my_sed} -e 's/[^0-9\ ]//g'`
            echo "${OFFSET}${OFFSET}Your input is: ${input}"

            # Check that input is valid
            let invalid_input=0

            for i in ${input} ; do

                if [ "${AVAILABLE_DISK[$i]}" = "" ]; then
                   echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                   echo "${OFFSET}${OFFSET}${OFFSET} ERROR:  Input value \"${i}\" is invalid"
                   echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                   let invalid_input=${invalid_input}+1
                fi

            done

            base_count=2
            test_array=(${input})
            let test_count=${#test_array[*]}

            # Check for minimum disk count, based on VDEV type
            case ${vdev_type} in

                log)
                    let disk_count=${base_count}
                    error_descriptor="disks"

                    # Log volumes should be mirrored
                    # Make sure ${test_count}%2=0
                    let test_modulus=${test_count}%2

                    if [ ${test_modulus} -gt 0 ]; then
                        let invalid_input=${invalid_input}+1
                    else
                        guided_command_extras="mirror"
                    fi

                ;;

                mirror)
                    let disk_count=${base_count}
                    error_descriptor="disks"

                    # Make sure ${test_count}%2=0
                    let test_modulus=${test_count}%2

                    if [ ${test_modulus} -gt 0 ]; then
                        let invalid_input=${invalid_input}+1
                    fi

                ;;

                cache)
                    let disk_count=${base_count}
                    error_descriptor="disks"
                ;;

                raidz1)
                    let disk_count=${base_count}+1 
                    error_descriptor="disks"
                ;;

                raidz2)
                    let disk_count=${base_count}+2
                    error_descriptor="disks"
                ;;

                raidz3)
                    let disk_count=${base_count}+3
                    error_descriptor="disks"
                ;;

                spare)
                    let disk_count=1
                    error_descriptor="disk"
                ;;

            esac

            if [ ${test_count} -lt ${disk_count} ]; then
                echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                echo "${OFFSET}${OFFSET}${OFFSET} ERROR: VDEV Type ${vdev_type} requires at least ${disk_count} ${error_descriptor}"
                echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                let invalid_input=${invalid_input}+1
            fi

            if [ ${invalid_input} -eq 0 ]; then
                vdev_elements="${input}"
            else
                echo
                echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                echo "${OFFSET}${OFFSET}${OFFSET} ERROR:  There were problems found with the disk selections"
                echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
            fi

        done

        # If we get here, we need to find the persistent name of the disk
        # by first looking in /dev/disk/by-id, then in /dev/disk/by-uuid, then
        # in /dev/disk/by-path.  If nothing else can be found, we use the
        # plain old /dev/<disk> name
        persistent_names=""
        item_errors=0

        for item in ${vdev_elements} ; do
            persistent_item=""
            raw_item=`echo "${AVAILABLE_DISK[$item]}" | ${my_awk} -F':' '{print $NF}' | ${my_awk} -F'/' '{print $NF}'`
            item_id=`f__dev2id "${raw_item}"`
            item_uuid=`f__dev2uuid "${raw_item}"`
            item_path=`f__dev2path "${raw_item}"`
            item_dev=`f__dev2dev "${raw_item}"`

            if [ "${item_id}" != "" ]; then
                echo "${OFFSET}${OFFSET}${OFFSET}  Using persistent name \"/dev/disk/by-id/${item_id}\" for \"${raw_item}\""
                persistent_item="/dev/disk/by-id/${item_id}"
            elif [ "${item_uuid}" != "" ]; then
                echo "${OFFSET}${OFFSET}${OFFSET}  Using persistent name \"/dev/disk/by-uuid/${item_uuid}\" for \"${raw_item}\""
                persistent_item="/dev/disk/by-uuid/${item_uuid}"
            elif [ "${item_path}" != "" ]; then
                echo "${OFFSET}${OFFSET}${OFFSET}  Using persistent name \"/dev/disk/by-path/${item_path}\" for \"${raw_item}\""
                persistent_item="/dev/disk/by-path/${item_path}"
            elif [ "${item_dev}" != "" ]; then
                echo "${OFFSET}${OFFSET}${OFFSET}  Using persistent name \"${item_dev}\" for \"${raw_item}\""
                persistent_item="/dev/${item_dev}"
            else 
                echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                echo "${OFFSET}${OFFSET}${OFFSET} ERROR:  Unable to find persistent name for \"${raw_item}\""
                echo "${OFFSET}${OFFSET}${OFFSET}+-----+"
                let item_errors=${item_errors}+1
            fi

            if [ "${persistent_item}" != "" ]; then

                if [ "${persistent_names}" = "" ]; then
                    persistent_names="${persistent_item}"
                else
                    persistent_names="${persistent_names} ${persistent_item}"
                fi

            fi

        done

        if [ ${item_errors} -eq 0 ]; then
            echo
            echo "${OFFSET}${OFFSET}Preparing ZFS pool ${zpool_name} of type ${vdev_type} with the following disks:"
            
            for item in ${persistent_names}; do
                echo "${OFFSET}${OFFSET}${OFFSET}${item}"
            done

            echo "`${my_date}`: Executing command: '${my_zpool} ${guided_command} \"${zpool_name}\" ${vdev_type} ${guided_command_extras} ${persistent_names} -f > /dev/null 2>&1'" >> "${LOG_DIR}/${LOG_FILE}"
            ${my_zpool} ${guided_command} "${zpool_name}" ${vdev_type} ${guided_command_extras} ${persistent_names} -f > /dev/null 2>&1
            echo
            echo "+------+"
            echo " STATUS:"
            echo "+------+"
           
            ${my_zpool} status ${zpool_name}
        else
            err_msg="Errors occured converting disk devices into persistent names"
            return_code=${ERROR}
        fi

    else
        err_msg="All block devices are already in use"
        return_code=${ERROR}
    fi

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__cli_args
# WHY:  This subroutine exercises the arguments provided via command line
#
f__cli_args() {
    return_code=${SUCESS}
    args="${*}"
    echo "`${my_date}`: Executing command: '${my_zpool} ${args}'" >> "${LOG_DIR}/${LOG_FILE}"
    ${my_zpool} ${args}
    return_code=${?}

    if [ ${return_code} -ne ${SUCCESS} ]; then
        err_msg="Errors were encountered running command: \"${my_zpool} ${args}\""
    fi

    return ${return_code}
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__all_disks
# WHY:  This subroutine finds all local filesystem disks/partitions
#
f__all_disks() {
    #items=`${my_parted} -l 2> /dev/null | ${my_awk} '/^Disk \/dev/ {print $2}' | ${my_sed} -e 's/://g' | ${my_sort} -u`

    case ${device_type} in 

        partitions)
            items=`${my_ls} -altr /dev/disk/by-id/ | ${my_awk} -F'/' '/sd/ {print "/dev/" $NF}' | ${my_egrep} "[1-9]$" | ${my_sort} -u`
        ;;

        *)
            items=`${my_ls} -altr /dev/disk/by-id/ | ${my_awk} -F'/' '/sd/ {print "/dev/" $NF}' | ${my_sed} -e 's/[0-9]//g' | ${my_sort} -u`
        ;;

    esac 

    echo "${items}"
}

#-------------------------------------------------------------------------------


# WHAT: Subroutine - f__available_disks
# WHY:  This subroutine finds all local filesystem disks/partitions not is use
#
f__available_disks() {
    items=""
    excluded_items=`f__excluded_disks`
    all_items=`f__all_disks`

    # Item format: <human readable size>:<raw disk device>
    for this_item in ${all_items} ; do
        match=""

        for that_item in ${excluded_items} ; do

            if [ "${this_item}" = "${that_item}" ]; then
                match="${this_item}"
            fi

        done

        if [ "${match}" = "" ]; then
            real_item=""

            case ${device_type} in 

                rawdisks)
                    this_item_size=`${my_fdisk} -l ${this_item} 2> /dev/null | ${my_egrep} "^Disk ${this_item}:" | ${my_awk} '{print $(NF-1)}'`
                    hr_size="`echo \"${this_item_size}/1024/1024/1024\" | ${my_bc} -l`"
                    hr_int_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $1}'`"

                    if [ "${hr_int_size}" = "" ]; then 
                        hr_size="`echo \"scale=6;${this_item_size}/1024/1024/1024\" | ${my_bc} -l`"
                        hr_size="0.${hr_size}"
                        hr_int_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $1}'`"
                        hr_dec_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $NF}' | ${my_cut} -c1-4`"
                    else
                        hr_dec_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $NF}' | ${my_cut} -c1-2`"
                    fi

                    size_hr="${hr_int_size}.${hr_dec_size}GB"
                    real_item="${size_hr}:${this_item}"
                ;;

                partitions)
                    part_start_line=`${my_parted} -s ${this_item} print 2> /dev/null | ${my_egrep} -nA1 "^Number" | ${my_tail} -1 | ${my_awk} -F'-' '{print $1}'`
                    part_end_line=`${my_parted} -s ${this_item} unit B print 2> /dev/null | ${my_wc} -l`

                    # parted output prints a blank line as the last line of output
                    let part_end_line=${part_end_line}-1

                    # Add one to delta computation because search pattern in inclusive
                    let part_line_delta=`echo "${part_end_line}-${part_start_line}+1" | ${my_bc}`
                    part_lines=`${my_parted} -s ${this_item} unit B print 2> /dev/null | ${my_egrep} -A${part_line_delta} "^Number" | ${my_tail} -${part_line_delta} | ${my_awk} '{print $1 ":" $4}'`

                    for part_line in ${part_lines} ; do
                        this_part_number=`echo "${part_line}" | ${my_awk} -F':' '{print $1}'`
                        this_item_size=`echo "${part_line}" | ${my_awk} -F':' '{print $NF}' | ${my_sed} -e 's/[a-zA-Z]//g'`
                        hr_size="`echo \"${this_item_size}/1024/1024/1024\" | ${my_bc} -l`"
                        hr_int_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $1}'`"

                        if [ "${hr_int_size}" = "" ]; then 
                            hr_size="`echo \"scale=6;${this_item_size}/1024/1024/1024\" | ${my_bc} -l`"
                            hr_size="0.${hr_size}"
                            hr_int_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $1}'`"
                            hr_dec_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $NF}' | ${my_cut} -c1-4`"
                        else
                            hr_dec_size="`echo \"${hr_size}\" | ${my_awk} -F'.' '{print $NF}' | ${my_cut} -c1-2`"
                        fi

                        size_hr="${hr_int_size}.${hr_dec_size}GB"

                        if [ "${real_item}" = "" ]; then
                            real_item="${size_hr}:${this_item}${this_part_number}"
                        else
                            real_item="${real_item} ${size_hr}:${this_item}${this_part_number}"
                        fi

                    done

                ;;

            esac

            if [ "${items}" = "" ]; then
                items="${real_item}"
            else
                items="${items} ${real_item}"
            fi

        fi

    done

    # Sort items by size
    items=`for i in ${items} ; do echo "${i}" ; done | ${my_sort} -n`

    echo "${items}"
}

#-------------------------------------------------------------------------------

# WHAT: Subroutine - f__excluded_disks
# WHY:  This subroutine finds all local filesystem disks/partitions to be
#       excluded from any ZFS pools
#
f__excluded_disks() {
    #fs_items=`${my_df} -h 2> /dev/null | ${my_egrep} "^/dev" | ${my_awk} '{print $1}'`
    fs_items=`${my_df} -h 2> /dev/null | ${my_egrep} -v "mapper" | ${my_awk} '/^\/dev/ {print $1}'`
    excluded_items=""

    # Add currently mounted filesystem disks to the exludes list
    for fs_item in ${fs_items} ; do

        if [ "${excluded_items}" = "" ]; then
            excluded_items="${fs_item}"
        else
            excluded_items="${excluded_items} ${fs_item}"
        fi

    done

    # Add any swap devices
    for swap in `${my_awk} '/^\/dev/ {print $1}' /proc/swaps 2> /dev/null` ; do

        if [ "${excluded_items}" = "" ]; then
            excluded_items="${swap}"
        else
            excluded_items="${excluded_items} ${swap}"
        fi

    done

    # Add any zpool devices
    for zpool in `${my_zpool} status 2> /dev/null | ${my_egrep} "pool:" 2> /dev/null | ${my_awk} '{print $NF}'` ; do
        start_line=`${my_zpool} status 2> /dev/null | ${my_egrep} -nA1 "NAME.*STATE" | ${my_tail} -1 | ${my_awk} -F'-' '{print $1}'`
        let last_line_check=`${my_zpool} status 2> /dev/null | ${my_tail} -1 | egrep -ic "^errors:"`

        if [ ${last_line_check} -eq 0 ]; then
            end_line=`${my_zpool} status 2> /dev/null | ${my_wc} -l`
        else
            end_line=`${my_zpool} status 2> /dev/null | ${my_egrep} -nB2 "^errors:" | ${my_head} -1 | ${my_awk} -F'-' '{print $1}'`
        fi

        # Add one to delta computation because search pattern is inclusive
        let delta=`echo "${end_line}-${start_line}+1" | ${my_bc}`
        zfs_items=`${my_zpool} status "${zpool}" 2> /dev/null | ${my_egrep} -nA${delta} "NAME.*STATE" | ${my_tail} -${delta} | ${my_awk} '{print $2}'`

        for zfs_item in ${zfs_items} ; do
            item_name=`echo "${zfs_item}" | ${my_awk} -F'/' '{print $NF}'`

            # Look up the device in /dev/disk/by-uuid,
            # then in /dev/disk/by-id, then in /dev/disk/by-path,
            # then lastly in /dev
            uuid_check=`f__uuid2dev "${item_name}"`
            id_check=`f__id2dev "${item_name}"`
            path_check=`f__path2dev "${item_name}"`
            dev_check=`f__dev2dev "${item_name}"`

            if [ "${uuid_check}" != "" ]; then
                this_item=`echo "${uuid_check}" | ${my_sed} -e 's/[0-9]//g'`
            elif [ "${id_check}" != "" ]; then
                this_item=`echo "${id_check}"   | ${my_sed} -e 's/[0-9]//g'`
            elif [ "${path_check}" != "" ]; then
                this_item=`echo "${path_check}" | ${my_sed} -e 's/[0-9]//g'`
            elif [ "${dev_check}" != "" ]; then
                this_item=`echo "${dev_check}"  | ${my_sed} -e 's/[0-9]//g'`
            else
                this_item=""
            fi

            if [ "${this_item}" != "" ]; then

                if [ "${excluded_items}" = "" ]; then
                    excluded_items="${this_item}"
                else
                    excluded_items="${excluded_items} /dev/${this_item}"
                fi

            fi

        done

    done

    # Expand any LVM or MDADM devices into their components
    for item in ${excluded_items} ; do

        case ${item} in

            /dev/mapper*)

                for element in `${my_pvscan} 2> /dev/null | ${my_awk} '/ PV \// {print $2}'` ; do
                    excluded_items="${excluded_items} ${element}"
                done

            ;;

            /dev/md*)

                for element in `${my_awk} -F'raid[0-9]*' '/active/ {print $NF}' /proc/mdstat` ; do 
                    element=`echo "${element}" | ${my_awk} -F'[0-9]*\\\[' '{print $1}'`
                    excluded_items="${excluded_items} /dev/${element}"
                done

            ;;

        esac

    done

    # Uniquely sort the updated exclude list
    case ${device_type} in 

        partitions)
            sorted_items=`for exclude in ${excluded_items} ; do echo -ne "${exclude}\n" ; done | ${my_sort} -u`
        ;;

        *)
            sorted_items=`for exclude in ${excluded_items} ; do echo -ne "${exclude}\n" ; done | ${my_sed} -e 's/[0-9]*$//g' | ${my_sort} -u`
        ;;

    esac 

    excluded_items=""

    for i in ${sorted_items} ; do

        if [ "${excluded_items}" = "" ]; then
            excluded_items="${i}"
        else
            excluded_items="${excluded_items} ${i}"
        fi

    done

    echo "${excluded_items}"
}

#-------------------------------------------------------------------------------

################################################################################
# MAIN
################################################################################

# WHAT: Make sure we have a some useful commands
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    for command in awk bc cut date df egrep fdisk head id ls parted pvscan sed sort tail tr zpool wc ; do
        unalias ${command} > /dev/null 2>&1
        f__check_command "${command}"

        if [ ${?} -ne ${SUCCESS} ]; then
            let exit_code=${exit_code}+1
        fi

    done

fi

# WHAT: Make sure we are root
# WHY:  Cannot proceed otherwise
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    this_uid=`${my_id} -u 2> /dev/null`

    if [ "${this_uid}" != "0" ]; then
        err_msg="You must be root to run this script"
        exit_code=${ERROR}
    fi

fi

# WHAT: Gather excludes (initializes variable ${excluded_items}
# WHY:  Needed later
#
if [ ${exit_code} -eq ${SUCCESS} ]; then
    device_type="rawdisks"

    if [ "${1}" = "partitions" ]; then
        device_type="${1}"
        shift
    fi

    excluded_disks=`f__excluded_disks`

    if [ "${excluded_disks}" = "" ]; then
        err_msg="An error occured building the block device exclude list"
        exit_code=${ERROR}
    else
        echo
        echo -ne "    Assigned disks : ${excluded_disks}"
        echo
    fi

fi

# WHAT: Process arguments
# WHY:  Determines how we behave
#
if [ ${exit_code} -eq ${SUCCESS} ]; then

    if [ "${*}" = "" ]; then
        f__guided
    else 
        f__cli_args ${*}
    fi

    exit_code=${?}
fi

# WHAT: Complain if necessary and exit
# WHY:  Success or failure, either way we are through
#
if [ ${exit_code} -ne ${SUCCESS} ]; then

    if [ "${err_msg}" != "" ]; then
        echo
        echo "    ERROR:  ${err_msg} ... processing halted"
        echo
    fi

fi

exit ${exit_code}
