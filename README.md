# K8s cluster using Kubespray on Vagrant with GlusterFS with Ubuntu 20.04

## Overview

Going to setup kubernetes cluster on Ubuntu 20.04 using Kubespray + Vagrant
it will be 3 node cluster and each node will also have 10GB HDD attached to create GlusterFS
Memory on each node should be 1500MB

glusterfs is a scalable, distributed file system that integrates disk storage resources from multiple servers into a single global namespace to provide shared file storage.

### **glusterfs features**

- Can be expanded to several PB capacity
- Support handling thousands of clients
- Compatible with POSIX interface
- Use general hardware, ordinary server can be built
- Able to use file systems that support extended attributes, such as ext4, XFS
- Support industry standard protocols, such as NFS, SMB
- Provides many advanced functions, such as copy, quota, cross-regional replication, snapshot and bitrot detection
- Support for tuning according to different workloads

### **the mode of glusterfs volume**

`glusterfs`The `volume`model has many, including the following:

- Distributed volume (default mode): DHT, also called distributed volume: Randomly distribute files to a server node for storage using a hash algorithm.
- Replication mode: AFR, with replica x quantity when creating a volume: Copy files to replica x nodes.
- Stripe mode: Striped, the number of stripe x when creating a volume: Cut the file into data blocks and store them in stripe x nodes (similar to raid 0).
- Distributed striping mode: At least 4 servers are required to create. When creating a volume, stripe 2 server = 4 nodes: It is a combination of DHT and Striped.
- Distributed replication mode: At least 4 servers are required to create. When creating a volume, replica 2 server = 4 nodes: a combination of DHT and AFR.
- Striped replication volume mode: At least 4 servers are required to create. When creating a volume, stripe 2 replica 2 server = 4 nodes: It is a combination of Striped and AFR.
- Three modes are mixed: At least 8 servers are required to create. stripe 2 replica 2, every 4 nodes form a group.

### Step 1# Download repo with Vagrantfile and Spinup base nodes

```bash
git clone https://github.com/rahulinux/k8s-ubuntu-gfs
cd k8s-ubuntu
vagrant u
```

### Step 2# Download and setup environment for kubespray

```bash
git clone https://github.com/kubernetes-sigs/kubespray
cd kubespray
```

Note: please install sshpass tool and Python 3.7 on your base machine to use ansible and also vagrant status, make sure instances are up and running

```bash
virtualenv --python=<PATH_OF_PYTHON3>  venv
source venv/bin/activate
pip install -r requirements.txt
```

### Step 3# Apply kubespray

Setup inventory 

```bash
cp -a inventory/sample inventory/k8s-home
cat <<EOF > inventory/k8s-home/inventory.ini
# ## Configure 'ip' variable to bind kubernetes services on a
# ## different ip than the default iface
# ## We should set etcd_member_name for etcd cluster. The node that is not a etcd member do not need to set the value, or can set the empty string value.
[all]
node-1 ansible_host=192.168.10.10 ip=192.168.10.10 etcd_member_name=etcd1  ansible_ssh_user=vagrant ansible_ssh_pass=vagrant
node-2 ansible_host=192.168.10.11  ip=192.168.10.11 etcd_member_name=etcd2 ansible_ssh_user=vagrant ansible_ssh_pass=vagrant
node-3 ansible_host=192.168.10.12  ip=192.168.10.12 etcd_member_name=etcd3 ansible_ssh_user=vagrant ansible_ssh_pass=vagrant

# ## configure a bastion host if your nodes are not directly reachable
# bastion ansible_host=x.x.x.x ansible_user=some_user

[kube-master]
node-1
node-2
node-3

[etcd]
node-1
node-2
node-3

[kube-node]
node-1
node-2
node-3

[calico-rr]

[k8s-cluster:children]
kube-master
kube-node
calico-rr
EOF
```

Check connection 

```bash
export PATH=$PWD/venv/bin/:$PATH
export ANSIBLE_HOST_KEY_CHECKING=False
ansible -vv -i inventory/k8s-home/inventory.ini  all -m ping
```

