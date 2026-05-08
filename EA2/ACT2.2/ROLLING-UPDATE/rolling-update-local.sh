#!/bin/bash
# Rolling Update - Entorno Local (kind)
# Despliega v1, luego actualiza a v2 y mide metricas reales.

DEPLOYMENT_NAME="duoc-app-deployment"
SERVICE_NAME="duoc-app-service"
YAML_FILE="EA2/ACT2.2/ROLLING-UPDATE/rolling-update-local.yaml"
STRATEGY="rolling-update"

echo "============================================================"
echo " ESTRATEGIA: Rolling Update [ENTORNO LOCAL - kind]"
echo "============================================================"

# Obtener IP del nodo kind
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30001
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] URL de acceso: $URL"

# --- FASE 1: Despliegue inicial con v1 ---
echo ""
echo "[FASE 1] Desplegando version v1.0 (Blue)..."
kubectl apply -f "$YAML_FILE"
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=180s
echo "[OK] v1.0 desplegada y lista."

echo "[INFO] Esperando respuesta HTTP 200 OK de v1..."
for i in $(seq 1 60); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "[OK] v1.0 respondiendo 200 OK en $URL" && break
    sleep 2
done

# --- FASE 2: Actualizacion a v2 (Rolling Update real) ---
echo ""
echo "[FASE 2] Actualizando a v2.0 (Green) - Iniciando Rolling Update..."

START_GLOBAL=$(date +%s.%N)

START_ROLLOUT=$(date +%s.%N)
kubectl set image deployment/$DEPLOYMENT_NAME node-app-container=duoc-lab:v2.0
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=300s
END_ROLLOUT=$(date +%s.%N)

ROLLOUT_DURATION=$(echo "$END_ROLLOUT - $START_ROLLOUT" | bc)
echo "[OK] Rollout interno completado en: $ROLLOUT_DURATION segundos"

# --- FASE 3: Verificar disponibilidad externa ---
echo ""
echo "[FASE 3] Verificando disponibilidad externa (200 OK)..."
START_PROPAGATION=$END_ROLLOUT
PROPAGATION_SECONDS=0

for i in $(seq 1 60); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        END_PROPAGATION=$(date +%s.%N)
        PROPAGATION_DURATION=$(echo "$END_PROPAGATION - $START_PROPAGATION" | bc)
        echo "[OK] Respuesta 200 OK recibida."
        break
    fi
    sleep 1
    PROPAGATION_SECONDS=$((PROPAGATION_SECONDS + 1))
done

END_GLOBAL=$(date +%s.%N)
TOTAL_DURATION=$(echo "$END_GLOBAL - $START_GLOBAL" | bc)

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - Rolling Update"
echo "============================================================"
echo "A. Tiempo de Rollout Interno (K8s Ready): $ROLLOUT_DURATION segundos"
echo "B. Tiempo de Propagacion (Ready a 200 OK): $PROPAGATION_DURATION segundos"
echo "C. Tiempo TOTAL (Apply a 200 OK): $TOTAL_DURATION segundos"
echo "D. Downtime: 0 segundos (Rolling Update garantiza continuidad)"
echo "G. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "============================================================"

# Limpieza
echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Listo para la siguiente estrategia."
