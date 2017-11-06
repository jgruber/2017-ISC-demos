#!/bin/bash


function validate_undercloud() {
    if [[ -z ${DIRECTOR_NODE} ]]
    then
        echo -n "Undercloud Director Node IP: "
        read DIRECTOR_NODE;
        export DIRECTOR_NODE="${DIRECTOR_NODE}"
    fi
    if [[ -z ${UNDERCLOUD_INVENTORY} ]]
    then
        get_undercloud_inventory
    fi
}

function get_undercloud_inventory() {
    ssh root@$DIRECTOR_NODE "runuser -l stack -c \". /home/stack/stackrc; nova list 2>/dev/null | tail -n +4 | head -n -1\"" > /tmp/undercloud_nodes_full.txt
    cat /tmp/undercloud_nodes_full.txt|awk '{print $4 $12}'|sed s/ctlplane=/=/g > /tmp/undercloud_nodes.txt
    unset UNDERCLOUD_INVENTORY
    while read node
    do
        export UNDERCLOUD_INVENTORY="${UNDERCLOUD_INVENTORY} ${node} "
    done < /tmp/undercloud_nodes.txt
    rm -rf /tmp/undercloud_nodes.txt /tmp/undercloud_nodes_full.txt
}

function get_undercloud_nodes() {
    validate_undercloud
    for node in $UNDERCLOUD_INVENTORY; do echo -n "${node} "| cut -d "=" -f1; done
}

function get_undercloud_node_ip() {
    validate_undercloud
    node=$1
    for node in $UNDERCLOUD_INVENTORY
    do
        if [[ $node == ${1}* ]]
        then
            echo -n "${node} "| cut -d "=" -f2;
        fi
    done
}

function clear_undercloud_inventory() {
    unset UNDERCLOUD_INVENTORY
    unset DIRECTOR_NODE
}

function quote() { printf %q "${1}"; }

function runcmd_on_undercloud_node(){
    validate_undercloud
    nodeip=$(quote $(get_undercloud_node_ip $1))
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} "${@:2}"
}

function cp_to_undercloud_node() {
    validate_undercloud
    nodeip=$(quote $(get_undercloud_node_ip $1))
    src_file=$2
    src_file_only=$(basename $2)
    dst_file=$3
    owner=root
    group=root
    mode="0644"
    if [[ -z "$4" ]]; then owner=$4; fi
    if [[ -z "$5" ]]; then group=$5; fi
    if [[ -z "$6" ]]; then mode=$6; fi
    scp $2 root@$DIRECTOR_NODE:/tmp/$src_file_only
    ssh root@$DIRECTOR_NODE sudo -u stack scp /tmp/$src_file_only heat-admin@${nodeip}:/tmp/$src_file_only
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} sudo -i mv -f /tmp/$src_file_only $dst_file
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} sudo -i chown $owner:$group $dst_file
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} sudo -i chmod $mode $dst_file
    ssh root@$DIRECTOR_NODE rm /tmp/$src_file_only
}

function cp_from_undercloud_node() {
    validate_undercloud
    nodeip=$(quote $(get_undercloud_node_ip $1))
    src_file=$2
    src_file_only=$(basename $2)
    dst_file=$3
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} sudo -i cp $src_file /tmp/${src_file_only}
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} sudo -i chown heat-admin /tmp/${src_file_only}
    ssh root@$DIRECTOR_NODE sudo -u stack scp heat-admin@${nodeip}:/tmp/${src_file_only} /tmp/${src_file_only}
    ssh root@$DIRECTOR_NODE sudo -u stack ssh heat-admin@${nodeip} sudo -i rm /tmp/${src_file_only}
    scp root@$DIRECTOR_NODE:/tmp/$src_file_only ${dst_file}
    ssh root@$DIRECTOR_NODE rm /tmp/$src_file_only
}

function get_esds_on_hosts() {
    validate_undercloud
    esd_dir="/etc/neutron/services/f5/esd/"
    for node in $(get_undercloud_nodes)
    do
        runcmd_on_undercloud_node $node sudo -i ls $esd_dir 2>/dev/null > /tmp/esd_ls.txt
        if [[ $? < 1 ]]
        then
            echo "--------------------"
            echo " ${node}"
            echo "--------------------"
            while read esd_file
            do
                 echo ""
                 echo $esd_file
                 echo ""

                 runcmd_on_undercloud_node $node sudo -i cat ${esd_dir}${esd_file} < /dev/null

            done < /tmp/esd_ls.txt
        fi
        rm -rf /tmp/esd_ls.txt 2>/dev/null
    done
}

function cp_esd_file_to_hosts() {
   validate_undercloud
   src_file=$1
   src_file_only=$(basename $1)
   for node in $(get_undercloud_nodes)
   do
        runcmd_on_undercloud_node ${node} sudo -i ls /etc/neutron/services/f5/esd 2>/dev/null > /tmp/esd_ls.txt
        if [[ $? < 1 ]]
        then
            echo "copying ${src_file} to ${node}"
            cp_to_undercloud_node $node $src_file /etc/neutron/services/f5/esd/$src_file_only neutron root 0644
        fi
        rm -rf /tmp/esd_ls.txt 2>/dev/null
   done
}

function restart_f5_openstack_agents() {
   validate_undercloud
   for node in $(get_undercloud_nodes)
   do
     pslines=$(runcmd_on_undercloud_node ${node} sudo -i ps -ef|grep f5-openstack-agent|wc -l)
     if [[ $pslines == 1 ]]
     then
         echo "restarting f5-openstack-agent service on ${node}"
         runcmd_on_undercloud_node ${node} sudo -i systemctl restart f5-openstack-agent
         echo ""
     fi
   done
}