Output should be

```bash
node-1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
node-2 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
node-3 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Run playbook 

```bash
ansible-playbook  -b -i inventory/k8s-home/inventory.ini   cluster.yml  -vvv
```

Output should be at the end 

```bash
PLAY RECAP ***********************************************************************************************************************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node-1                     : ok=573  changed=125  unreachable=0    failed=0    skipped=1076 rescued=0    ignored=1
node-2                     : ok=493  changed=111  unreachable=0    failed=0    skipped=930  rescued=0    ignored=1
node-3                     : ok=495  changed=112  unreachable=0    failed=0    skipped=928  rescued=0    ignored=1
```

Now your kubernetes cluster is Up and Running you can login to any node using `vagrant ssh node-1` then configure `kubectl` by copying `sudo cp /etc/kubernetes/admin.conf .kube/config` and check get pods from kube-system namespace

### Step 4# Install glusterfs  clients on all nodes

```bash
modprobe dm_thin_pool
modprobe dm_snapshot
modprobe dm_mirror
apt install -y glusterfs-client

```

Apply storage labels to all nodes 

```bash
for node in node-{1..3};
do
  kubectl label nodes $node storagenode=glusterfs;
done
```

## Step 5# Deploy deamonset for glusterfs service

```bash
git clone https://github.com/heketi/heketi
cd heketi/extras/kubernetes
kubectl create -f glusterfs-daemonset.json
kubectl get pods 
# Wait until all pods start running
```

Optional 

```bash

kubectl exec -it  glusterfs-bvjtq -- gluster peer status
```

## Step 6# Deploy Heketi

Its RESTAPI for GlusterFS

- *RESTful based volume management framework for GlusterFS*
- *Heketi provides a RESTful management interface which can be used to manage the life cycle of GlusterFS volumes. With Heketi, cloud services like OpenStack Manila, Kubernetes, and OpenShift can dynamically provision GlusterFS volumes with any of the supported durability types. Heketi will automatically determine the location for bricks across the cluster, making sure to place bricks and its replicas across different failure domains. Heketi also supports any number of GlusterFS clusters, allowing cloud services to provide network file storage without being limited to a single GlusterFS cluster.*

```bash
# create a Heketi service account
kubectl create -f heketi-service-account.json
```

We must now establish the ability for that service account to control the gluster pods. We do this by creating a cluster role binding for our newly created service account:

```bash
kubectl create clusterrolebinding heketi-gluster-admin --clusterrole=edit --serviceaccount=default:heketi-service-account
```

Create a Kubernetes secret that will hold the configuration of our Heketi instance

```bash
kubectl create secret generic heketi-config-secret --from-file=./heketi.json
```

Then create a first initial heketi pod, that we’ll use for the first few configuration steps and remove it after that:

```bash
kubectl create -f heketi-bootstrap.json

```

heketi-client to interact with heketi server 

```bash
wget https://github.com/heketi/heketi/releases/download/v8.0.0/heketi-client-v8.0.0.linux.amd64.tar.gz
tar -xzvf ./heketi-client-v8.0.0.linux.amd64.tar.gz
cp ./heketi-client/bin/heketi-cli /usr/local/bin/
heketi-cli
```

To Access heketi restip 

```bash
HEKETI_IP=$(kubectl get svc deploy-heketi  --template='{{.spec.clusterIP}}')

```

Test connection 

```bash

curl http://$HEKETI_IP:8080/hello

