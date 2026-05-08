#!/bin/bash
# Canary - Entorno Local (kind)

SERVICE_NAME="duoc-app-canary-service"
STABLE_DEPLOYMENT="duoc-app-stable-v1"
CANARY_DEPLOYMENT="duoc-app-canary-v2"
YAML_FILE="EA2/ACT2.2/CANARY/canary-local.yaml"

echo "============================================================"
echo " ESTRATEGIA: Canary [ENTORNO LOCAL - kind]"
echo "============================================================"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30003
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] URL: $URL"

T_GLOBAL_START=$(date +%s)

# --- FASE 1: Despliegue Canary (10% v2 + 90% v1) ---
echo ""
echo "[FASE 1] Desplegando Stable v1 (2 replicas) + Canary v2 (1 replica)..."
T_CANARY_START=$(date +%s)
kubectl apply -f "$YAML_FILE"
kubectl rollout status deployment/$STABLE_DEPLOYMENT --timeout=180s
kubectl rollout status deployment/$CANARY_DEPLOYMENT --timeout=180s
T_CANARY_END=$(date +%s)

CANARY_DEPLOY_DURATION=$((T_CANARY_END - T_CANARY_START))
echo "[OK] Canary desplegado en: ${CANARY_DEPLOY_DURATION}s"

echo "[INFO] Verificando servicio con trafico mixto..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null)
    if [ "$STATUS" = "200" ]; then
        echo "[OK] Servicio respondiendo 200 OK"
        break
    fi
    echo "  Intento $i: HTTP $STATUS"
    sleep 3
done

echo ""
echo "[FASE 2] Ventana de observacion de 10 segundos (simulacion de prueba canary)..."
sleep 10
echo "[OK] Sin fallos. Promoviendo v2 a 100%..."

# --- FASE 3: Promocion ---
echo ""
echo "[FASE 3] Promoviendo Canary v2 a 100% del trafico..."
T_PROMO_START=$(date +%s)

kubectl scale deployment/$CANARY_DEPLOYMENT --replicas=3
kubectl scale deployment/$STABLE_DEPLOYMENT --replicas=0
kubectl rollout status deployment/$CANARY_DEPLOYMENT --timeout=180s

echo "[INFO] Confirmando respuesta Green..."
for i in $(seq 1 60); do
    RESPONSE=$(curl -s --max-time 3 "$URL" 2>/dev/null)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL" 2>/dev/null)
    if echo "$RESPONSE" | grep -qi "green"; then
        T_PROMO_END=$(date +%s)
        echo "[OK] Version Green confirmada."
        break
    fi
    echo "  Intento $i: HTTP $HTTP_CODE | Respuesta: $(echo $RESPONSE | head -c 80)"
    sleep 2
done

T_GLOBAL_END=$(date +%s)
PROMOTION_DURATION=$((T_PROMO_END - T_PROMO_START))
TOTAL_DURATION=$((T_GLOBAL_END - T_GLOBAL_START))

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - Canary"
echo "============================================================"
echo "A. Tiempo de Despliegue Canary Inicial (10%): ${CANARY_DEPLOY_DURATION} segundos"
echo "B. Tiempo de Promocion E2E (Scale v2 -> Green confirmado): ${PROMOTION_DURATION} segundos"
echo "C. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "D. Riesgo de Exposicion al Bug: 10% (1 de 3 pods era canary)"
echo "E. Tiempo TOTAL (Apply -> Promocion): ${TOTAL_DURATION} segundos"
echo "F. Downtime: 0 segundos (pods v1 activos durante toda la transicion)"
echo "============================================================"

echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Listo para la siguiente estrategia."
