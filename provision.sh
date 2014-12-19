#!/bin/bash

set -e

echo "---------------------------------------------------------------"
echo "Installing Prerequisites..."
echo "---------------------------------------------------------------"
apt-get install -y g++ make curl mercurial git libprotobuf-dev

apt-get remove -y docker.io
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
echo "deb https://get.docker.com/ubuntu docker main" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y lxc-docker

# For convenience
apt-get install -y screen
echo "Done."
echo ""

echo "---------------------------------------------------------------"
echo "Installing Go 1.4..."
echo "---------------------------------------------------------------"
mkdir -p /usr/local/opt/gopath
cd /usr/local/opt
curl -L https://storage.googleapis.com/golang/go1.4.linux-amd64.tar.gz | tar xvz

export GOROOT=/usr/local/opt/go
export GOPATH=/usr/local/opt/gopath
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
cat <<EOF > /etc/profile.d/gopath.sh
export GOROOT=$GOROOT
export GOPATH=$GOPATH
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH
EOF
echo "Done."
echo ""

echo "---------------------------------------------------------------"
echo "Installing godep"
echo "---------------------------------------------------------------"
go get github.com/tools/godep
echo "Done."
echo ""

echo "---------------------------------------------------------------"
echo "Installing kubernetes-mesos"
echo "---------------------------------------------------------------"
cd $GOPATH

mkdir -p src/github.com/mesosphere/kubernetes-mesos
git clone https://github.com/mesosphere/kubernetes-mesos.git src/github.com/mesosphere/kubernetes-mesos
cd src/github.com/mesosphere/kubernetes-mesos
godep restore

go install github.com/GoogleCloudPlatform/kubernetes/cmd/{proxy,kubecfg}
go install github.com/mesosphere/kubernetes-mesos/kubernetes-{mesos,executor}
go install github.com/mesosphere/kubernetes-mesos/controller-manager

echo "Done."
echo ""

echo "---------------------------------------------------------------"
echo "Starting services..."
echo "---------------------------------------------------------------"
export servicehost=127.0.0.1

docker run -d --net=host coreos/etcd go-wrapper run \
   -advertise-client-urls=http://${servicehost}:4001 \
   -listen-client-urls=http://${servicehost}:4001 \
   -initial-advertise-peer-urls=http://${servicehost}:7001 \
   -listen-peer-urls=http://${servicehost}:7001

nohup kubernetes-mesos \
  -address=${servicehost} \
  -mesos_master=${servicehost}:5050 \
  -etcd_servers=http://${servicehost}:4001 \
  -executor_path=$(pwd)/bin/kubernetes-executor \
  -proxy_path=$(pwd)/bin/proxy -v=2  2>&1 >> /var/log/kubernetes-mesos.log &

export KUBERNETES_MASTER=http://${servicehost}:8888
cat <<EOF > /etc/profile.d/kubernetes.sh
export KUBERNETES_MASTER=http://${servicehost}:8888
EOF
nohup controller-manager -master=${KUBERNETES_MASTER#http://*} -v=2 2>&1 >> /var/log/controller-manager.log &

echo "Done."
echo ""
