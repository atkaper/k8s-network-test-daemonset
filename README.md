# K8S Network Test Daemonset

## Description

An on-premise K8S (kubernetes) cluster needs a proper working virtual network to connect all masters and nodes to each other.
In our situation, the host machines (vmware redhat), are not all 100% the same, and can not easily be wiped clean on new K8S
and OS upgrades. Therefor we sometimes experienced issues in which the nodes or masters could not always reach each other.
We did use the flannel network, which often caused weird issues. We recently switched to using calico, which seems much more stable.

To detect if the network is functioning correct, we have created a piece of test software. Nothing fancy, just a simple
shell script. This script runs as a daemonset in the cluster, on both masters and nodes. It tries to ping all members of the
daemonset, and ping the host machines, and tests if the k8s nameservers are reachable. If all this works, it is a nice indication
of the health of the cluster's network.

You can look at the test results by looking at the log's of each pod. The test runs every minute.

Another way to look at it, is by enabling prometheus to poll the data. The data is available in prometheus format on url
/prometheus.report (port 8123). We have added prometheus.io annotations in the k8s.yml file, which trigger prometheus to
poll all daemonset pods for this data. This way you can create a graph or counter on your dashboard with the network health.
Note: this graph/counter is on our TODO list, so there's no example here. You should probably create an expression to
calculate the number of kube-dns instances + 1, and the number of nodes and masters (compute to power of 2), and subtract
the dns/node-OK counters from that to get to zero errors on your dashboard. For now we use a query which adds all error counts: 
"sum(networktest_total_error_count)". Disadvantage of this; if a test pod is down, it does not report error's itself. Of course all
other test pods will mark it as error, so it shows up anyway as non-zero errors ;-)

## Build using:

```
docker build -t repository-url/k8s-network-test-daemonset:0.1 .
docker push repository-url/k8s-network-test-daemonset:0.1
```

## Deploy

In k8s.yml, replace "##DOCKER_REGISTRY##/k8s-network-test-daemonset:##VERSION##" by the image name/version. In our environment,
the jenkins build pipeline takes care of that.
The set will run in the kube-system namespace. It add's the needed rbac (security) information also. If you do not have rbac enabled,
you might need to strip down the k8s.yml file a bit.

```
kubectl apply -f k8s.yml
```

## Example output:

```
[master1]$ kubectl get pods -n kube-system -o wide | grep k8s-network-test-daemonset

k8s-network-test-daemonset-2c7mk                           1/1       Running   0          39d       10.233.71.183    ahlt1828
k8s-network-test-daemonset-brxh6                           1/1       Running   0          39d       10.233.86.188    ahlt1827
k8s-network-test-daemonset-k6s9b                           1/1       Running   0          39d       10.233.116.142   ahlt1825
k8s-network-test-daemonset-kwsjp                           1/1       Running   0          38d       10.233.123.15    ahlt1625
k8s-network-test-daemonset-l47w7                           1/1       Running   1          39d       10.233.106.85    ahlt1826
k8s-network-test-daemonset-lsgn5                           1/1       Running   1          39d       10.233.114.195   ahlt1627
k8s-network-test-daemonset-mzw2z                           1/1       Running   0          39d       10.233.112.211   ahlt1799
k8s-network-test-daemonset-rwncl                           1/1       Running   1          4d        10.233.67.48     ahlt1626
k8s-network-test-daemonset-tmbbt                           1/1       Running   0          39d       10.233.110.83    ahlt1628
k8s-network-test-daemonset-tqxmx                           1/1       Running   0          39d       10.233.107.200   ahlt1569
k8s-network-test-daemonset-tvh57                           1/1       Running   0          39d       10.233.104.81    ahlt1632
k8s-network-test-daemonset-vzd4f                           1/1       Running   0          39d       10.233.68.25     ahlt1798
k8s-network-test-daemonset-wgn9j                           1/1       Running   0          39d       10.233.71.208    ahlt1630
k8s-network-test-daemonset-zvbfb                           1/1       Running   0          39d       10.233.91.169    ahlt1629

[master1]$ kubectl logs --tail 30 k8s-network-test-daemonset-2c7mk -n kube-system

... chopped some lines ...
Tue Jan 16 11:57:01 CET 2018 Tests running on node: ahlt1828, host: k8s-network-test-daemonset-2c7mk
DNS: 10.233.0.3 kube-dns.kube-system.svc.cluster.tst.local.
DNS: 10.233.104.72 kube-dns-5977b8689-2qbmq.
DNS: 10.233.116.133 kube-dns-5977b8689-xmh6h.
Testing 14 nodes
Checking: ahlt1828 141.93.123.164 Running - k8s-network-test-daemonset-2c7mk 10.233.71.183;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1827 141.93.123.163 Running - k8s-network-test-daemonset-brxh6 10.233.86.188;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1825 141.93.123.161 Running - k8s-network-test-daemonset-k6s9b 10.233.116.142;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1625 141.93.123.50 Running - k8s-network-test-daemonset-kwsjp 10.233.123.15;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1826 141.93.123.162 Running - k8s-network-test-daemonset-l47w7 10.233.106.85;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1627 141.93.123.52 Running - k8s-network-test-daemonset-lsgn5 10.233.114.195;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1799 141.93.123.146 Running - k8s-network-test-daemonset-mzw2z 10.233.112.211;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1626 141.93.123.51 Running - k8s-network-test-daemonset-rwncl 10.233.67.48;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1628 141.93.123.53 Running - k8s-network-test-daemonset-tmbbt 10.233.110.83;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1569 141.93.122.94 Running - k8s-network-test-daemonset-tqxmx 10.233.107.200;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1632 141.93.123.56 Running - k8s-network-test-daemonset-tvh57 10.233.104.81;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1798 141.93.123.145 Running - k8s-network-test-daemonset-vzd4f 10.233.68.25;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1630 141.93.123.55 Running - k8s-network-test-daemonset-wgn9j 10.233.71.208;  host-ping: 0.00 pod-ping: 0.00 - OK
Checking: ahlt1629 141.93.123.54 Running - k8s-network-test-daemonset-zvbfb 10.233.91.169;  host-ping: 0.00 pod-ping: 0.00 - OK
No status changes since previous test run.

```

## Notes

This daemonset has been tested on kubernetes 1.6.x (using flannel) and 1.8.4 (using calico).
The last one being much more stable than the first one ;-)

## Diagram

![Diagram](k8s-network-test-daemonset-tests.png?raw=true "Test endpoints")


