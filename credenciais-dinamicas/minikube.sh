#!/bin/bash
set -euf -o pipefail

minikube start --vm-driver kvm2

# TODO
## run vault on minikube
## expose vault on localhost