```

Output should be

```bash
Hello from Heketi
```

```bash
export HEKETI_CLI_SERVER=http://$HEKETI_IP:8080
```

Provide a Heketi with information about the GlusterFS cluster it is to manage.

We provide this information via a topology file. Topology is a JSON manifest with the list of all nodes, disks, and clusters used by GlusterFS.

- NOTE: Make sure that hostnames/manage points to the exact name as shown under kubectl get nodes, and hostnames/storage is the IP address of the storage nodes.

Create `topology.json` as below:

```json
{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                "node-1"
              ],
              "storage": [
                "192.168.10.10"
              ]
            },
            "zone": 1
          },
          "devices": [
            {
              "name": "/dev/sdb",
              "destroydata": false
            }
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "node-2"
              ],
              "storage": [
                "192.168.10.11"
              ]
            },
            "zone": 1
          },
          "devices": [
            {
              "name": "/dev/sdb",
              "destroydata": false
            }
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "node-3"
              ],
              "storage": [
                "192.168.10.12"
              ]
            },
            "zone": 1
          },
          "devices": [
            {
              "name": "/dev/sdb",
              "destroydata": false
            }
          ]
        }
      ]
    }
  ]
}
```

Load topology 

```json
heketi-cli topology load --json=topology.json
```

You will get following error:

*Error: Unable to get topology information: Invalid JWT token: Token missing iss claim* 

So use:

```bash
heketi-cli -s $HEKETI_CLI_SERVER --user admin --secret 'My Secret' topology load --json=topology.json
```

You should see following output:

```bash
Found node node-1 on cluster 8e1058ad30d8b423f52d17866a3e9618
		Adding device /dev/sdb ... OK
	Found node node-2 on cluster 8e1058ad30d8b423f52d17866a3e9618
		Adding device /dev/sdb ... OK
	Found node node-3 on cluster 8e1058ad30d8b423f52d17866a3e9618
		Adding device /dev/sdb ... OK
