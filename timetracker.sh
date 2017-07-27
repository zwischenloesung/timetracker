#!/bin/bash -e
########################################################################
#** Version: 1.0
#* This script helps recording accomplished tasks and the time used.
#
########################################################################
# author/copyright: <mic@inofix.ch>
# license: gladly sharing with the universe and any lifeform,
#          be it naturally born or constructed, alien or kin..
#          USE AT YOUR OWN RISK.
########################################################################
[ "$1" == "debug" ] && shift && set -x

## variables ##

### you may copy the following variables into this file for having your own
### local config ...
conffile=~/.tt.conf

### {{{

dryrun=1
needsroot=1

ttfile=~/.tt

xmlBodyTag="taskRecords"
xmlRecordTag="ch.inofix.portlet.timetracker.model.impl.TaskRecordImpl"

# pattern in input file where processing should end
stop_processing="^####"

date_format="+%Y-%m-%d %H:%M:00.0 UTC"

### }}}

# Unsetting this helper variable
_pre=""

actionmode="edit"

declare -A taskRecords
taskRecords=()

# The system tools we gladly use. Thank you!
declare -A sys_tools
sys_tools=( ["_2xml"]="/usr/bin/2xml"
            ["_awk"]="/usr/bin/awk"
            ["_cat"]="/bin/cat"
            ["_cp"]="/bin/cp"
            ["_date"]="/bin/date"
            ["_diff"]="/usr/bin/diff"
            ["_grep"]="/bin/grep"
            ["_id"]="/usr/bin/id"
            ["_mkdir"]="/bin/mkdir"
            ["_mktemp"]="/bin/mktemp"
            ["_pwd"]="/bin/pwd"
            ["_rm"]="/bin/rm"
            ["_rmdir"]="/bin/rmdir"
            ["_sed"]="/bin/sed"
            ["_sed_forced"]="/bin/sed"
            ["_tr"]="/usr/bin/tr"
            ["_vim"]="/usr/bin/vim"
            ["_xml2"]="/usr/bin/xml2" )
# this tools get disabled in dry-run and sudo-ed for needsroot
danger_tools=( "_cp" "_mkdir" "_mktemp" "_sed" "_rm" "_rmdir" "_vim" )
# special case sudo (not mandatory)
_sudo="/usr/bin/sudo"

## functions ##

print_usage()
{
    echo "usage: $0"
}

print_help()
{
    print_usage
    $_grep "^#\* " $0 | $_sed_forced 's;^#\*;;'
}

print_version()
{
    $_grep "^#\*\* " $0 | $_sed 's;^#\*\*;;'
}

die()
{
    printf "\e[1;31m$@\n"
    exit 1
}

error()
{
    print_usage
    echo ""
    die "Error: $@"
}

do_or_skip()
{
    echo "$1 [y/N]"
    read y
    if [ "$y" != "y" ] ; then
        return 1
    fi
}

parse_file()
{
    if [ -f "$1" ] ; then
        $_awk \
            'BEGIN {
                workpackage=""
                status=0
                currentday=""
                mode="none"
            }
            #sanitize input a little
            /\$|\||`/ {
                print "found suspicious characters on input: $ | `"
                exit 1
            }
            /^'$stop_processing'/ {
                # EOF for our concern..
                exit
            }
            /^$/ || /^#/ {
                next
            }
            /^=.*=$/ {
                mode="date"
                gsub("=", "")
                currentday=$1
                next
            }
            !/\s/ {
                if (mode != "none") {
                    mode="workpackage"
                    if (index($1, "~") == 1) {
                        status=1
                        workpackage=substr($1, 2)
                    } else {
                        status=0
                        workpackage=$1
                    }
                } else {
                    print "failed to parse: workpackage outside date"
                    exit 1
                }
                next
            }
            /^    [0-9]/ {
                if (mode == "workpackage") {
                    startdigits=match($1, "^[0-9]*$")
                    if (startdigits == 0) {
                        print "failed to parse: task must start with time first"
                        exit 1
                    }
                    startvalue=$1

                    enddigits=match($2, "^[0-9]*$")
                    if (enddigits > 0) {
                        startvalue=currentday" "startvalue
                        endvalue=currentday" "$2
                    } else {
                        startvalue=currentday" 0000"
                        endvalue=currentday" "$1" minutes"
                    }
                    patsplit($0, descr, "\".*\"")
                    gsub("\"", "", descr[1])
                    description=descr[1]
                    patsplit($0, tkt, "\\[.*\\]")
                    gsub("\\[", "", tkt[1])
                    gsub("\\]", "", tkt[1])
                    ticketURL=tkt[1]
                } else {
                    print "failed to parse: task outside workpackage"
                    exit 1
                }
            }
            {
                print "workpackage=\""workpackage"\""
                print "description=\""description"\""
                print "ticketURL=\""ticketURL"\""
                print "startDate=\""startvalue"\""
                print "endDate=\""endvalue"\""
                print "status=\""status"\""
                print "--next--"
                next
            }
            {
                echo "failed to parse: parser should never get down here.."
                exit 1
            }' "$1"
    fi
}

