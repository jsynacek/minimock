#!/bin/bash

# Copyright (C) 2015 Jan Synáček
#
# Author: Jan Synáček <jan.synacek@gmail.com>
# URL: https://github.com/jsynacek/minimock
# Created: Jun 2015
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING.  If not, write to
# the Free Software Foundation, Inc., 51 Franklin Street, Fifth
# Floor, Boston, MA 02110-1301, USA.

arg_logfile=
arg_machine=
arg_machinedir=
arg_yes=
srpm=

nspawn_cmd="sudo systemd-nspawn --quiet"
install_cmd="yum install -y"
arch="$(rpm --eval "%_arch")"
topdir=/tmp/minimock
srcrpmdir=$topdir/SRPMS


function usage {
    {
    echo "usage: $0 -M MACHINE    [ OPTIONS ] SRPM"
    echo "       $0 -D MACHINEDIR [ OPTIONS ] SRPM"
    echo ""
    echo "OPTIONS"
    echo "    -h            Show this help."
    echo "    -L LOGFILE    Path to a file that will be used for logging."
    echo "    -M MACHINE    Machine that should be used to do the building. See systemd-nspawn(1)."
    echo "    -D MACHINEDIR Directory where rootfs of a machine is located. See systemd-nspawn(1)."
    echo "    -y            Answer every question with 'yes'."
    } >&2
}

function setup_logging {
    if [[ -n "$arg_logfile"  ]]; then
	exec 10>&1
       	exec 1>$arg_logfile
    fi
}

function restore_stdout {
    if [[ -n "$arg_logfile" ]]; then
	exec 1>&10 10>&-
    fi
}

function ask_yes_no {
    local question="$1"

    echo -n "$question (Y/n) "
    if [[ -n "$arg_yes" ]]; then
	echo "y"
	return 0
    fi

    read answer
    if [[ -z "$answer" || "$answer" == "y" || "$answer" == "Y" ]]; then
	return 0
    fi
    return 1
}

function cleanup {
    sudo rm -rf $topdir/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} /tmp/deps
}

# Process program options.
if [[ $# < 1 ]]; then
    usage && exit 1
fi

while getopts "hL:M:D:y" opt; do
    case "$opt" in
	h)
	    usage && exit 0
	    ;;
	L)
	    arg_logfile="$OPTARG"
	    ;;
	M)
	    arg_machine="$OPTARG"
	    ;;
	D)
	    arg_machinedir="$OPTARG"
	    ;;
	y)
	    arg_yes="-y"
	    ;;
	?)
	    usage && exit 1
	    ;;
    esac    
done
shift $((OPTIND - 1))
srpm=$1

# Check for vital binaries on the host.
for bin in rpm systemd-nspawn; do
    $bin --version &>/dev/null
    if [[ $? != 0 ]]; then
        echo "$bin is not installed, exiting"
        exit 1
    fi
done

# Check main argument sanity.
[[ -z "$srpm" ]] && echo "no srpm specified" && exit 1
[[ ! -f "$srpm" ]] && echo "$srpm cannot be used" && exit 1
if [[ -z "$arg_machine" && -z "$arg_machinedir" ]]; then
    echo "one of -D or -M must be specified" >&2
    usage && exit 1
fi

[[ -n "$arg_machine" ]] && nspawn_cmd="$nspawn_cmd -M $arg_machine"
[[ -n "$arg_machinedir" ]] && nspawn_cmd="$nspawn_cmd -D $arg_machinedir"

# the last 3 components from the src rpm (.<os>.src.rpm) are removed
_t=${srpm%.*}
_t=${_t%.*}
resultdir=${_t%.*}

# Set up logging.
setup_logging

mkdir -p $topdir/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp $srpm $srcrpmdir/
[[ $? == 0 ]] || ( cleanup && exit 1 )
mkdir $resultdir &>/dev/null

# Probe for rpmbuild on the machine, install it in case it's not there and the user wishes so.
$nspawn_cmd rpmbuild --version &>/dev/null
if [[ $? != 0 ]]; then
    if ask_yes_no "rpmbuild not installed on the machine, do you want to install it now?"; then
	$nspawn_cmd $install_cmd /usr/bin/rpmbuild
	rc=$?
	[[ $rc == 0 ]] || ( cleanup && exit $rc )
    else
	cleanup && exit 1
    fi
fi

# Extract the source RPM to the correct places.
$nspawn_cmd --bind=$topdir \
     /bin/bash -c "cd $topdir/SOURCES && rpm2cpio $srcrpmdir/$1 | cpio --quiet -i && mv *.spec $topdir/SPECS"

# Test for any missing dependencies. If there are any, try to grep them out of the rpmbuild output and install them if the user wishes so.
$nspawn_cmd --bind=$topdir \
     /bin/bash -c "rpmbuild --define '%_topdir $topdir' --nobuild $topdir/SPECS/*.spec" 2>&1 | tee /tmp/deps

deps=$(grep "is needed by" /tmp/deps | sed -e 's/^[[:space:]]\([a-zA-Z():-]*\)\(.*\)\? is needed by .*$/\1/' | tr "\n" " ")
if [[ ! -z "$deps" ]]; then
    if ask_yes_no "Build dependencies '$deps' are not installed, do you want to install them?"; then
	$nspawn_cmd $install_cmd $deps 
	rc=$?
	[[ $rc == 0 ]] || ( cleanup && exit $rc )
    else
	cleanup && exit 1
    fi
fi

# Build.
$nspawn_cmd --bind=$topdir \
     rpmbuild --define "_topdir $topdir" -bb $topdir/SPECS/*.spec 2>&1

# Fetch the result packages.
if [[ $? == 0 ]]; then
     cp $topdir/RPMS/$arch/*.rpm $resultdir/
     [[ -d $topdir/RPMS/noarch/ ]] && cp $topdir/RPMS/noarch/*.rpm $resultdir/

     restore_stdout
     echo "Results have been written to '$resultdir'."
fi

# Clean up.
cleanup

