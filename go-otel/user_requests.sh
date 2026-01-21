#!/bin/bash

# Define server URL
SERVER_URL="http://localhost:${GO_DEMO_SERVER_PORT:-8080}"

# 预定义一些常见英文名字
NAMES=(
  "James" "John" "Robert" "Michael" "William" "David" "Richard" "Joseph" "Thomas" "Charles"
  "Mary" "Patricia" "Jennifer" "Linda" "Elizabeth" "Barbara" "Susan" "Jessica" "Sarah" "Karen"
)

# 用于跟踪创建的用户
USERS=()

# Function to generate random number between min and max
random_between() {
  min=$1
  max=$2
  # Ensure max is at least min to avoid division by zero
  if [ $max -lt $min ]; then
    max=$min
  fi
  range=$(( $max - $min + 1 ))
  # Ensure range is at least 1 to avoid modulo by zero
  if [ $range -le 0 ]; then
    echo $min
  else
    echo $(( $min + RANDOM % $range ))
  fi
}

# Function to generate random user data
generate_user_data() {
  # 从预定义列表中随机选择一个名字
  local idx=$(random_between 0 $(( ${#NAMES[@]} - 1 )) )
  local name="${NAMES[$idx]}"
  
  local gender=$([[ $(random_between 1 2) -eq 1 ]] && echo "male" || echo "female")
  local phone="1$(random_between 3000000000 9999999999)"
  local email="${name}@example.com"
  local age=$(random_between 18 80)
  
  echo "{\"name\":\"${name}\",\"gender\":\"${gender}\",\"phone\":\"${phone}\",\"email\":\"${email}\",\"age\":${age}}"
}

# Function to make a request to create user endpoint
create_user() {
  local user_data=$(generate_user_data)
  echo "Creating user: ${user_data}"
  
  # 提取名字和电话号码，用于后续查询
  local name=$(echo "$user_data" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
  local phone=$(echo "$user_data" | grep -o '"phone":"[^"]*' | cut -d'"' -f4)
  
  # 发送创建用户请求
  local response=$(curl -s -X POST -H "Content-Type: application/json" -d "${user_data}" "${SERVER_URL}/user")
  echo "${response}"
  
  # 如果响应不包含error，则认为创建成功，添加到用户列表
  if [[ ! "$response" == *"error"* ]]; then
    # 保存为 "name|phone" 格式
    USERS+=("${name}|${phone}")
    echo "Added user to tracking: ${name}|${phone}"
  fi
  
  echo ""
}

# Function to make a request to get user endpoint
get_user() {
  # 如果没有创建用户，先创建一个
  if [ ${#USERS[@]} -eq 0 ]; then
    echo "No users yet, creating first user..."
    create_user
    sleep 1
  fi
  
  # 如果还是没有用户，跳过查询
  if [ ${#USERS[@]} -eq 0 ]; then
    echo "Still no users available, skipping get request"
    return
  fi
  
  # 随机选择一个用户
  local idx=$(random_between 0 $(( ${#USERS[@]} - 1 )) )
  local user_info="${USERS[$idx]}"
  
  # 分割用户信息
  local name=$(echo "$user_info" | cut -d'|' -f1)
  local phone=$(echo "$user_info" | cut -d'|' -f2)
  
  # 确保名字和电话号码没有特殊字符
  name=$(echo "$name" | sed 's/[^a-zA-Z0-9]/_/g')
  phone=$(echo "$phone" | sed 's/[^0-9]/_/g')
  
  # 随机选择查询方式
  if [[ $(random_between 1 2) -eq 1 ]]; then
    # 用名字查询，确保URL安全
    echo "Getting user by name: ${name}"
    curl -s -X GET "${SERVER_URL}/user?name=${name}"
  else
    # 用电话查询，确保URL安全
    echo "Getting user by phone: ${phone}"
    curl -s -X GET "${SERVER_URL}/user?phone=${phone}"
  fi
  echo ""
}

# Function to make a request to list users endpoint
list_users() {
  echo "Listing users"
  curl -s -X GET "${SERVER_URL}/users"
  echo ""
}

# 创建初始用户前先清空数组
USERS=()

# Create a few initial users to have some data
echo "Creating initial users..."
for i in {1..3}; do
  create_user
  sleep 1
done

echo "Tracked users count: ${#USERS[@]}"
echo "Tracked users: ${USERS[@]}"

# Main loop
while true; do
  # Determine number of requests for this minute (10-20)
  num_requests=$(random_between 10 20)
  echo "Making ${num_requests} requests this minute"
  
  # Calculate sleep interval
  sleep_interval=$(echo "scale=3; 60 / ${num_requests}" | bc)
  
  for ((i=1; i<=${num_requests}; i++)); do
    # Randomly choose which endpoint to request
    endpoint_choice=$(random_between 1 3)
    
    case ${endpoint_choice} in
      1)
        create_user
        ;;
      2)
        get_user
        ;;
      3)
        list_users
        ;;
    esac
    
    # Sleep for calculated interval
    sleep ${sleep_interval}
  done
done 
