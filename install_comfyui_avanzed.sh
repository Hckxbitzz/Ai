#!/bin/bash

# ==================================================
# INSTALADOR COMFYUI AVANZADO (SDXL + VAEs + Flux + OpenPose + WAN)
# ==================================================

# Configuración (¡Actualiza estos valores!)
NGROK_TOKEN="tu_token_ngrok"              # Token de Ngrok
VOLUME_DIR="/workspace/comfy-data"        # Carpeta persistente
COMFYUI_DIR="/workspace/ComfyUI"          # Ruta de instalación
PORT=8188                                 # Puerto para ComfyUI

# Colores para mensajes
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Función de manejo de errores
check_error() {
  [ $? -ne 0 ] && echo -e "${RED}[ERROR] $1${NC}" && exit 1
}

# ======================
# 1. VERIFICACIONES INICIALES
# ======================
echo -e "${YELLOW}[1/8] Verificando sistema...${NC}"
nvidia-smi || check_error "No se detectó GPU NVIDIA"
[ ! -d "$VOLUME_DIR" ] && mkdir -p "$VOLUME_DIR"

# ======================
# 2. INSTALAR NGROK
# ======================
echo -e "${YELLOW}[2/8] Configurando Ngrok...${NC}"
if [ ! -f "./ngrok" ]; then
  wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
  tar -xzf ngrok-v3-stable-linux-amd64.tgz
  chmod +x ngrok
  ./ngrok authtoken "$NGROK_TOKEN" || check_error "Token Ngrok inválido"
fi

# ======================
# 3. INSTALAR COMFYUI + SDXL
# ======================
echo -e "${YELLOW}[3/8] Instalando ComfyUI...${NC}"
cd /workspace
if [ ! -d "$COMFYUI_DIR" ]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git || check_error "Error al clonar ComfyUI"
  cd "$COMFYUI_DIR"
  pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118
else
  cd "$COMFYUI_DIR" && git pull
fi
pip install -r requirements.txt --upgrade || check_error "Error en dependencias"

# ======================
# 4. CONFIGURAR PERSISTENCIA
# ======================
echo -e "${YELLOW}[4/8] Configurando persistencia...${NC}"
mkdir -p "$VOLUME_DIR"/{models/{checkpoints,vae,controlnet,loras},outputs,inputs,workflows,custom_nodes}
for dir in models outputs inputs workflows custom_nodes; do
  rm -rf "$COMFYUI_DIR/$dir"
  ln -s "$VOLUME_DIR/$dir" "$COMFYUI_DIR/$dir" || check_error "Error enlazando $dir"
done

# ======================
# 5. DESCARGAR MODELOS (SDXL + VAEs)
# ======================
echo -e "${YELLOW}[5/8] Descargando modelos...${NC}"

# 5.1 Modelos SDXL base
wget -P "$VOLUME_DIR/models/checkpoints" \
  https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors

wget -P "$VOLUME_DIR/models/checkpoints" \
  https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors

# 5.2 VAEs recomendados para SDXL
wget -P "$VOLUME_DIR/models/vae" \
  https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors

wget -P "$VOLUME_DIR/models/vae" \
  https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors

# 5.3 OpenPose (ControlNet)
wget -P "$VOLUME_DIR/models/controlnet" \
  https://huggingface.co/webui/ControlNet-modules-safetensors/resolve/main/control_openpose-fp16.safetensors

# ======================
# 6. INSTALAR COMPONENTES CLAVE
# ======================
echo -e "${YELLOW}[6/8] Instalando componentes...${NC}"

# 6.1 ComfyUI Manager
cd "$COMFYUI_DIR/custom_nodes"
[ ! -d "ComfyUI-Manager" ] && git clone https://github.com/ltdrdata/ComfyUI-Manager.git

# 6.2 Flux Sampler
[ ! -d "ComfyUI-Flux" ] && git clone https://github.com/BlenderNeko/ComfyUI-Flux.git

# 6.3 WAN (Weighted Average Noise)
[ ! -d "ComfyUI-WAN" ] && git clone https://github.com/BlenderNeko/ComfyUI-WAN.git

# 6.4 OpenPose Preprocessor
[ ! -d "comfy_controlnet_preprocessors" ] && git clone https://github.com/Fannovel16/comfy_controlnet_preprocessors.git

# ======================
# 7. INSTALAR DEPENDENCIAS
# ======================
echo -e "${YELLOW}[7/8] Instalando dependencias...${NC}"
cd "$COMFYUI_DIR"
pip install opencv-python scipy git+https://github.com/facebookresearch/segment-anything.git || check_error "Error en dependencias"

# ======================
# 8. INICIAR SERVICIOS
# ======================
echo -e "${YELLOW}[8/8] Iniciando servicios...${NC}"

# Configurar autenticación
echo -e "${YELLOW}¿Proteger con usuario/contraseña? (y/n)${NC}"
read -r use_auth
if [[ "$use_auth" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Usuario:${NC}" && read -r auth_user
  echo -e "${YELLOW}Contraseña:${NC}" && read -r auth_pass
  AUTH_ARGS="--enable-auth --username $auth_user --password $auth_pass"
fi

# Iniciar servicios
screen -dmS comfyui bash -c "cd $COMFYUI_DIR && python main.py --listen 0.0.0.0 --port $PORT $AUTH_ARGS"
screen -dmS ngrok bash -c "./ngrok http $PORT"

# Mostrar resultados
sleep 5
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url')

echo -e "${GREEN}\n✔ Instalación completada!${NC}"
echo -e "========================================"
echo -e "${YELLOW}ACCESO:${NC}"
echo -e "URL Ngrok: ${GREEN}$NGROK_URL${NC}"
echo -e "URL RunPod: ${GREEN}https://${RUNPOD_POD_ID}-${PORT}.proxy.runpod.net${NC}"
echo -e ""
echo -e "${YELLOW}MODELOS INSTALADOS:${NC}"
echo -e "- SDXL Base: ${GREEN}$VOLUME_DIR/models/checkpoints/sd_xl_base_1.0.safetensors${NC}"
echo -e "- SDXL Refiner: ${GREEN}$VOLUME_DIR/models/checkpoints/sd_xl_refiner_1.0.safetensors${NC}"
echo -e "- VAEs:"
echo -e "  - SDXL VAE: ${GREEN}$VOLUME_DIR/models/vae/sdxl_vae.safetensors${NC}"
echo -e "  - Ollin VAE (FP16 fix): ${GREEN}$VOLUME_DIR/models/vae/sdxl_vae.safetensors${NC}"
echo -e "- OpenPose: ${GREEN}$VOLUME_DIR/models/controlnet/control_openpose-fp16.safetensors${NC}"
echo -e "========================================"
echo -e "${YELLOW}COMPONENTES:${NC}"
echo -e "- Flux Sampler"
echo -e "- WAN Mixer"
echo -e "- ComfyUI Manager"
echo -e "========================================"