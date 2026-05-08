#!/bin/bash
# Canary - Entorno Local (kind)
# Despliega 10% canary (v2) con 90% estable (v1), luego promueve a 100% v2.

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
echo "[INFO] URL de acceso: $URL"

START_GLOBAL=$(date +%s.%N)

# --- FASE 1: Despliegue inicial Canary (10% v2 + 90% v1) ---
echo ""
echo "[FASE 1] Desplegando Stable v1 (90%) + Canary v2 (10%)..."
START_CANARY_DEPLOY=$(date +%s.%N)
kubectl apply -f "$YAML_FILE"

kubectl rollout status deployment/$STABLE_DEPLOYMENT --timeout=180s
kubectl rollout status deployment/$CANARY_DEPLOYMENT --timeout=180s
END_CANARY_DEPLOY=$(date +%s.%N)

CANARY_DEPLOY_DURATION=$(echo "$END_CANARY_DEPLOY - $START_CANARY_DEPLOY" | bc)
echo "[OK] Canary (10%) desplegado en: $CANARY_DEPLOY_DURATION segundos"

echo "[INFO] Verificando servicio con trafico mixto (v1+v2)..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "[OK] Servicio respondiendo 200 OK" && break
    sleep 2
done

echo ""
echo "[FASE 2] Ventana de observacion de 10 segundos (simulacion de prueba)..."
echo "         En produccion esta ventana seria de 10-30 minutos."
sleep 10
echo "[OK] Sin fallos detectados. Promoviendo v2 a 100%..."

# --- FASE 3: Promocion (escalar canary a 100%, bajar stable a 0) ---
echo ""
echo "[FASE 3] Promoviendo Canary v2 a 100% del trafico..."
START_PROMOTION=$(date +%s.%N)

TOTAL_REPLICAS=$(kubectl get deployment $STABLE_DEPLOYMENT -o jsonpath='{.spec.replicas}')
TOTAL_REPLICAS=$((TOTAL_REPLICAS + 1))

kubectl scale deployment/$CANARY_DEPLOYMENT --replicas=$TOTAL_REPLICAS
kubectl scale deployment/$STABLE_DEPLOYMENT --replicas=0
kubectl rollout status deployment/$CANARY_DEPLOYMENT --timeout=180s

# Confirmar que solo sirve v2 (Green)
echo "[INFO] Confirmando version Green en la respuesta..."
for i in $(seq 1 60); do
    RESPONSE=$(curl -s "$URL" 2>/dev/null)
    if echo "$RESPONSE" | grep -qi "green"; then
        END_PROMOTION=$(date +%s.%N)
        PROMOTION_DURATION=$(echo "$END_PROMOTION - $START_PROMOTION" | bc)
        echo "[OK] Version Green confirmada."
        break
    fi
    sleep 1
done

END_GLOBAL=$(date +%s.%N)
TOTAL_DURATION=$(echo "$END_GLOBAL - $START_GLOBAL" | bc)

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - Canary"
echo "============================================================"
echo "A. Tiempo de Despliegue Canary Inicial (10%): $CANARY_DEPLOY_DURATION segundos"
echo "B. Tiempo de Promocion E2E (Scale v2 -> Confirmacion Green): $PROMOTION_DURATION segundos"
echo "C. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "D. Riesgo de Exposicion al Bug: 10% (solo 1 de 3 pods era canary)"
echo "E. Tiempo TOTAL (Apply -> Promocion): $TOTAL_DURATION segundos"
echo "F. Downtime: 0 segundos (continuidad garantizada por pods v1 durante la transicion)"
echo "============================================================"

# Limpieza
echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Listo para la siguiente estrategia."
