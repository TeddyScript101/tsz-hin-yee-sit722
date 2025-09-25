#!/bin/bash

NAMESPACE="staging-18015381287"

echo -e "\n🔍 Checking Kubernetes resources in namespace: $NAMESPACE"

echo -e "\n📦 Pods status:"
kubectl get pods -n $NAMESPACE -o wide

echo -e "\n🔧 Services:"
kubectl get svc -n $NAMESPACE -o wide

echo -e "\n🔗 Endpoints:"
kubectl get endpoints -n $NAMESPACE -o wide

echo -e "\n🌐 RabbitMQ specific checks:"
echo -e "\nRabbitMQ Service details:"
kubectl get svc rabbitmq-service-w10-aks -n $NAMESPACE -o wide

echo -e "\nRabbitMQ Endpoint details:"
kubectl get endpoints rabbitmq-service-w10-aks -n $NAMESPACE -o yaml

echo -e "\n🔍 RabbitMQ Pod logs:"
RABBIT_POD=$(kubectl get pods -n $NAMESPACE -l app=rabbitmq -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$RABBIT_POD" ]; then
    kubectl logs $RABBIT_POD -n $NAMESPACE --tail=20
else
    echo "No RabbitMQ pod found with label app=rabbitmq"
    kubectl get pods -n $NAMESPACE | grep rabbit
fi

echo -e "\n📊 Detailed pod status:"
for pod in $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    echo -e "\n--- Status of $pod ---"
    kubectl get pod $pod -n $NAMESPACE -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
done

echo -e "\n🔌 Network connectivity test:"
echo -e "\nTesting service DNS resolution from within the cluster..."

# Create a temporary debug pod to test connectivity
kubectl run network-test --rm -i --tty --restart=Never --image=busybox -n $NAMESPACE -- \
    sh -c "
    echo '1. Testing DNS resolution:'
    nslookup rabbitmq-service-w10-aks.$NAMESPACE.svc.cluster.local
    echo ''
    nslookup customer-service-w10-aks.$NAMESPACE.svc.cluster.local
    echo ''
    
    echo '2. Testing port connectivity:'
    echo 'Testing RabbitMQ (5672):'
    if nc -z rabbitmq-service-w10-aks 5672; then
        echo '✅ RabbitMQ port 5672 is accessible'
    else
        echo '❌ Cannot connect to RabbitMQ port 5672'
    fi
    
    echo 'Testing Customer Service (8002):'
    if nc -z customer-service-w10-aks 8002; then
        echo '✅ Customer Service port 8002 is accessible'
    else
        echo '❌ Cannot connect to Customer Service port 8002'
    fi
    "

echo -e "\n🐰 RabbitMQ connection details from Order Service perspective:"
kubectl exec deployment/order-service-w10-aks -n $NAMESPACE -- \
    sh -c "cat /etc/hosts && echo '' && nslookup rabbitmq-service-w10-aks"

echo -e "\n📋 Recent Order Service logs:"
kubectl logs deployment/order-service-w10-aks -n $NAMESPACE --tail=50

echo -e "\n🔄 Checking if all services are communicating properly:"
echo -e "\nTesting service endpoints:"

# Test each service endpoint
kubectl run api-test --rm -i --tty --restart=Never --image=curlimages/curl:latest -n $NAMESPACE -- \
    sh -c "
    echo 'Testing Product Service (8000):'
    curl -s -o /dev/null -w 'Product Service: %{http_code}\n' http://product-service-w10-aks:8000/health || echo 'Product Service: FAILED'
    
    echo 'Testing Order Service (8001):'
    curl -s -o /dev/null -w 'Order Service: %{http_code}\n' http://order-service-w10-aks:8001/health || echo 'Order Service: FAILED'
    
    echo 'Testing Customer Service (8002):'
    curl -s -o /dev/null -w 'Customer Service: %{http_code}\n' http://customer-service-w10-aks:8002/health || echo 'Customer Service: FAILED'
    
    echo 'Testing Frontend (80):'
    curl -s -o /dev/null -w 'Frontend: %{http_code}\n' http://frontend-w10-aks:80/ || echo 'Frontend: FAILED'
    "

echo -e "\n🎯 RabbitMQ specific connectivity test:"
kubectl run rabbitmq-test --rm -i --tty --restart=Never --image=curlimages/curl:latest -n $NAMESPACE -- \
    sh -c "
    # Test if RabbitMQ management API is accessible (if enabled)
    echo 'Testing RabbitMQ management interface (if available):'
    curl -s -u guest:guest http://rabbitmq-service-w10-aks:15672/api/healthchecks/node 2>/dev/null | head -c 100 || echo 'RabbitMQ management interface not accessible'
    "