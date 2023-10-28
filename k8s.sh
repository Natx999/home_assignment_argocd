#! /bin/bash

main () {
    case $1 in
        cluster_setup)
            cluster_setup
            ;;
        argocd_setup)
            argocd_setup
            ;;
        run_test)
            run_test
            ;;
        *)
            echo -n "Incorrect or no flag found"
    esac
}

cluster_setup () {
    sudo apt-get update -y
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        wget
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    sudo apt install docker.io -y
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.6/cri-dockerd_0.3.6.3-0.ubuntu-bionic_amd64.deb
    sudo dpkg -i cri-dockerd_0.3.6.3-0.ubuntu-bionic_amd64.deb
    sudo systemctl daemon-reload
    sudo systemctl enable cri-docker.service
    sudo systemctl enable --now cri-docker.socket
    systemctl status cri-docker.socket
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -y
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///var/run/cri-dockerd.sock
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    cd ~
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml -O
    kubectl apply -f calico.yaml
    kubectl taint nodes $(kubectl get nodes --no-headers | cut -d " " -f 1) node-role.kubernetes.io/control-plane:NoSchedule-
    status=0
    while [ ! $status -eq 200 ] ; do
        status=$(curl -k 'https://localhost:6443/readyz?verbose&exclude=etcd' -w "%{http_code}" -s -o /dev/null)
    done
    echo "K8s cluster is up and running!"
}

argocd_setup () {
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml
    kubectl patch svc argocd-server -n argocd --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"},{"op":"replace","path":"/spec/ports/0/nodePort","value":30040}]'
}

main
