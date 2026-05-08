#!/bin/bash
# All-In-Once (Recreate) - Entorno Local (kind)

DEPLOYMENT_NAME="duoc-app-deployment"
SERVICE_NAME="duoc-app-service"
YAML_FILE="EA2/ACT2.2/ALL-IN-ONCE/all-in-once-local.yaml"

echo "============================================================"
echo " ESTRATEGIA: All-In-Once / Recreate [ENTORNO LOCAL - kind]"
echo "============================================================"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30002
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] URL: $URL"

# --- FASE 1: Desplegar v1 ---
echo ""
echo "[FASE 1] Desplegando v1.0 (Blue)..."
kubectl apply -f "$YAML_FILE"
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=180s

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

# --- FASE 2: Actualizar a v2 con estrategia Recreate ---
echo ""
echo "[FASE 2] Actualizando a v2.0 - Estrategia Recreate (elimina todos los pods primero)..."

T_UPDATE_START=$(date +%s)
kubectl set image deployment/$DEPLOYMENT_NAME node-app-container=duoc-lab:v2.0

# Monitorear downtime
DOWNTIME_START=""
DOWNTIME_END=""
echo "[INFO] Monitoreando disponibilidad..."

for i in $(seq 1 120); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$URL" 2>/dev/null)

    if [ "$STATUS" != "200" ] && [ -z "$DOWNTIME_START" ]; then
        DOWNTIME_START=$(date +%s)
        echo "  [!] DOWNTIME INICIO (intento $i) - HTTP: $STATUS"
    fi

    if [ "$STATUS" = "200" ] && [ ! -z "$DOWNTIME_START" ] && [ -z "$DOWNTIME_END" ]; then
        DOWNTIME_END=$(date +%s)
        echo "  [OK] SERVICIO RECUPERADO (intento $i) - HTTP: 200"
        break
    fi

    [ -z "$DOWNTIME_START" ] && echo "  Intento $i: HTTP $STATUS (aun OK)"
    sleep 1
done

T_UPDATE_END=$(date +%s)
TOTAL_DURATION=$((T_UPDATE_END - T_UPDATE_START))

if [ ! -z "$DOWNTIME_START" ] && [ ! -z "$DOWNTIME_END" ]; then
    DOWNTIME_DURATION=$((DOWNTIME_END - DOWNTIME_START))
else
    DOWNTIME_DURATION="No capturado (verificar manualmente)"
fi

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - All-In-Once (Recreate)"
echo "============================================================"
echo "A. Tiempo TOTAL de Despliegue (Apply a 200 OK): ${TOTAL_DURATION} segundos"
echo "B. Downtime (Interrupcion del Servicio): ${DOWNTIME_DURATION} segundos"
echo "C. Tiempo hasta Recuperacion: ${TOTAL_DURATION} segundos"
echo "G. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "============================================================"
echo "[!] El Downtime es la diferencia critica frente a Rolling Update."

echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Listo para la siguiente estrategia."
