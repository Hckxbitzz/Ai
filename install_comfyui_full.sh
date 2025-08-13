#!/bin/bash

# ==================================================
# INSTALADOR COMFYUI + PERSISTENCIA + NGROK + MANAGER + LoRA POPYAYS
# ==================================================

# Configuración (¡Edita esto!)
NGROK_TOKEN="tu_token_ngrok"  # Consíguelo en https://ngrok.com/
VOLUME_DIR="/workspace/comfy-data"  # Carpeta persistente
COMFYUI_DIR="/workspace/ComfyUI"
PORT=8188

# Colores
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Función de errores
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
  fi
}

# ======================
# 1. VERIFICACIONES INICIALES
# ======================
echo -e "${YELLOW}[1/6] Verificando sistema...${NC}"
nvidia-smi || check_error "No hay GPU NVIDIA detectada"
[ ! -d "$VOLUME_DIR" ] && mkdir -p "$VOLUME_DIR"

# ======================
# 2. INSTALAR NGROK
# ======================
echo -e "${YELLOW}[2/6] Configurando Ngrok...${NC}"
if [ ! -f "./ngrok" ]; then
  wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
  tar -xzf ngrok-v3-stable-linux-amd64.tgz
  chmod +x ngrok
  ./ngrok authtoken "$NGROK_TOKEN" || check_error "Token Ngrok inválido"
fi

# ======================
# 3. INSTALAR COMFYUI
# ======================
echo -e "${YELLOW}[3/6] Instalando ComfyUI...${NC}"
cd /workspace
if [ ! -d "$COMFYUI_DIR" ]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git || check_error "Error al clonar ComfyUI"
else
  echo -e "${GREEN}✔ ComfyUI ya existe, actualizando...${NC}"
  cd "$COMFYUI_DIR" && git pull
fi

# Instalar dependencias base
cd "$COMFYUI_DIR"
pip install -r requirements.txt --upgrade || check_error "Error al instalar dependencias"

# ======================
# 4. CONFIGURAR PERSISTENCIA
# ======================
echo -e "${YELLOW}[4/6] Configurando persistencia...${NC}"
mkdir -p "$VOLUME_DIR"/{models,outputs,inputs,workflows,extras,custom_nodes}
for dir in models outputs inputs workflows extras custom_nodes; do
  rm -rf "$COMFYUI_DIR/$dir"
  ln -s "$VOLUME_DIR/$dir" "$COMFYUI_DIR/$dir" || check_error "Error al enlazar $dir"
done

# ======================
# 5. INSTALAR EXTRAS
# ======================
echo -e "${YELLOW}[5/6] Instalando extras...${NC}"

# 5.1 ComfyUI Manager
cd "$COMFYUI_DIR/custom_nodes"
if [ ! -d "ComfyUI-Manager" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git || check_error "Error al clonar Manager"
  cd ComfyUI-Manager && pip install -r requirements.txt
else
  echo -e "${GREEN}✔ Manager ya instalado${NC}"
fi

# 5.2 LoRA Popyays (y dependencias)
cd "$COMFYUI_DIR/custom_nodes"
if [ ! -d "comfyui_poppyays" ]; then
  git clone https://github.com/Popyays/comfyui_poppyays.git || check_error "Error al clonar Popyays"
  cd comfyui_poppyays
  pip install -r requirements.txt || check_error "Error al instalar dependencias de Popyays"
  # Descargar LoRA Popyays (ejemplo)
  mkdir -p "$VOLUME_DIR/models/loras"
  wget -P "$VOLUME_DIR/models/loras" https://huggingface.co/Popyays/LoRAs/resolve/main/popyays_sdxl.safetensors
else
  echo -e "${GREEN}✔ Popyays ya instalado${NC}"
fi

# ======================
# 6. INICIAR SERVICIOS
# ======================
echo -e "${YELLOW}[6/6] Iniciando servicios...${NC}"

# Configurar autenticación
echo -e "${YELLOW}¿Quieres proteger con usuario/contraseña? (y/n)${NC}"
read -r use_auth
if [[ "$use_auth" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Usuario:${NC}" && read -r auth_user
  echo -e "${YELLOW}Contraseña:${NC}" && read -r auth_pass
  AUTH_ARGS="--enable-auth --username $auth_user --password $auth_pass"
fi

# Iniciar ComfyUI y Ngrok en screen
screen -dmS comfyui bash -c "cd $COMFYUI_DIR && python main.py --listen 0.0.0.0 --port $PORT $AUTH_ARGS"
screen -dmS ngrok bash -c "./ngrok http $PORT"

# Esperar y mostrar URL
sleep 5
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')

# ======================
# RESULTADOS
# ======================
echo -e "${GREEN}\n✔ Instalación completada!${NC}"
echo -e "========================================"
echo -e "${YELLOW}ACCESO:${NC}"
echo -e "URL Ngrok: ${GREEN}$NGROK_URL${NC}"
echo -e "URL RunPod: ${GREEN}https://${RUNPOD_POD_ID}-${PORT}.proxy.runpod.net${NC}"
echo -e ""
echo -e "${YELLOW}DIRECTORIOS:${NC}"
echo -e "Modelos: ${GREEN}$VOLUME_DIR/models${NC}"
echo -e "LoRAs: ${GREEN}$VOLUME_DIR/models/loras${NC}"
echo -e "Outputs: ${GREEN}$VOLUME_DIR/outputs${NC}"
echo -e "========================================"
echo -e "${YELLOW}GESTIÓN:${NC}"
echo -e "Ver sesiones: ${GREEN}screen -ls${NC}"
echo -e "Reiniciar: ${GREEN}pkill -f 'python main.py' && ./ngrok http $PORT${NC}"
