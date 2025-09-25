#!/bin/bash
# debug-product-service.sh
# Usage: ./debug-product-service.sh <namespace>

NAMESPACE=${1:-staging-18019609176}  # default if not provided
DEPLOYMENT="product-service-w10-aks"

echo "🔍 Checking deployment status for $DEPLOYMENT in namespace $NAMESPACE..."
kubectl get deployment $DEPLOYMENT -n $NAMESPACE

echo -e "\n📦 Listing all pods in the deployment..."
kubectl get pods -n $NAMESPACE -l app=product-service

# Identify any pods in non-ready state
PODS=$(kubectl get pods -n $NAMESPACE -l app=product-service -o jsonpath='{.items[*].metadata.name}')
for pod in $PODS; do
    READY=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].ready}')
    if [ "$READY" != "true" ]; then
        echo -e "\n⚠️ Pod $pod is not ready. Describing pod..."
        kubectl describe pod $pod -n $NAMESPACE

        echo -e "\n📝 Fetching logs for pod $pod..."
        kubectl logs $pod -n $NAMESPACE --all-containers
    fi
done

# Test if RabbitMQ service is reachable from inside a temporary pod
echo -e "\n🔌 Testing RabbitMQ connectivity..."
kubectl run -i --rm debug-rabbitmq --image=busybox --restart=Never -n $NAMESPACE -- sh -c "wget -qO- rabbitmq-service-w10-aks:5672 || echo 'RabbitMQ not reachable'"

echo -e "\n✅ Debug script completed."
