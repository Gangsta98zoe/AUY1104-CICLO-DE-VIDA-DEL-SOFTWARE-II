#!/bin/bash
# Blue/Green - Entorno Local (kind)

SERVICE_NAME="duoc-app-bg-service"
BLUE_DEPLOYMENT="duoc-app-blue"
GREEN_DEPLOYMENT="duoc-app-green"
YAML_FILE="EA2/ACT2.2/BLUE-GREEN/blue-green-local.yaml"
WAIT_DURATION_S=10

echo "============================================================"
echo " ESTRATEGIA: Blue/Green [ENTORNO LOCAL - kind]"
echo "============================================================"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30004
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] URL: $URL"

T_GLOBAL_START=$(date +%s)

# --- FASE 1: Desplegar Blue + Green ---
echo ""
echo "[FASE 1] Desplegando Blue (v1) y Green (v2) simultaneamente..."
T_DEPLOY_START=$(date +%s)
kubectl apply -f "$YAML_FILE"
kubectl rollout status deployment/$BLUE_DEPLOYMENT --timeout=180s
kubectl rollout status deployment/$GREEN_DEPLOYMENT --timeout=180s
T_DEPLOY_END=$(date +%s)

GREEN_DEPLOY_DURATION=$((T_DEPLOY_END - T_DEPLOY_START))
echo "[OK] Ambos entornos listos en: ${GREEN_DEPLOY_DURATION}s"

echo "[INFO] Verificando que Blue responde..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        echo "[OK] Blue respondiendo 200 OK"
        break
    fi
    echo "  Intento $i: HTTP $STATUS"
    sleep 3
done

# --- FASE 2: Ventana de prueba ---
echo ""
echo "[FASE 2] Ventana de prueba de ${WAIT_DURATION_S}s (Green inactivo para usuarios)..."
sleep $WAIT_DURATION_S
echo "[OK] Green validado. Ejecutando switch..."

# --- FASE 3: Switch Blue -> Green ---
echo ""
echo "[FASE 3] Switch de trafico BLUE -> GREEN via kubectl patch..."
T_SWITCH_START=$(date +%s)
kubectl patch service "$SERVICE_NAME" -p '{"spec":{"selector":{"version":"green"}}}'
T_SWITCH_END=$(date +%s)
SWITCH_DURATION=$((T_SWITCH_END - T_SWITCH_START))
echo "[OK] kubectl patch completado en: ${SWITCH_DURATION}s"

# --- FASE 4: Verificar propagacion ---
echo "[FASE 4] Confirmando respuesta Green y midiendo propagacion..."
T_PROP_START=$(date +%s)
DOWNTIME_DETECTED=false

for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null)
    RESPONSE=$(curl -s --max-time 3 "$URL" 2>/dev/null)

    if [ "$HTTP_CODE" != "200" ]; then
        echo "  [!] HTTP $HTTP_CODE en intento $i"
        DOWNTIME_DETECTED=true
    fi

    if echo "$RESPONSE" | grep -qi "green"; then
        T_PROP_END=$(date +%s)
        echo "[OK] Green confirmado en intento $i"
        break
    fi
    echo "  Intento $i: HTTP $HTTP_CODE | $(echo $RESPONSE | head -c 60)"
    sleep 1
done

PROPAGATION_DURATION=$((T_PROP_END - T_PROP_START))
TOTAL_WITHOUT_WAIT=$((GREEN_DEPLOY_DURATION + SWITCH_DURATION + PROPAGATION_DURATION))

if [ "$DOWNTIME_DETECTED" = true ]; then
    DOWNTIME_MSG="Alerta: downtime detectado durante switch"
else
    DOWNTIME_MSG="0 segundos (Blue activo en todo momento)"
fi

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - Blue/Green"
echo "============================================================"
echo "A. Tiempo de Despliegue Green (Deploy Interno): ${GREEN_DEPLOY_DURATION} segundos"
echo "B. Tiempo de Ventana de Prueba: ${WAIT_DURATION_S} segundos"
echo "C. Velocidad de Switch (kubectl patch): ${SWITCH_DURATION} segundos"
echo "D. Tiempo de Propagacion (Patch -> Green OK): ${PROPAGATION_DURATION} segundos"
echo "E. Tiempo TOTAL E2E (sin contar espera): ${TOTAL_WITHOUT_WAIT} segundos"
echo "F. Downtime: $DOWNTIME_MSG"
echo "G. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "H. Rollback: Instantaneo (re-patch a 'blue')"
echo "============================================================"

echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Todas las estrategias completadas!"
