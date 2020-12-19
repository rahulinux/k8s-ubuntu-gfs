# K8s cluster using Kubespray on Vagrant with GlusterFS with Ubuntu 20.04 

### Step 1# Download repo with Vagrantfile and Spinup base nodes

```bash
git clone ..
cd k8s-ubuntu
vagrant u
```

### Step 2# Download and setup environment for kubespray

```bash
git clone https://github.com/kubernetes-sigs/kubespray
cd kubespray
```

Compose host file by using sample at `inventory/sample` and then run playbook
Check readme file on kubespray