```

After executing heketi-cli topology load, the general operations Heketi does on the server are as follows:

- Enter any glusterfs Pod and execute gluster peer status to find that the peer has been added to the trusted storage pool (TSP).
- On the node where the gluster Pod is running, a VG is automatically created. This VG is created by the bare disk device in the topology-sample.json file.
- A disk device creates a VG, and the PVC created later is the LV divided from this VG.
- heketi-cli topology info View the topology, display the ID of each disk device, the ID of the corresponding VG, total space, used space, free space and other information.

    View through partial logs

```bash
kubectl logs -f  deploy-heketi-6565469fdf-mcbvs
[kubeexec] DEBUG 2020/12/19 18:32:51 heketi/pkg/remoteexec/log/commandlog.go:46:log.(*CommandLogger).Success: Ran command [/usr/sbin/lvm pvs -o pv_name,pv_uuid,vg_name --reportformat=json /dev/sdb] on [pod:glusterfs-bvjtq c:glusterfs ns:default (from host:node-3 selector:glusterfs-node)]: Stdout [  {
      "report": [
          {
              "pv": [
                  {"pv_name":"/dev/sdb", "pv_uuid":"Iqe8ij-AaRO-Pc35-qvJX-o6QH-Hj20-AFYmVM", "vg_name":"vg_eb92c3c8a958ce046da40fa451d0d311"}
              ]
          }
      ]
  }
```

### persistent heketi configuration

The heketi created above is not configured with a persistent volume. If the pod of heketi is restarted, the previous configuration information may be lost, so now create a heketi persistent volume to persist the heketi data. This persistence method uses the dynamics provided by gfs Storage can also be persisted in other ways.

Install `device-mapper*` for centos and `libdevmapper-dev` ubuntu  on all nodes

```bash
apt-get install -y libdevmapper-dev 

```

Save the configuration information as a file and create persistent related information

```bash
heketi-cli -s $HEKETI_CLI_SERVER --user admin --secret 'My Secret' setup-openshift-heketi-storage Saving heketi-storage.json
kubectl apply -f heketi-storage.json
```

Delete intermediates

```bash
kubectl delete all,svc,jobs,deployment,secret --selector="deploy-heketi"
```

Create heketi deployment 

```bash
kubectl apply -f heketi-deployment.json
```

Output 

```bash
root@node-1:~/heketi/extras/kubernetes# kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
glusterfs-bvjtq          1/1     Running   0          68m
glusterfs-n8sqg          1/1     Running   0          68m
glusterfs-sqvjw          1/1     Running   0          68m
heketi-d94cd58f9-lklqh   1/1     Running   0          18s
```

Get heketi new IP

```bash
HEKETI_IP=$(kubectl get svc heketi  --template='{{.spec.clusterIP}}')
export HEKETI_CLI_SERVER=http://$HEKETI_IP:8080
curl $HEKETI_CLI_SERVER/hello
```

View gfs cluster information, refer to official documentation for more operations

```bash
heketi-cli -s $HEKETI_CLI_SERVER --user admin --secret 'My Secret' topology info
```

Output:

```bash
Cluster Id: 8e1058ad30d8b423f52d17866a3e9618

    File:  true
    Block: true

    Volumes:

	Name: heketidbstorage
	Size: 2
	Id: b4298da3e8f803d7af3afcdfc546141f
	Cluster Id: 8e1058ad30d8b423f52d17866a3e9618
	Mount: 192.168.10.12:heketidbstorage
	Mount Options: backup-volfile-servers=192.168.10.10,192.168.10.11
	Durability Type: replicate
	Replica: 3
	Snapshot: Disabled

		Bricks:
			Id: 54ce41fab1c1407e1c21ddf44795f285
			Path: /var/lib/heketi/mounts/vg_5fa97208362c4008502dda627731af94/brick_54ce41fab1c1407e1c21ddf44795f285/brick
			Size (GiB): 2
			Node: fa8ca92b6591b4d2d51029088ea97777
			Device: 5fa97208362c4008502dda627731af94

			Id: 7d09f3abc1aeb6f28f18d27d162c7939
			Path: /var/lib/heketi/mounts/vg_eb92c3c8a958ce046da40fa451d0d311/brick_7d09f3abc1aeb6f28f18d27d162c7939/brick
			Size (GiB): 2
			Node: 5fe690aa48a67900221ccc7cd71bf597
			Device: eb92c3c8a958ce046da40fa451d0d311

			Id: f307f2a468d95b7d5393fddac5ba51ac
			Path: /var/lib/heketi/mounts/vg_0dde14620d81a618cdf8d47818075035/brick_f307f2a468d95b7d5393fddac5ba51ac/brick
			Size (GiB): 2
			Node: 7b80e0cc546fd3afb0435ea0476f041e
			Device: 0dde14620d81a618cdf8d47818075035

    Nodes:

	Node Id: 5fe690aa48a67900221ccc7cd71bf597
	State: online
	Cluster Id: 8e1058ad30d8b423f52d17866a3e9618
	Zone: 1
	Management Hostnames: node-3
	Storage Hostnames: 192.168.10.12
	Devices:
		Id:eb92c3c8a958ce046da40fa451d0d311   Name:/dev/sdb            State:online    Size (GiB):9       Used (GiB):2       Free (GiB):7
			Bricks:
				Id:7d09f3abc1aeb6f28f18d27d162c7939   Size (GiB):2       Path: /var/lib/heketi/mounts/vg_eb92c3c8a958ce046da40fa451d0d311/brick_7d09f3abc1aeb6f28f18d27d162c7939/brick

	Node Id: 7b80e0cc546fd3afb0435ea0476f041e
	State: online
	Cluster Id: 8e1058ad30d8b423f52d17866a3e9618
	Zone: 1
	Management Hostnames: node-1
	Storage Hostnames: 192.168.10.10
	Devices:
		Id:0dde14620d81a618cdf8d47818075035   Name:/dev/sdb            State:online    Size (GiB):9       Used (GiB):2       Free (GiB):7
			Bricks:
				Id:f307f2a468d95b7d5393fddac5ba51ac   Size (GiB):2       Path: /var/lib/heketi/mounts/vg_0dde14620d81a618cdf8d47818075035/brick_f307f2a468d95b7d5393fddac5ba51ac/brick

	Node Id: fa8ca92b6591b4d2d51029088ea97777
	State: online
	Cluster Id: 8e1058ad30d8b423f52d17866a3e9618
	Zone: 1
	Management Hostnames: node-2
	Storage Hostnames: 192.168.10.11
	Devices:
		Id:5fa97208362c4008502dda627731af94   Name:/dev/sdb            State:online    Size (GiB):9       Used (GiB):2       Free (GiB):7
			Bricks:
				Id:54ce41fab1c1407e1c21ddf44795f285   Size (GiB):2       Path: /var/lib/heketi/mounts/vg_5fa97208362c4008502dda627731af94/brick_54ce41fab1c1407e1c21ddf44795f285/brick
```

## Create a storageclass

Create file `storageclass-gfs-heketi.yaml` as below 

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gluster-heketi
provisioner: kubernetes.io/glusterfs
reclaimPolicy: Retain
parameters:
  resturl: "http://ADD-HEKETI-IP-FROM-SVC:8080"
  restauthenabled: "true"
  restuser: "admin"
  restuserkey: "My Secret"
  gidMin: "40000"
  gidMax: "50000"
  volumetype: "replicate:3"
allowVolumeExpansion: true
```

```yaml
kubectl apply -f storageclass-gfs-heketi.yaml

```

Parameter Description:

- reclaimPolicy: Retain recycling policy. The default is Delete. After pvc is deleted, the volume and brick (lvm) created by the pv and the backend will not be deleted.
- gidMin and gidMax, the smallest and largest gid that can be used
- volumetype: volume type and number, here is a copy volume, the number must be greater than 1

### Test to provide dynamic storage through gfs

Create file `pod-gfs-pvc.yml` 

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-use-pvc
spec:
  containers:
  - name: pod-use-pvc
    image: busybox
    command:
      - sleep
      - "3600"
    volumeMounts:
    - name: gluster-volume
      mountPath: "/pv-data"
      readOnly: false
  volumes:
  - name: gluster-volume
    persistentVolumeClaim:
      claimName: pvc-gluster-heketi

---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-gluster-heketi
spec:
  accessModes: [ "ReadWriteOnce" ]
  storageClassName: "gluster-heketi"
  resources:
    requests:
      storage: 1Gi
```

Cassandra 

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cassandra
  labels:
    app: cassandra
spec:
  serviceName: cassandra
  replicas: 3
  selector:
    matchLabels:
      app: cassandra
  template:
    metadata:
      labels:
        app: cassandra
    spec:
      terminationGracePeriodSeconds: 1800
      containers:
      - name: cassandra
        image: gcr.io/google-samples/cassandra:v13
        imagePullPolicy: Always
        ports:
        - containerPort: 7000
          name: intra-node
        - containerPort: 7001
          name: tls-intra-node
        - containerPort: 7199
          name: jmx
        - containerPort: 9042
          name: cql
        resources:
          limits:
            cpu: "500m"
            memory: 800Mi
          requests:
            cpu: "500m"
            memory: 800Mi
        securityContext:
          capabilities:
            add:
              - IPC_LOCK
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/sh
              - -c
              - nodetool drain
        env:
          - name: MAX_HEAP_SIZE
            value: 512M
          - name: HEAP_NEWSIZE
            value: 100M
          - name: CASSANDRA_SEEDS
            value: "cassandra-0.cassandra.default.svc.cluster.local"
          - name: CASSANDRA_CLUSTER_NAME
            value: "K8Demo"
          - name: CASSANDRA_DC
            value: "DC1-K8Demo"
          - name: CASSANDRA_RACK
            value: "Rack1-K8Demo"
          - name: POD_IP
            valueFrom:
              fieldRef:
                fieldPath: status.podIP
        readinessProbe:
          exec:
            command:
            - /bin/bash
            - -c
            - /ready-probe.sh
          initialDelaySeconds: 15
          timeoutSeconds: 5
        # These volume mounts are persistent. They are like inline claims,
        # but not exactly because the names need to match exactly one of
        # the stateful pod volumes.
        volumeMounts:
        - name: cassandra-data
          mountPath: /cassandra_data
  volumeClaimTemplates:
  - metadata:
      name: cassandra-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "gluster-heketi"
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: cassandra
  name: cassandra
spec:
  clusterIP: None
  ports:
  - port: 9042
  selector:
    app: cassandra
```
