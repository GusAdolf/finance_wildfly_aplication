#!/bin/bash

# ---------------------------------------
# Variables de configuración
# ---------------------------------------
WILDFLY_VERSION="34.0.1.Final"
WILDFLY_ZIP_URL="https://github.com/wildfly/wildfly/releases/download/$WILDFLY_VERSION/wildfly-$WILDFLY_VERSION.zip"
INSTALL_DIR="/opt"
WILDFLY_HOME="$INSTALL_DIR/wildfly-$WILDFLY_VERSION"

# Configuración de Oracle
DB_HOST="138.91.238.102"
DB_PORT="1521"
DB_SERVICE="finance"
DB_USER="finance_user"
DB_PASSWORD="StrongPassword"

# Rutas locales
JDBC_DIR="/opt/wildfly/finance_wildfly_aplication/library/jdbc"
DRIVER_JAR="ojdbc8-19.8.0.0.jar"
MODULE_XML="module.xml"
EAR_DIR="/opt/wildfly/finance_wildfly_aplication/library/ear"
EAR_FILE="application_wildfly-ear-1.0-SNAPSHOT.ear"
DEPLOYMENTS_DIR="$WILDFLY_HOME/standalone/deployments"

# ---------------------------------------
# Funciones de validación
# ---------------------------------------
function validar_archivo() {
    local archivo=$1
    if [ ! -f "$archivo" ]; then
        echo ">>> ERROR: No se encontró el archivo requerido: $archivo"
        exit 1
    fi
}

function validar_directorio() {
    local directorio=$1
    if [ ! -d "$directorio" ]; then
        echo ">>> ERROR: No se encontró el directorio requerido: $directorio"
        exit 1
    fi
}

# ---------------------------------------
# Validaciones iniciales
# ---------------------------------------
echo ">>> Validando archivos necesarios..."
validar_archivo "$JDBC_DIR/$DRIVER_JAR"
validar_archivo "$JDBC_DIR/$MODULE_XML"
validar_archivo "$EAR_DIR/$EAR_FILE"

# ---------------------------------------
# 1. Validar conexión a la base de datos
# ---------------------------------------
echo ">>> Validando conexión al host $DB_HOST en el puerto $DB_PORT..."
if ! nc -zv $DB_HOST $DB_PORT; then
    echo ">>> ERROR: No se pudo conectar al host $DB_HOST:$DB_PORT. Verifica la base de datos."
    exit 1
else
    echo ">>> Conexión al host $DB_HOST en el puerto $DB_PORT exitosa."
fi

# ---------------------------------------
# 2. Instalar WildFly si no existe
# ---------------------------------------
if [ -d "$WILDFLY_HOME" ]; then
    echo ">>> Ya existe WildFly en: $WILDFLY_HOME. No se instala de nuevo."
else
    echo ">>> WildFly no está instalado. Descargando e instalando $WILDFLY_VERSION..."
    cd /tmp
    curl -sSL -o "wildfly-$WILDFLY_VERSION.zip" "$WILDFLY_ZIP_URL"

    # Verificación de descarga exitosa
    if [ ! -f "wildfly-$WILDFLY_VERSION.zip" ]; then
        echo ">>> ERROR: No se pudo descargar el archivo wildfly-$WILDFLY_VERSION.zip"
        exit 1
    fi

    unzip -q "wildfly-$WILDFLY_VERSION.zip"
    mv "wildfly-$WILDFLY_VERSION" "$INSTALL_DIR/"
fi

# ---------------------------------------
# 3. Configurar driver Oracle
# ---------------------------------------
ORACLE_MODULE_DIR="$WILDFLY_HOME/modules/system/layers/base/com/oracle/main"
if [ -d "$ORACLE_MODULE_DIR" ]; then
    echo ">>> El driver Oracle ya está configurado en: $ORACLE_MODULE_DIR."
else
    echo ">>> Configurando driver Oracle y module.xml..."
    mkdir -p "$ORACLE_MODULE_DIR"
    cp "$JDBC_DIR/$DRIVER_JAR" "$ORACLE_MODULE_DIR/"
    cp "$JDBC_DIR/$MODULE_XML" "$ORACLE_MODULE_DIR/module.xml"

    # Verificar que los archivos fueron copiados correctamente
    if [ ! -f "$ORACLE_MODULE_DIR/$DRIVER_JAR" ]; then
        echo ">>> ERROR: No se pudo copiar el archivo JAR al directorio del módulo Oracle."
        exit 1
    fi
    if [ ! -f "$ORACLE_MODULE_DIR/module.xml" ]; then
        echo ">>> ERROR: No se pudo copiar module.xml al directorio del módulo Oracle."
        exit 1
    fi
