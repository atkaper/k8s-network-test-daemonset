#!/bin/bash

# The name of our daemonset (used to ask k8s api for al instances)
SETNAME=k8s-network-test-daemonset

if [ "$NODENAME" == "" ]
then
   # This one will be passed in from the daemonset deployment yml, this fallback for running outside k8s container (for debug/test).
   NODENAME=$HOSTNAME
fi

echo "`date` Tests running on node: $NODENAME, host: $HOSTNAME"

>/tmp/testnodes.log

# clear prometheus report (the "new" file, will be renamed to ".report" at end to prevent http server from serving half a file)
>/tmp/prometheus.report.new

function prometheus {
   # add entry to prometheus report file
   if [ "$4" != "" ]
   then
      if [ "$6" != "" ]
      then
         echo "networktest_${1}{src_node=\"${NODENAME}\",$3=\"$4\",$5=\"$6\"} $2" >>/tmp/prometheus.report.new
      else
         echo "networktest_${1}{src_node=\"${NODENAME}\",$3=\"$4\"} $2" >>/tmp/prometheus.report.new
      fi
   else
      echo "networktest_${1}{src_node=\"${NODENAME}\"} $2" >>/tmp/prometheus.report.new
   fi
}

function prometheus_end {
   # activate new prometheus report
   mv /tmp/prometheus.report.new /tmp/prometheus.report
}

function error {
   # Write to report file. Will be compared with previous report.
   echo "Error from: $NODENAME $HOSTNAME; $*" >>/tmp/testnodes.log
}

function exit_on_error {
   if [ "$?" != "0" ]
   then
      error "$* -- exit"
      echo "Error from: $NODENAME $HOSTNAME; $*"
      prometheus fatal_error 1
      prometheus_end
      exit 1
   fi
}

# disable proxy server, in case one was enabled somewhere
http_proxy=
https_proxy=

# Find all pods for our daemonset
if [ "$KUBERNETES_SERVICE_HOST" == "" ]
then
   # This one is used when running OUTside of a container (works only on master, for test/debug of script)
   curl -sSk "http://localhost:8080/api/v1/pods?labelSelector=daemonset%3D$SETNAME" > /tmp/nodeset.json.raw
   exit_on_error "reading api data pods"

   # get DNS endpoints
   curl -sS "http://localhost:8080/api/v1/namespaces/kube-system/endpoints/kube-dns" >/tmp/dns.json
   exit_on_error "reading api data dns"

   # get DNS service
   curl -sS "http://localhost:8080/api/v1/namespaces/kube-system/services/kube-dns" >/tmp/dns-service.json
   exit_on_error "reading api data dns-service"
else
   # This one is used when running INside of a container (for normal use)
   KUBE_TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
   curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
      "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/pods?labelSelector=daemonset%3D$SETNAME" > /tmp/nodeset.json.raw
   exit_on_error "reading api data pods"

   # get DNS endpoints
   curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
      "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/kube-system/endpoints/kube-dns" >/tmp/dns.json
   exit_on_error "reading api data dns"

   # get DNS service
   curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" \
      "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/kube-system/services/kube-dns" >/tmp/dns-service.json
   exit_on_error "reading api data dns-service"
fi

# Find DNS Service IP
DNS_SERVICE_IP="`cat /tmp/dns-service.json | jq -r '.spec.clusterIP'`"
if [ "$DNS_SERVICE_IP" == "" ]
then
   echo "ERROR: no dns service-ip found in k8s api?"
   prometheus dns_no_service 1
   prometheus dns_error 1 
fi

# Find DNS instance IP's
DNS_IPS="`cat /tmp/dns.json | jq -r '.subsets[].addresses[].ip'`"
if [ "$DNS_IPS" == "" ]
then
   echo "ERROR: no dns servers found in k8s api?"
   prometheus dns_no_servers 1
   prometheus dns_error 1 
fi

# Test DNS
dnsokcount=0
dnserrorcount=0
for i in $DNS_SERVICE_IP $DNS_IPS
do
   DNS_HOST="`dig -x $i @$i +short | grep kube-dns`"
   if [ "$DNS_HOST" != "" ]
   then
      echo DNS: $i $DNS_HOST
      prometheus dns_lookup 1 dest $i
      prometheus dns_error 0 dest $i
      dnsokcount=$((dnsokcount+1))
   else
      echo DNS: $i "*ERROR*"
      prometheus dns_lookup 0 dest $i
      prometheus dns_error 1 dest $i
      dnserrorcount=$((dnserrorcount+1))
   fi
done
prometheus dns_ok_count $dnsokcount
prometheus dns_error_count $dnserrorcount

# Parse/filter data
cat /tmp/nodeset.json.raw | jq  "[ .items[] | { hostIP: .status.hostIP, podIP: .status.podIP, name: .metadata.name, nodeName: .spec.nodeName, phase: .status.phase } ]" > /tmp/nodeset.json

