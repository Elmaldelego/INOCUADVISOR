#!/bin/bash

# 서버 정보
SERVER_USER="mergefeat"
SERVER_IP="211.243.34.108"
SSH_PORT="2222"
# 대상 이미지 이름
TARGET_IMAGE="ghcr.io/open-webui/open-webui:main"

# 경로
CONTAINER_DATA_PATH="/app/backend/data"
CONTAINER_OPENWEBUI_DATA_PATH="/app/backend/open_webui/data"
HOST_TEMP_PATH="/home/mergefeat/temp_data_sync"
LOCAL_BASE_PATH="/Users/Jiho/Public/hkust-open-webui/backend"

# 인자 확인
ONLY_OPEN_WEBUI=false
if [[ "$1" == "--owui" ]]; then
  ONLY_OPEN_WEBUI=true
fi

# 사용자 확인 프롬프트
echo "🛠  이 작업은 로컬 데이터를 삭제하고 서버에서 복사해옵니다."
if $ONLY_OPEN_WEBUI; then
  echo "📂 open_webui/data 만 동기화합니다."
else
  echo "📂 data 와 open_webui/data 둘 다 동기화합니다."
fi
read -p "계속하시겠습니까? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ 작업이 취소되었습니다."
  exit 1
fi

# sudo 권한 체크
if [[ "$EUID" -ne 0 ]]; then
  echo "🔐 sudo 권한이 필요합니다. 비밀번호를 입력해주세요."
  exec sudo "$0" "$@"
fi

echo "🔄 로컬 디렉토리 삭제 중..."

if $ONLY_OPEN_WEBUI; then
  rm -rf "$LOCAL_BASE_PATH/open_webui/data"
  mkdir -p "$LOCAL_BASE_PATH/open_webui/data"
else
  rm -rf "$LOCAL_BASE_PATH/data"
  rm -rf "$LOCAL_BASE_PATH/open_webui/data"
  mkdir -p "$LOCAL_BASE_PATH/data"
  mkdir -p "$LOCAL_BASE_PATH/open_webui/data"
fi

echo "🚀 서버에서 도커 컨테이너 파일을 호스트로 복사 중..."
ssh -p ${SSH_PORT} -t ${SERVER_USER}@${SERVER_IP} <<EOF
  echo "🔍 ${TARGET_IMAGE} 이미지를 사용하는 컨테이너 ID 찾는 중..."
  CONTAINER_ID=\$(sudo docker ps -q --filter "ancestor=${TARGET_IMAGE}")
  
  if [ -z "\$CONTAINER_ID" ]; then
    echo "❌ ${TARGET_IMAGE} 이미지를 사용하는 실행 중인 컨테이너를 찾을 수 없습니다."
    exit 1
  fi
  
  echo "🔹 컨테이너 ID: \$CONTAINER_ID"
  
  echo "🧼 임시 폴더 정리 중..."
  sudo mkdir -p ${HOST_TEMP_PATH}
  sudo rm -rf ${HOST_TEMP_PATH}/data ${HOST_TEMP_PATH}/open_webui_data

  if $ONLY_OPEN_WEBUI; then
    echo "📦 open_webui/data 가져오는 중..."
    sudo docker cp \$CONTAINER_ID:${CONTAINER_OPENWEBUI_DATA_PATH} ${HOST_TEMP_PATH}/open_webui_data
  else
    echo "📦 전체 데이터 가져오는 중..."
    sudo docker cp \$CONTAINER_ID:${CONTAINER_DATA_PATH} ${HOST_TEMP_PATH}/data
    sudo docker cp \$CONTAINER_ID:${CONTAINER_OPENWEBUI_DATA_PATH} ${HOST_TEMP_PATH}/open_webui_data
  fi
EOF

# SSH 명령의 종료 상태 확인
if [ $? -ne 0 ]; then
  echo "❌ 서버에서 데이터 복사 중 오류가 발생했습니다."
  exit 1
fi

echo "📥 로컬로 복사 중..."
if $ONLY_OPEN_WEBUI; then
  scp -P ${SSH_PORT} -r ${SERVER_USER}@${SERVER_IP}:${HOST_TEMP_PATH}/open_webui_data/* "$LOCAL_BASE_PATH/open_webui/data/"
else
  scp -P ${SSH_PORT} -r ${SERVER_USER}@${SERVER_IP}:${HOST_TEMP_PATH}/data/* "$LOCAL_BASE_PATH/data/"
  scp -P ${SSH_PORT} -r ${SERVER_USER}@${SERVER_IP}:${HOST_TEMP_PATH}/open_webui_data/* "$LOCAL_BASE_PATH/open_webui/data/"
fi

echo "✅ 데이터 동기화 완료!"

# 파일 소유권 변경
echo "🔐 파일 소유권 변경 중..."
sudo chown -R $(whoami) "$LOCAL_BASE_PATH/data"
sudo chown -R $(whoami) "$LOCAL_BASE_PATH/open_webui/data"
echo "✅ 파일 소유권 변경 완료!"

# 데이터베이스 파일 권한 설정
echo "📝 데이터베이스 파일 쓰기 권한 설정 중..."
if $ONLY_OPEN_WEBUI; then
  chmod 666 "$LOCAL_BASE_PATH/open_webui/data/webui.db"*
else
  chmod 666 "$LOCAL_BASE_PATH/data/webui.db"*
  chmod 666 "$LOCAL_BASE_PATH/open_webui/data/webui.db"*
fi
echo "✅ 데이터베이스 파일 권한 설정 완료!"

# 디렉토리 권한 설정
echo "📁 디렉토리 권한 설정 중..."
if $ONLY_OPEN_WEBUI; then
  sudo chmod -R 755 "$LOCAL_BASE_PATH/open_webui/data"
else
  sudo chmod -R 755 "$LOCAL_BASE_PATH/data" "$LOCAL_BASE_PATH/open_webui/data"
fi
echo "✅ 디렉토리 권한 설정 완료!"