fi

# ---------------------------------------
# 4. Iniciar WildFly en segundo plano
# ---------------------------------------
if pgrep -f "wildfly.*standalone" > /dev/null 2>&1; then
    echo ">>> WildFly ya está en ejecución."
else
    echo ">>> Iniciando WildFly en segundo plano..."

    # Verificar que el directorio de logs existe
    if [ ! -d "$WILDFLY_HOME/standalone/log" ]; then
        mkdir -p "$WILDFLY_HOME/standalone/log"
    fi

    nohup "$WILDFLY_HOME/bin/standalone.sh" -b 0.0.0.0 > "$WILDFLY_HOME/standalone/log/server.log" 2>&1 &
    echo ">>> Esperando 60s para que arranque..."
    sleep 60  # Aumentamos el tiempo de espera para asegurar que WildFly esté listo
fi

# ---------------------------------------
# 5. Verificar disponibilidad de la CLI de WildFly
# ---------------------------------------
echo ">>> Verificando si la CLI de WildFly está disponible..."
RETRIES=5
for ((i=1; i<=RETRIES; i++)); do
    if $WILDFLY_HOME/bin/jboss-cli.sh --connect --commands="version" > /dev/null 2>&1; then
        echo ">>> La CLI de WildFly está disponible."
        break
    else
        if [ $i -eq $RETRIES ]; then
            echo ">>> ERROR: La CLI de WildFly no está disponible después de $RETRIES intentos."
            exit 1
        fi
        echo ">>> Intentando nuevamente ($i/$RETRIES)..."
        sleep 10
    fi
done

# ---------------------------------------
# 6. Registrar el driver Oracle
# ---------------------------------------
echo ">>> Registrando el driver Oracle en WildFly..."
$WILDFLY_HOME/bin/jboss-cli.sh --connect <<EOF
/subsystem=datasources/jdbc-driver=com.oracle:add(driver-name="com.oracle", driver-module-name="com.oracle", driver-class-name="oracle.jdbc.driver.OracleDriver")
EOF

# ---------------------------------------
# 7. Crear el DataSource
# ---------------------------------------
echo ">>> Creando el DataSource FinanceDS..."
$WILDFLY_HOME/bin/jboss-cli.sh --connect <<EOF
batch
data-source add \
    --name=FinanceDS \
    --jndi-name=java:/jdbc/FinanceDS \
    --driver-name=com.oracle \
    --connection-url=jdbc:oracle:thin:@//$DB_HOST:$DB_PORT/$DB_SERVICE \
    --user-name=$DB_USER \
    --password=$DB_PASSWORD \
    --min-pool-size=5 \
    --max-pool-size=20 \
    --blocking-timeout-wait-millis=5000
run-batch
EOF

# Validar la conexión al DataSource
echo ">>> Probando la conexión del DataSource FinanceDS..."
if "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="data-source test-connection-in-pool --name=FinanceDS" | grep -q "true"; then
    echo ">>> Conexión al DataSource FinanceDS exitosa."
else
    echo ">>> ERROR: La conexión al DataSource FinanceDS falló. Verifica los parámetros y la conectividad."
    exit 1
fi

# ---------------------------------------
# 8. Desplegar EAR
# ---------------------------------------
echo ">>> Copiando el EAR al directorio de despliegue..."
if [ ! -f "$DEPLOYMENTS_DIR/$EAR_FILE" ]; then
    cp "$EAR_DIR/$EAR_FILE" "$DEPLOYMENTS_DIR/"
    echo ">>> EAR copiado a $DEPLOYMENTS_DIR/"
else
    echo ">>> El EAR ya existe en $DEPLOYMENTS_DIR. No se copia de nuevo."
fi

# ---------------------------------------
# Final
# ---------------------------------------
echo ">>> Script completado. WildFly configurado y EAR copiado al directorio de despliegue."
echo ">>> Revisa los logs en: $WILDFLY_HOME/standalone/log/server.log"