NODECOUNT=`grep hostIP /tmp/nodeset.json  | wc -l`
echo "Testing $NODECOUNT nodes"

prometheus node_count $NODECOUNT

NODEOKLIST=
NODEERRORLIST=

# Go through nodes one-by-one
for ((i=0;i<$NODECOUNT;i++)); 
do
   NODEOK=1

   # Parse the info fields for the given node
   cat /tmp/nodeset.json | jq ".[$i]" > /tmp/node$i.json
   NODE=`cat /tmp/node$i.json  | jq ".nodeName" -r`
   HOSTIP=`cat /tmp/node$i.json  | jq ".hostIP" -r`
   STATUS=`cat /tmp/node$i.json  | jq ".phase" -r`
   PODNAME=`cat /tmp/node$i.json  | jq ".name" -r`
   PODIP=`cat /tmp/node$i.json  | jq ".podIP" -r`

   echo -n "Checking: $NODE $HOSTIP $STATUS - $PODNAME $PODIP;  "

   if [ "$STATUS" == "Running" ]
   then
      # Ping the HOST machine
      /usr/bin/time -f "%e" -o /tmp/time$i.host.log ping -q -c1 -W4 $HOSTIP >/tmp/test$i.host.ping 2>&1
      if [ "$?" != "0" ]
      then
         error "host-ping-failed $NODE $HOSTIP"
         NODEOK=0
         echo -n "host-ping: FAIL "
         prometheus host_ping 1000 dest_ip $HOSTIP dest_node $NODE
         prometheus host_ping_fail 1 dest_ip $HOSTIP dest_node $NODE
      else
         echo -n "host-ping: `cat /tmp/time$i.host.log` "
         prometheus host_ping `cat /tmp/time$i.host.log` dest_ip $HOSTIP dest_node $NODE
         prometheus host_ping_fail 0 dest_ip $HOSTIP dest_node $NODE
      fi

      # Ping the pod in the virtual network
      /usr/bin/time -f "%e" -o /tmp/time$i.pod.log ping -q -c1 -W4 $PODIP >/tmp/test$i.pod.ping 2>&1
      if [ "$?" != "0" ]
      then
         error "pod-ping-failed $NODE $PODIP"
         NODEOK=0
         echo -n "pod-ping: FAIL "
         prometheus pod_ping 1000 dest_ip $PODIP dest_node $NODE
         prometheus pod_ping_fail 1 dest_ip $PODIP dest_node $NODE
      else
         echo -n "pod-ping: `cat /tmp/time$i.pod.log` "
         prometheus pod_ping `cat /tmp/time$i.pod.log` dest_ip $PODIP dest_node $NODE
         prometheus pod_ping_fail 0 dest_ip $PODIP dest_node $NODE
      fi

   else
      error "Status not Running: $STATUS"
      NODEOK=0
      echo -n "node-status-error "
   fi


   if [ "$NODEOK" == "1" ]
   then
      echo "- OK"
      NODEOKLIST="$NODEOKLIST $NODE"
      prometheus node_ok 1 dest_node $NODE
      prometheus node_error 0 dest_node $NODE
   else
      echo "- ** ERROR **"
      NODEERRORLIST="$NODEERRORLIST $NODE"
      prometheus node_ok 0 dest_node $NODE
      prometheus node_error 1 dest_node $NODE
   fi

done

echo "Nodes OK: $NODEOKLIST" >>/tmp/testnodes.log
echo "Nodes connect-error (from: $NODENAME $HOSTNAME): $NODEERRORLIST" >>/tmp/testnodes.log

prometheus node_ok_count `echo $NODEOKLIST | wc -w`
prometheus node_error_count `echo $NODEERRORLIST | wc -w`

prometheus total_ok_count $((dnsokcount+`echo $NODEOKLIST | wc -w`))
prometheus total_error_count $((dnserrorcount+`echo $NODEERRORLIST | wc -w`))

touch /tmp/testnodes.log.previous
diff /tmp/testnodes.log.previous /tmp/testnodes.log >/dev/null

# This diff was meant to be used to send a message to hipchat or slack, but... there's an issue with sorting the node-names,
# so this diff triggers quite often, even if there's no relevant change ;-) TODO; sort node names... (low prio, better use prometheus data).
if [ "$?" != "0" ]
then
   echo "Status Changes."
   diff /tmp/testnodes.log.previous /tmp/testnodes.log | sed 's/</OLD: /g;s/>/NEW: /g' | grep -e OLD -e NEW
else
   if [ "$NODEERRORLIST" != "" ]
   then
      echo "Nodes connect-error: $NODEERRORLIST"
   fi
   echo "No status changes since previous test run."
fi

mv /tmp/testnodes.log /tmp/testnodes.log.previous

# enable result to prometeus (will be served by internal http server in this pod)
prometheus_end

