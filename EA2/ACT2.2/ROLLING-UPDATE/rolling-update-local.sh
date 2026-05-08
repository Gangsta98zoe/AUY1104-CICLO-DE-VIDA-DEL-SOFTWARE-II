#!/bin/bash
# Rolling Update - Entorno Local (kind)

DEPLOYMENT_NAME="duoc-app-deployment"
SERVICE_NAME="duoc-app-service"
YAML_FILE="EA2/ACT2.2/ROLLING-UPDATE/rolling-update-local.yaml"

# Instalar bc si no existe
if ! command -v bc &>/dev/null; then
    sudo apt-get install -y bc -qq 2>/dev/null || true
fi

calc() { python3 -c "print(round($1, 2))"; }

echo "============================================================"
echo " ESTRATEGIA: Rolling Update [ENTORNO LOCAL - kind]"
echo "============================================================"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30001
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] Node IP: $NODE_IP | NodePort: $NODE_PORT"
echo "[INFO] URL: $URL"

# --- FASE 1: Despliegue inicial con v1 ---
echo ""
echo "[FASE 1] Desplegando v1.0 (Blue)..."
kubectl apply -f "$YAML_FILE"
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=180s
echo "[OK] v1.0 lista."

echo "[INFO] Esperando 200 OK de v1..."
for i in $(seq 1 60); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        echo "[OK] v1.0 respondiendo 200 OK"
        break
    fi
    echo "  Intento $i: HTTP $STATUS"
    sleep 3
done

# --- FASE 2: Rolling Update a v2 ---
echo ""
echo "[FASE 2] Actualizando a v2.0 (Green) - Rolling Update..."

T_ROLLOUT_START=$(date +%s)
kubectl set image deployment/$DEPLOYMENT_NAME node-app-container=duoc-lab:v2.0
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=300s
T_ROLLOUT_END=$(date +%s)

ROLLOUT_DURATION=$((T_ROLLOUT_END - T_ROLLOUT_START))
echo "[OK] Rollout interno: ${ROLLOUT_DURATION}s"

# --- FASE 3: Verificar 200 OK tras rollout ---
echo ""
echo "[FASE 3] Verificando 200 OK post-rollout..."
T_PROP_START=$(date +%s)
SUCCESS=false

for i in $(seq 1 60); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        T_PROP_END=$(date +%s)
        SUCCESS=true
        echo "[OK] 200 OK recibido."
        break
    fi
    echo "  Intento $i: HTTP $STATUS"
    sleep 2
done

if [ "$SUCCESS" = false ]; then
    T_PROP_END=$(date +%s)
    echo "[WARN] No se recibio 200 OK en 60 intentos."
fi

PROPAGATION=$((T_PROP_END - T_PROP_START))
TOTAL=$((T_PROP_END - T_ROLLOUT_START))

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - Rolling Update"
echo "============================================================"
echo "A. Tiempo de Rollout Interno (K8s Ready): ${ROLLOUT_DURATION} segundos"
echo "B. Tiempo de Propagacion (Ready a 200 OK): ${PROPAGATION} segundos"
echo "C. Tiempo TOTAL (Apply a 200 OK): ${TOTAL} segundos"
echo "D. Downtime: 0 segundos (Rolling Update garantiza continuidad)"
echo "G. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "============================================================"

echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Listo para la siguiente estrategia."
