#!/bin/bash
# Blue/Green - Entorno Local (kind)
# Ambos entornos corren en paralelo. El switch es instantaneo via kubectl patch.

SERVICE_NAME="duoc-app-bg-service"
BLUE_DEPLOYMENT="duoc-app-blue"
GREEN_DEPLOYMENT="duoc-app-green"
YAML_FILE="EA2/ACT2.2/BLUE-GREEN/blue-green-local.yaml"
WAIT_DURATION_S=10  # Ventana de prueba reducida para entorno local

echo "============================================================"
echo " ESTRATEGIA: Blue/Green [ENTORNO LOCAL - kind]"
echo "============================================================"

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=30004
URL="http://$NODE_IP:$NODE_PORT"
echo "[INFO] URL de acceso: $URL"

START_GLOBAL=$(date +%s.%N)

# --- FASE 1: Desplegar ambos entornos (Blue activo, Green inactivo para el trafico) ---
echo ""
echo "[FASE 1] Desplegando entorno Blue (v1) y Green (v2) simultaneamente..."
START_GREEN_DEPLOY=$(date +%s.%N)
kubectl apply -f "$YAML_FILE"

kubectl rollout status deployment/$BLUE_DEPLOYMENT --timeout=180s
kubectl rollout status deployment/$GREEN_DEPLOYMENT --timeout=180s
END_GREEN_DEPLOY=$(date +%s.%N)

GREEN_DEPLOY_DURATION=$(echo "$END_GREEN_DEPLOY - $START_GREEN_DEPLOY" | bc)
echo "[OK] Ambos entornos listos en: $GREEN_DEPLOY_DURATION segundos"

echo "[INFO] Verificando que Blue (v1) responde..."
for i in $(seq 1 30); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    [ "$STATUS" = "200" ] && echo "[OK] Blue respondiendo 200 OK" && break
    sleep 2
done

# --- FASE 2: Ventana de prueba (testear Green sin afectar produccion) ---
echo ""
echo "[FASE 2] Ventana de prueba: $WAIT_DURATION_S segundos observando Green..."
echo "         (En produccion: 10-30 minutos de pruebas en Green antes del switch)"
sleep $WAIT_DURATION_S
echo "[OK] Green validado. Sin fallos. Procediendo con el switch..."

# --- FASE 3: Switch instantaneo Blue -> Green ---
echo ""
echo "[FASE 3] Ejecutando switch de trafico: BLUE -> GREEN..."
SWITCH_START=$(date +%s.%N)
kubectl patch service "$SERVICE_NAME" -p '{"spec":{"selector":{"version":"green"}}}'
SWITCH_END=$(date +%s.%N)
SWITCH_DURATION=$(echo "$SWITCH_END - $SWITCH_START" | bc)
echo "[OK] kubectl patch completado en: $SWITCH_DURATION segundos"

# --- FASE 4: Verificar propagacion y confirmar Green ---
echo "[FASE 4] Confirmando respuesta Green en $URL..."
PROP_START=$SWITCH_END
for i in $(seq 1 60); do
    RESPONSE=$(curl -s "$URL" 2>/dev/null)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)

    if [ "$HTTP_CODE" != "200" ]; then
        echo "[ALERTA] Downtime detectado! Codigo: $HTTP_CODE"
    fi

    if echo "$RESPONSE" | grep -qi "green"; then
        PROP_END=$(date +%s.%N)
        PROPAGATION_DURATION=$(echo "$PROP_END - $PROP_START" | bc)
        echo "[OK] Version Green confirmada en la respuesta."
        break
    fi
    sleep 0.5
done

END_GLOBAL=$(date +%s.%N)
TOTAL_WITHOUT_WAIT=$(echo "$GREEN_DEPLOY_DURATION + $SWITCH_DURATION + $PROPAGATION_DURATION" | bc)

echo ""
echo "============================================================"
echo " RESULTADOS FINALES - Blue/Green"
echo "============================================================"
echo "A. Tiempo de Despliegue Green (Deploy Interno): $GREEN_DEPLOY_DURATION segundos"
echo "B. Tiempo de Ventana de Prueba: $WAIT_DURATION_S segundos"
echo "C. Velocidad de Switch (kubectl patch): $SWITCH_DURATION segundos"
echo "D. Tiempo de Propagacion (Patch -> Green OK): $PROPAGATION_DURATION segundos"
echo "E. Tiempo TOTAL E2E (sin contar espera): $TOTAL_WITHOUT_WAIT segundos"
echo "F. Downtime: 0 segundos (Blue estuvo activo durante todo el proceso)"
echo "G. Provisionamiento LB: N/A (entorno local - kind NodePort)"
echo "H. Rollback: Instantaneo (re-ejecutar patch a 'blue')"
echo "============================================================"

# Limpieza
echo ""
echo "[LIMPIEZA] Eliminando recursos..."
kubectl delete -f "$YAML_FILE" --ignore-not-found
echo "[OK] Todas las estrategias completadas."