parse_date()
{
    echo $($_date -d "$1" +%s)
}

format_date()
{
    echo $($_date -d "@$1" $date_format)
}

test_date()
{
    [ $1 -lt $2 ] || error "start date was greater than end date"
    for d in $1 $2 ; do
        m=$($_date -d "@$d" +%M)
        case $m in
            00|15|30|45)
            ;;
            *)
                error "date was not one of '00|15|30|45'"
            ;;
        esac
    done
}

parse_current_record()
{
    for e in ${currentRecord[@]} ; do
#echo "-- $e --"
        eval "$e"
    done
}

parse_records()
{
    i=0
    IFS="
"
    for l in $(parse_file $ttfile) ; do
        if [ "${l}" == "--next--" ] ; then
            let ++i
        else
            taskRecords[$i]="${taskRecords[$i]} \n $l"
        fi
    done
    unset IFS
}

export_xml()
{
    tagBase="/$xmlBodyTag/$xmlRecordTag"
    toxml="$tagBase
$tagBase/__workPackage=$workpackage
$tagBase/__description=$description
$tagBase/__ticketURL=$ticketURL
$tagBase/__startDate=$startDate
$tagBase/__endDate=$endDate
$tagBase/__status=$status"
    if [ $dryrun -eq 0 ] ; then
        printf "\e[1;39mThis is what we would feed 2xml:\e[0;39m\n"
        echo "$toxml"
        printf "\e[1;39mThis is what 2xml makes out of it:\e[0;39m\n"
        echo "$toxml" | $_2xml
    else
        printf "\e[1;39mWriting to ${tempfile}\e[0;39m\n"
        echo "$toxml" >> ${tempfile}
    fi
}

process_records()
{
    parse_records

    IFS="
"
    for (( i=0 ; i < ${#taskRecords[@]} ; i++ )) ; do

        printf "\e[1;32mProcessing Entry #\e[1;33m$i \e[0;39m\n"
#echo "${taskRecords[$i]//\\n}"
        currentRecord=( $( /bin/echo -e ${taskRecords[$i]} ) )
        printf " ${currentRecord[1]}\n"
        printf " ${currentRecord[2]}\n"
        printf " ${currentRecord[4]}\n"
        printf " ${currentRecord[5]}\n"
        parse_current_record

        startSince=$( parse_date $startDate )
        endSince=$( parse_date $endDate )
        test_date $startSince $endSince
        startDate=$( format_date $startSince )
        endDate=$( format_date $endSince )

        $1
    done
    unset IFS
}

## control logic ##

## first set the system tools
for t in ${!sys_tools[@]} ; do
    if [ -x "${sys_tools[$t]##* }" ] ; then
        export ${t}="${sys_tools[$t]}"
    else
        error "Missing system tool: ${sys_tools[$t]##* } must be installed."
    fi
done

[ -r "$conffile" ] && . $conffile

#*  options:
while true ; do
    case "$1" in
#*      -c |--config conffile               alternative config file
        -c|--config)
            shift
            if [ -r "$1" ] ; then
                . $1
            else
                die " config file $1 does not exist."
            fi
        ;;
#*      -h |--help                          print this help
        -h|--help)
            print_help
            exit 0
        ;;
#*      -n |--dry-run                       do not change anything
        -n|--dry-run)
            dryrun=0
        ;;
#*      -v |--version
        -v|--version)
            print_version
            exit
        ;;
#*      -x |--export                        export to XML
        -x|--export)
            actionmode="export2xml"
        ;;
        -*|--*)
            error "option $1 not supported"
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ $dryrun -eq 0 ] ; then
    _pre="echo "
fi

if [ $needsroot -eq 0 ] ; then

    iam=$($_id -u)
    if [ $iam -ne 0 ] ; then
        if [ -x "$_sudo" ] ; then

            _pre="$_pre $_sudo"
        else
            error "Missing system tool: $_sudo must be installed."
        fi
    fi
fi

for t in ${danger_tools[@]} ; do
    export ${t}="$_pre ${sys_tools[$t]}"
done

case $actionmode in
    edit)
        $_vim -c "set backup" -c "set writebackup" $ttfile
    ;;&
    export2xml)
        [ ! -s "${ttfile}.xml" ] || error "file ${ttfile}.xml was not empty"
        tempfile=$( $_mktemp )
        process_records export_xml
        if [ "${_pre:0:4}" != "echo" ] ; then
            printf "\e[1;32mLooks good, now writing ${ttfile}.xml\e[0;39m\n"
            $_2xml > "${ttfile}.xml" < "$tempfile"
            $_rm "$tempfile"
        fi
    ;;
    *)
    echo "removing trailing white space, just in case"
    $_sed --follow-symlinks -i 's#[ \t]*$##' $ttfile
    if ! $_diff -q $ttfile $ttfile+ ; then
        if do_or_skip "Skip backup?" ; then
            printf "\e[1;32mNo backup was created..\e[0;39m\n"
        else
            printf "\e[1;32mWriting backup..\e[0;39m\n"
            $_cp $ttfile $ttfile+
        fi
    fi
    ;;
esac

printf "\e[1;32mDONE.\e[0;39m\n"
