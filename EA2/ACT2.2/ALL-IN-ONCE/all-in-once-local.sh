#!/bin/bash
# All-In-Once (Recreate) - Entorno Local (kind)
# Mide el downtime real: el tiempo en que el servicio no responde entre v1 y v2.

DEPLOYMENT_NAME="duoc-app-deployment"
SERVICE_NAME="duoc-app-service"
YAML_FILE="EA2/ACT2.2/ALL-IN-ONCE/all-in-once-local.yaml"
STRATEGY="recreate"

echo "============================================================"
echo " ESTRATEGIA: All-In-Once / Recreate [ENTORNO LOCAL - kind]"
echo "============================================================"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30002
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] URL de acceso: $URL"

# --- FASE 1: Desplegar v1 ---
echo ""
echo "[FASE 1] Desplegando version v1.0 (Blue)..."
kubectl apply -f "$YAML_FILE"
kubectl rollout status deployment/$DEPLOYMENT_NAME --timeout=180s

echo "[INFO] Esperando 200 OK de v1..."
for i in $(seq 1 60); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "[OK] v1.0 respondiendo 200 OK" && break
    sleep 2
done

# --- FASE 2: Actualizar a v2 (Recreate: mata todos los pods primero) ---
echo ""
echo "[FASE 2] Actualizando a v2.0 (Green) - Estrategia Recreate..."
echo "[INFO] Recreate eliminara TODOS los pods de v1 antes de crear los de v2."

START_UPDATE=$(date +%s.%N)
kubectl set image deployment/$DEPLOYMENT_NAME node-app-container=duoc-lab:v2.0

# --- FASE 3: Medir downtime en background ---
echo "[FASE 3] Midiendo downtime en tiempo real..."
DOWNTIME_START=""
DOWNTIME_END=""
DOWNTIME_SECONDS=0
MEASURING=true

# Loop de monitoreo: detecta cuando el servicio cae y cuando vuelve
while $MEASURING; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$URL" 2>/dev/null)

    if [ "$STATUS" != "200" ] && [ -z "$DOWNTIME_START" ]; then
        DOWNTIME_START=$(date +%s.%N)
        echo "[DOWNTIME DETECTADO] El servicio dejo de responder 200 OK."
    fi

    if [ "$STATUS" = "200" ] && [ ! -z "$DOWNTIME_START" ]; then
        DOWNTIME_END=$(date +%s.%N)
        echo "[SERVICIO RECUPERADO] Respuesta 200 OK recibida de v2.0."
        MEASURING=false
    fi

    # Timeout de seguridad: 5 minutos
    ELAPSED=$(echo "$(date +%s.%N) - $START_UPDATE" | bc)
    if [ $(echo "$ELAPSED > 300" | bc -l) -eq 1 ]; then
        echo "[TIMEOUT] Se supero el tiempo de espera."
        MEASURING=false
    fi
    sleep 0.5
done

END_UPDATE=$(date +%s.%N)
TOTAL_DURATION=$(echo "$END_UPDATE - $START_UPDATE" | bc)

if [ ! -z "$DOWNTIME_START" ] && [ ! -z "$DOWNTIME_END" ]; then
    DOWNTIME_DURATION=$(echo "$DOWNTIME_END - $DOWNTIME_START" | bc)
else
    DOWNTIME_DURATION="No medido (transicion muy rapida)"
fi

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - All-In-Once (Recreate)"
echo "============================================================"
echo "A. Tiempo de Despliegue Total (Apply a 200 OK): $TOTAL_DURATION segundos"
echo "B. Downtime (Interrupcion del Servicio): $DOWNTIME_DURATION segundos"
echo "C. Tiempo TOTAL hasta Recuperacion: $TOTAL_DURATION segundos"
echo "G. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "============================================================"
echo "[!] NOTA: El downtime es la diferencia critica con Rolling Update."

# Limpieza
echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Listo para la siguiente estrategia."
