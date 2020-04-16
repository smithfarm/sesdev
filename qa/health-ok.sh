#!/bin/bash
#
# integration test automation script "health-ok.sh"
#

set -e
trap 'catch $?' EXIT

SCRIPTNAME="$(basename "${0}")"
BASEDIR="$(readlink -f "$(dirname "${0}")")"
test -d "$BASEDIR"
# [[ $BASEDIR =~ \/sesdev-qa$ ]]

# shellcheck disable=SC1091
source /etc/os-release
# shellcheck source=common/common.sh
source "$BASEDIR/common/common.sh"

function catch {
    echo
    echo -n "Overall result: "
    if [ "$1" = "0" ] ; then
        echo "OK"
    else
        echo "NOT_OK (error $2)"
    fi
}

function usage {
    echo "$SCRIPTNAME - script for testing HEALTH_OK deployment"
    echo "for use in SUSE Enterprise Storage testing"
    echo
    echo "Usage:"
    echo "  $SCRIPTNAME [-h,--help] [--igw=X] [--mds=X] [--mgr=X]"
    echo "  [--mon=X] [--nfs=X] [--strict-versions] [--rgw=X]"
    echo "  [--total-nodes=X]"
    echo
    echo "Options:"
    echo "    --help               Display this usage message"
    echo "    --igw-nodes          expected number of nodes with iSCSI Gateway"
    echo "    --mds-nodes          expected number of nodes with MDS"
    echo "    --mgr-nodes          expected number of nodes with MGR"
    echo "    --mon-nodes          expected number of nodes with MON"
    echo "    --nfs-nodes          expected number of nodes with NFS"
    echo "    --osd-nodes          expected number of nodes with OSD"
    echo "    --osds               expected total number of OSDs in cluster"
    echo "    --strict-versions    Insist that daemon versions match \"ceph --version\""
    echo "    --rgw-nodes          expected number of nodes with RGW"
    echo "    --total-nodes        expected total number of nodes in cluster"
    exit 1
}

assert_enhanced_getopt

TEMP=$(getopt -o h \
--long "help,igw-nodes:,mds-nodes:,mgr-nodes:,mon-nodes:,nfs-nodes:,osd-nodes:,osds:,strict-versions,rgw-nodes:,total-nodes:" \
-n 'health-ok.sh' -- "$@") || ( echo "Terminating..." >&2 ; exit 1 )
eval set -- "$TEMP"

# process command-line options
IGW_NODES=""
MDS_NODES=""
MGR_NODES=""
MON_NODES=""
NFS_NODES=""
OSD_NODES=""
OSDS=""
STRICT_VERSIONS=""
RGW_NODES=""
TOTAL_NODES=""
while true ; do
    case "$1" in
        --igw-nodes) shift ; IGW_NODES="$1" ; shift ;;
        --mds-nodes) shift ; MDS_NODES="$1" ; shift ;;
        --mgr-nodes) shift ; MGR_NODES="$1" ; shift ;;
        --mon-nodes) shift ; MON_NODES="$1" ; shift ;;
        --nfs-nodes) shift ; NFS_NODES="$1" ; shift ;;
        --osd-nodes) shift ; OSD_NODES="$1" ; shift ;;
        --osds) shift ; OSDS="$1" ; shift ;;
        --strict-versions) STRICT_VERSIONS="$1"; shift ;;
        --rgw-nodes) shift ; RGW_NODES="$1" ; shift ;;
        --total-nodes) shift ; TOTAL_NODES="$1" ; shift ;;
        -h|--help) usage ;;    # does not return
        --) shift ; break ;;
        *) echo "Internal error" ; exit 1 ;;
    esac
done

# make Salt Master be an "admin node"
_zypper_install_on_master ceph-common
ADMIN_KEYRING="/etc/ceph/ceph.client.admin.keyring"
CEPH_CONF="/etc/ceph/ceph.conf"
mkdir -p /etc/ceph
if [ -f "$ADMIN_KEYRING" -a -f "$CEPH_CONF" ] ; then
    true
else
    set -x
    ARBITRARY_MON_NODE="$(_first_x_node mon)"
    if [ ! -f "$ADMIN_KEYRING" ] ; then
        _copy_file_from_minion_to_master "$ARBITRARY_MON_NODE" "$ADMIN_KEYRING"
        chmod 0600 "$ADMIN_KEYRING"
    fi
    if [ ! -f "$CEPH_CONF" ] ; then
        _copy_file_from_minion_to_master "$ARBITRARY_MON_NODE" "$CEPH_CONF"
    fi
    set +x
fi
set -x
test -f "$ADMIN_KEYRING"
test -f "$CEPH_CONF"
set +x

# run tests
support_cop_out_test
ceph_rpm_version_test
ceph_cluster_running_test
ceph_daemon_versions_test "$STRICT_VERSIONS"
ceph_health_test
mgr_is_available_test
maybe_wait_for_osd_nodes_test "$OSD_NODES"  # it might take a long time for OSD nodes to show up
maybe_wait_for_mdss_test "$MDS_NODES"  # it might take a long time for MDSs to be ready
number_of_daemons_expected_vs_metadata_test
number_of_nodes_actual_vs_expected_test
