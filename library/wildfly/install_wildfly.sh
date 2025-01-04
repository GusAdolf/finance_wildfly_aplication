#!/bin/bash
#
# install_wildfly.sh
#
# Este script:
# 1. Descarga e instala WildFly en /opt
# 2. Copia el driver Oracle (ojdbc8.jar) y module.xml
# 3. Crea el DataSource FinanceDS
# 4. Despliega el EAR que tienes en ../ear/application_wildfly-ear-1.0-SNAPSHOT.ear
#
# Requisitos:
# - La VM debe tener Java 11 instalado.
# - Se ejecuta preferiblemente como root o con sudo si escribes en /opt.
#
set -e  # si algo falla, se detiene

# ---------------------------------------
# VARIABLES
# ---------------------------------------
WILDFLY_VERSION="28.0.2.Final"
WILDFLY_ZIP_URL="https://github.com/wildfly/wildfly/releases/download/$WILDFLY_VERSION/wildfly-$WILDFLY_VERSION.zip"
INSTALL_DIR="/opt"
WILDFLY_HOME="$INSTALL_DIR/wildfly-$WILDFLY_VERSION"

# Ajusta la IP/Puerto/SID/Usuario de la BD Oracle:
DB_HOST="0.0.0.0"     # IP donde está Oracle
DB_PORT="1521"
DB_SERVICE="finance"
DB_USER="finance_user"
DB_PASSWORD="StrongPassword"

# Paths relativos en tu repo (respecto a este script)
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"        # carpeta .../library/wildfly
JDBC_DIR="$SCRIPT_DIR/../jdbc"                   # carpeta .../library/jdbc
EAR_DIR="$SCRIPT_DIR/../ear"                     # carpeta .../library/ear

# Nombres de archivos
DRIVER_JAR="ojdbc8-19.8.0.0.jar"
MODULE_XML="module.xml"
EAR_FILE="application_wildfly-ear-1.0-SNAPSHOT.ear"

# ---------------------------------------
# 1. Descarga e instala WildFly
# ---------------------------------------
echo ">>> Descargando WildFly $WILDFLY_VERSION..."
cd /tmp
curl -sS -OL "$WILDFLY_ZIP_URL"

echo ">>> Descomprimiendo en $INSTALL_DIR..."
unzip -q "wildfly-$WILDFLY_VERSION.zip"
mv "wildfly-$WILDFLY_VERSION" "$INSTALL_DIR/"

# (Opcional) Renombrar si prefieres /opt/wildfly
# mv "$INSTALL_DIR/wildfly-$WILDFLY_VERSION" "$INSTALL_DIR/wildfly"
# WILDFLY_HOME="$INSTALL_DIR/wildfly"

# ---------------------------------------
# 2. Instalar driver Oracle en WildFly
# ---------------------------------------
echo ">>> Configurando driver Oracle..."
mkdir -p "$WILDFLY_HOME/modules/system/layers/base/com/oracle/main"

cp "$JDBC_DIR/$DRIVER_JAR"  "$WILDFLY_HOME/modules/system/layers/base/com/oracle/main/"
cp "$JDBC_DIR/$MODULE_XML"  "$WILDFLY_HOME/modules/system/layers/base/com/oracle/main/module.xml"

# ---------------------------------------
# 3. Arrancar WildFly
# ---------------------------------------
echo ">>> Iniciando WildFly en segundo plano..."
"$WILDFLY_HOME/bin/standalone.sh" -b 0.0.0.0 &

# Esperamos ~10s para que levante:
echo ">>> Esperando 10s para que arranque..."
sleep 10

# ---------------------------------------
# 4. Registrar driver y DataSource
# ---------------------------------------
echo ">>> Configurando DataSource FinanceDS..."
"$WILDFLY_HOME/bin/jboss-cli.sh" --connect <<EOF
subsystem=datasources/jdbc-driver=com.oracle:add(driver-name="com.oracle",driver-module-name="com.oracle",driver-class-name="oracle.jdbc.driver.OracleDriver")

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

data-source test-connection-in-pool --name=FinanceDS
EOF

# ---------------------------------------
# 5. Desplegar el EAR
# ---------------------------------------
if [ ! -f "$EAR_DIR/$EAR_FILE" ]; then
  echo ">>> ERROR: no se encontró el EAR en $EAR_DIR/$EAR_FILE"
  exit 1
fi

echo ">>> Desplegando EAR: $EAR_DIR/$EAR_FILE"
"$WILDFLY_HOME/bin/jboss-cli.sh" --connect --command="deploy $EAR_DIR/$EAR_FILE --force"

# ---------------------------------------
# Final
# ---------------------------------------
echo ">>> WildFly instalado y EAR desplegado con éxito."
echo ">>> Revisa logs en: $WILDFLY_HOME/standalone/log/server.log"
