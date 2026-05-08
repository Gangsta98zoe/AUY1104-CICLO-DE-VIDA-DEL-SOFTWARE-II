#!/bin/bash
set -e

echo "=== Setup de Entorno Local (kind + Docker) ==="

# 1. Instalar kind si no existe
if ! command -v kind &> /dev/null; then
    echo "[1] Instalando kind..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
fi
echo "[OK] kind: $(kind version)"

# 2. Crear cluster si no existe
if ! kind get clusters 2>/dev/null | grep -q "duoc-cluster"; then
    echo "[2] Creando cluster kind 'duoc-cluster'..."
    kind create cluster --name duoc-cluster
else
    echo "[OK] Cluster 'duoc-cluster' ya existe"
fi
kubectl config use-context kind-duoc-cluster
kubectl get nodes

# 3. Construir imagenes Docker
echo "[3] Construyendo imagenes Docker..."
docker build -t duoc-lab:v1.0 --build-arg BUILD_COLOR="Blue" . -q
echo "    [OK] duoc-lab:v1.0 (Blue)"
docker build -t duoc-lab:v2.0 --build-arg BUILD_COLOR="Green" . -q
echo "    [OK] duoc-lab:v2.0 (Green)"

# 4. Cargar imagenes en kind
echo "[4] Cargando imagenes en el cluster..."
kind load docker-image duoc-lab:v1.0 --name duoc-cluster
kind load docker-image duoc-lab:v2.0 --name duoc-cluster
echo "[OK] Imagenes disponibles en el cluster"

echo ""
echo "=== Setup completado! ==="
echo ""
echo "Ejecuta las estrategias en este orden:"
echo "  1. bash EA2/ACT2.2/ROLLING-UPDATE/rolling-update-local.sh"
echo "  2. bash EA2/ACT2.2/ALL-IN-ONCE/all-in-once-local.sh"
echo "  3. bash EA2/ACT2.2/CANARY/canary-local.sh"
echo "  4. bash EA2/ACT2.2/BLUE-GREEN/blue-green-local.sh"
